pub mod apps;
pub mod auth;
pub mod config;
pub mod docker;
pub mod error;
pub mod handlers;
pub mod preview;

use std::sync::Arc;

use axum::routing::{get, post};
use axum::Router;

use crate::config::Settings;

pub type AppState = Arc<Settings>;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/auth/login", post(handlers::login))
        .route("/api/apps", get(handlers::list_apps))
        .route("/api/apps/{fqdn}/start", post(handlers::start_app))
        .route("/api/apps/{fqdn}/stop", post(handlers::stop_app))
        .route("/api/apps/{fqdn}/logs", get(handlers::logs))
        .route("/api/apps/{fqdn}/status", get(handlers::app_status))
        .route("/api/previews/{fqdn}", get(handlers::get_preview))
        .route(
            "/api/previews/{fqdn}/refresh",
            post(handlers::refresh_preview),
        )
        .route("/api/status", get(handlers::api_status))
        .with_state(state)
}
