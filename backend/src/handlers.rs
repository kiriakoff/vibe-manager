use std::convert::Infallible;

use async_stream::stream;
use axum::extract::{Path, State};
use axum::http::header;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::IntoResponse;
use axum::Json;
use futures::Stream;
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::apps::{self, AppInfo};
use crate::auth::{self, CurrentUser};
use crate::docker;
use crate::error::ApiError;
use crate::preview;
use crate::AppState;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct LoginResponse {
    pub access_token: String,
    pub token_type: String,
}

#[derive(Serialize)]
pub struct AppListResponse {
    pub apps: Vec<AppInfo>,
}

#[derive(Serialize)]
pub struct ActionResponse {
    pub success: bool,
    pub message: String,
}

/// Reject invalid FQDN path params early (also prevents shell injection in docker calls).
fn require_fqdn(fqdn: &str) -> Result<(), ApiError> {
    if apps::is_valid_fqdn(fqdn) {
        Ok(())
    } else {
        Err(ApiError::not_found("Application not found"))
    }
}

// POST /auth/login
pub async fn login(
    State(state): State<AppState>,
    Json(request): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, ApiError> {
    let users = auth::load_users(&state.users_file());
    if !auth::authenticate(&request.username, &request.password, &users) {
        return Err(ApiError::unauthorized("Incorrect username or password"));
    }
    let token = auth::create_token(&request.username, &state.jwt_secret, state.jwt_expiration_hours)
        .map_err(|e| ApiError::internal(format!("token creation failed: {e}")))?;
    Ok(Json(LoginResponse {
        access_token: token,
        token_type: "bearer".to_string(),
    }))
}

// GET /api/apps
pub async fn list_apps(
    State(state): State<AppState>,
    user: CurrentUser,
) -> Result<Json<AppListResponse>, ApiError> {
    tracing::info!("Listing apps for user: {}", user.0);
    let apps_list = apps::scan_apps(&state, &user.0).await;
    Ok(Json(AppListResponse { apps: apps_list }))
}

// POST /api/apps/{fqdn}/start
pub async fn start_app(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(fqdn): Path<String>,
) -> Result<Json<ActionResponse>, ApiError> {
    require_fqdn(&fqdn)?;
    tracing::info!("Starting app: {fqdn} for user: {}", user.0);

    // Owner: the user themselves; admin uses the fqdn as owner id (flat structure).
    let (owner, app_path) = if user.0 == "admin" {
        ("admin".to_string(), apps::app_dir(&state, &fqdn))
    } else {
        (user.0.clone(), apps::app_dir(&state, &fqdn))
    };

    if !apps::path_exists(&app_path) {
        tracing::warn!("App directory does not exist: {}", app_path.display());
        return Err(ApiError::not_found("Application directory not found"));
    }

    docker::start_app(&state, &fqdn, &owner)
        .await
        .map_err(|e| {
            tracing::error!("Failed to start application {fqdn}: {e}");
            ApiError::internal("Failed to start application")
        })?;

    // Refresh preview after a successful start (container should be running now).
    tracing::info!("Refreshing preview for {fqdn}");
    preview::refresh(&state, &fqdn, true).await;

    tracing::info!("Application {fqdn} started successfully");
    Ok(Json(ActionResponse {
        success: true,
        message: format!("Application {fqdn} started"),
    }))
}

// POST /api/apps/{fqdn}/stop
pub async fn stop_app(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(fqdn): Path<String>,
) -> Result<Json<ActionResponse>, ApiError> {
    require_fqdn(&fqdn)?;
    tracing::info!("Stopping app: {fqdn} for user: {}", user.0);

    // Admin resolves the owner from the container label, falling back to the dir.
    let owner = if user.0 == "admin" {
        let labeled = docker::vibe_containers()
            .await
            .into_iter()
            .find(|c| c.fqdn == fqdn)
            .filter(|c| c.owner != "unknown")
            .map(|c| c.owner);

        match labeled {
            Some(owner) => {
                tracing::debug!("Found running container {fqdn}, owner={owner}");
                owner
            }
            None => {
                let dir = apps::app_dir(&state, &fqdn);
                if dir.exists() {
                    tracing::debug!("Found app directory, owner={fqdn}");
                    fqdn.clone()
                } else {
                    tracing::warn!("Cannot determine owner for {fqdn}");
                    return Err(ApiError::not_found("Application not found"));
                }
            }
        }
    } else {
        user.0.clone()
    };

    docker::stop_app(&state, &fqdn, &owner)
        .await
        .map_err(|e| {
            tracing::error!("Failed to stop application {fqdn}: {e}");
            ApiError::internal("Failed to stop application")
        })?;

    tracing::info!("Application {fqdn} stopped successfully");
    Ok(Json(ActionResponse {
        success: true,
        message: format!("Application {fqdn} stopped"),
    }))
}

// GET /api/apps/{fqdn}/logs (SSE, live follow)
pub async fn logs(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(fqdn): Path<String>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    require_fqdn(&fqdn)?;

    // Ownership check for non-admin users.
    if user.0 != "admin" && !apps::app_dir_exists(&state, &fqdn) {
        return Err(ApiError::not_found("Application not found"));
    }

    let exists = docker::container_status(&fqdn).await != "not found";
    let fqdn_clone = fqdn.clone();

    let stream = stream! {
        if !exists {
            yield Ok(Event::default().data("Container not found"));
            yield Ok(Event::default().data("[DONE]"));
            return;
        }

        let mut child = match docker::spawn_log_follow(&fqdn_clone) {
            Ok(child) => child,
            Err(e) => {
                yield Ok(Event::default().data(format!("Error getting logs: {e}")));
                yield Ok(Event::default().data("[DONE]"));
                return;
            }
        };

        // Live-follow the logs; the child is killed when the stream is
        // dropped (client disconnected / modal closed).
        if let Some(mut lines) = docker::take_log_lines(&mut child) {
            while let Ok(Some(line)) = lines.next_line().await {
                yield Ok(Event::default().data(line));
            }
        }
        yield Ok(Event::default().data("[DONE]"));
    };

    Ok(Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(std::time::Duration::from_secs(15))
            .text("ping"),
    ))
}

