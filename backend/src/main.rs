use std::net::SocketAddr;
use std::sync::Arc;

use tower_http::cors::CorsLayer;
use tower_http::services::{ServeDir, ServeFile};
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

use vibe_manager::config::Settings;
use vibe_manager::handlers;
use vibe_manager::AppState;

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,vibe_manager=debug,tower_http=info")),
        )
        .init();

    let settings = Settings::from_env();
    let port = settings.port;

    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
        .block_on(run(settings, port));
}

async fn run(settings: Settings, port: u16) {
    let state: AppState = Arc::new(settings.clone());

    // SPA fallback: serve the built Flutter app, index.html for unknown paths.
    let static_dir = settings.static_dir.clone();
    let spa = ServeDir::new(&static_dir)
        .append_index_html_on_directories(true)
        .fallback(ServeFile::new(static_dir.join("index.html")));

    let app = vibe_manager::router(state)
        .layer(CorsLayer::very_permissive())
        .layer(TraceLayer::new_for_http())
        .fallback_service(spa);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Vibe Manager v{} listening on http://{addr}", handlers::VERSION);
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind port");
    axum::serve(listener, app).await.expect("server error");
}
