use std::io::BufWriter;
use std::path::Path;
use std::time::Duration;

use tokio::process::Command;
use tokio::time::timeout;

use crate::config::Settings;

const SCREENSHOT_TIMEOUT: Duration = Duration::from_secs(60);
const WIDTH: u32 = 1280;
const HEIGHT: u32 = 720;

/// Screenshot the app's public site with headless chromium (16:9 preview).
pub async fn generate_screenshot(settings: &Settings, fqdn: &str) -> bool {
    let path = settings.preview_path(fqdn);
    if let Some(parent) = path.parent() {
        if let Err(e) = tokio::fs::create_dir_all(parent).await {
            tracing::warn!("Failed to create previews dir {}: {e}", parent.display());
            return false;
        }
    }

    let url = format!("http://{fqdn}");
    let output = timeout(
        SCREENSHOT_TIMEOUT,
        Command::new("chromium")
            .args([
                "--headless",
                "--disable-gpu",
                "--no-sandbox",
                "--hide-scrollbars",
            ])
            .arg(format!("--screenshot={}", path.display()))
            .arg(format!("--window-size={WIDTH},{HEIGHT}"))
            .arg(&url)
            .output(),
    )
    .await;

    match output {
        Ok(Ok(out)) if out.status.success() => {
            tracing::info!("Preview generated for {fqdn}");
            true
        }
        Ok(Ok(out)) => {
            tracing::warn!(
                "Preview generation failed for {fqdn}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            );
            false
        }
        Ok(Err(e)) => {
            tracing::warn!("Preview generation error for {fqdn}: {e}");
            false
        }
        Err(_) => {
            tracing::warn!("Preview generation timed out for {fqdn}");
            false
        }
    }
}

/// Write a solid slate-colored placeholder PNG (fallback when chromium fails).
pub fn write_placeholder(settings: &Settings, fqdn: &str) -> bool {
    let path = settings.preview_path(fqdn);
    if let Some(parent) = path.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            tracing::warn!("Failed to create previews dir {}: {e}", parent.display());
            return false;
        }
    }

    let file = match std::fs::File::create(&path) {
        Ok(f) => f,
        Err(e) => {
            tracing::warn!("Failed to create placeholder file for {fqdn}: {e}");
            return false;
        }
    };
    let writer = BufWriter::new(file);

    let mut encoder = png::Encoder::new(writer, 800, 600);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    let mut png_writer = match encoder.write_header() {
        Ok(w) => w,
        Err(e) => {
            tracing::warn!("Failed to write placeholder header for {fqdn}: {e}");
            return false;
        }
    };

    // Slate-800 background (30, 41, 59), same as the old PIL placeholder.
    let mut data = Vec::with_capacity(800 * 600 * 3);
    for _ in 0..(800 * 600) {
        data.extend_from_slice(&[30, 41, 59]);
    }

    match png_writer.write_image_data(&data) {
        Ok(()) => {
            tracing::info!("Placeholder preview written for {fqdn}");
            true
        }
        Err(e) => {
            tracing::warn!("Failed to write placeholder for {fqdn}: {e}");
            false
        }
    }
}

/// Refresh a preview: screenshot a running app, fall back to a placeholder.
pub fn preview_exists(settings: &Settings, fqdn: &str) -> bool {
    let path: &Path = &settings.preview_path(fqdn);
    path.is_file()
}

/// Screenshot if possible, otherwise write a placeholder. Returns screenshot success.
pub async fn refresh(settings: &Settings, fqdn: &str, container_running: bool) -> bool {
    if container_running {
        if generate_screenshot(settings, fqdn).await {
            return true;
        }
    } else {
        tracing::warn!("Container not running for {fqdn}, writing placeholder");
    }
    write_placeholder(settings, fqdn)
}