// GET /api/apps/{fqdn}/status
pub async fn app_status(
    State(_state): State<AppState>,
    _user: CurrentUser,
    Path(fqdn): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_fqdn(&fqdn)?;
    let status = docker::container_status(&fqdn).await;
    Ok(Json(json!({ "fqdn": fqdn, "status": status })))
}

// GET /api/previews/{fqdn} (public: consumed via <img> tags)
pub async fn get_preview(
    State(state): State<AppState>,
    Path(fqdn): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    require_fqdn(&fqdn)?;
    let path = state.preview_path(&fqdn);
    if !path.is_file() {
        return Err(ApiError::not_found("Preview not found"));
    }
    let bytes = tokio::fs::read(&path)
        .await
        .map_err(|_| ApiError::not_found("Preview not found"))?;
    Ok(([(header::CONTENT_TYPE, "image/png")], bytes))
}

// POST /api/previews/{fqdn}/refresh
pub async fn refresh_preview(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(fqdn): Path<String>,
) -> Result<Json<ActionResponse>, ApiError> {
    require_fqdn(&fqdn)?;
    tracing::info!("Refreshing preview for: {fqdn}");

    if user.0 == "admin" {
        let labeled = docker::vibe_containers()
            .await
            .into_iter()
            .find(|c| c.fqdn == fqdn)
            .filter(|c| c.owner != "unknown")
            .map(|c| c.owner);
        if labeled.is_none() && !apps::app_dir(&state, &fqdn).exists() {
            tracing::warn!("Cannot determine owner for {fqdn}");
            return Err(ApiError::not_found("Application not found"));
        }
    }

    let running = docker::container_status(&fqdn).await == "running";
    let screenshot_ok = preview::refresh(&state, &fqdn, running).await;

    if screenshot_ok {
        Ok(Json(ActionResponse {
            success: true,
            message: format!("Preview refreshed for {fqdn}"),
        }))
    } else {
        Ok(Json(ActionResponse {
            success: false,
            message: "Could not generate preview".to_string(),
        }))
    }
}

// GET /api/status
pub async fn api_status() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok", "version": VERSION }))
}
