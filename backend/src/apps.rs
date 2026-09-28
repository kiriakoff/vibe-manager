use std::path::Path;

use serde::Serialize;

use crate::docker;
use crate::preview;
use crate::AppState;

/// Validate an FQDN with at least three labels (`sub.domain.tld`),
/// mirroring the original spec: alphanumeric/hyphen labels, letters-only TLD.
pub fn is_valid_fqdn(name: &str) -> bool {
    let parts: Vec<&str> = name.split('.').collect();
    if parts.len() < 3 {
        return false;
    }
    for label in &parts {
        if label.is_empty() || label.len() > 63 {
            return false;
        }
        if label.starts_with('-') || label.ends_with('-') {
            return false;
        }
        if !label.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
            return false;
        }
    }
    // TLD: letters only, at least 2 chars.
    let tld = parts[parts.len() - 1];
    tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic())
}

#[derive(Debug, Clone, Serialize)]
pub struct AppInfo {
    pub fqdn: String,
    pub status: String,
    pub owner: String,
    pub has_preview: bool,
}

/// Scan filebrowser dirs (valid FQDN with index.html) plus orphaned
/// vibe-labeled running containers, the same way the original backend did.
pub async fn scan_apps(state: &AppState, username: &str) -> Vec<AppInfo> {
    let mut apps = Vec::new();
    let mut seen = std::collections::HashSet::new();

    tracing::debug!("Scanning filebrowser for user '{username}': {}", state.filebrowser_root.display());

    if let Ok(entries) = tokio::fs::read_dir(&state.filebrowser_root).await {
        let mut reader = entries;
        while let Ok(Some(entry)) = reader.next_entry().await {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let fqdn = entry.file_name().to_string_lossy().to_string();

            if !is_valid_fqdn(&fqdn) {
                tracing::debug!("Skipping '{fqdn}': not a valid FQDN");
                continue;
            }
            if !path.join("index.html").exists() {
                tracing::debug!("Skipping '{fqdn}': no index.html");
                continue;
            }

            let status = docker::container_status(&fqdn).await;
            let mut has_preview = preview::preview_exists(state, &fqdn);

            if status == "running" && !has_preview {
                tracing::info!("Auto-generating preview for {fqdn}");
                let state_clone = state.clone();
                let fqdn_clone = fqdn.clone();
                tokio::spawn(async move {
                    preview::generate_screenshot(&state_clone, &fqdn_clone).await;
                });
                has_preview = false;
            }

            tracing::info!("Found app: fqdn={fqdn}, status={status}, has_preview={has_preview}");
            seen.insert(fqdn.clone());
            apps.push(AppInfo {
                fqdn,
                status,
                owner: username.to_string(),
                has_preview,
            });
        }
    } else {
        tracing::warn!("Filebrowser root does not exist: {}", state.filebrowser_root.display());
    }

    // Also include orphaned running vibe containers (admin sees all of them).
    for container in docker::vibe_containers().await {
        let visible = username == "admin" || container.owner == username;
        if !visible || seen.contains(&container.fqdn) {
            continue;
        }
        tracing::info!("Found orphaned running container: fqdn={}, owner={}", container.fqdn, container.owner);
        seen.insert(container.fqdn.clone());
        let has_preview = preview::preview_exists(state, &container.fqdn);
        apps.push(AppInfo {
            fqdn: container.fqdn,
            status: "running".to_string(),
            owner: container.owner,
            has_preview,
        });
    }

    tracing::info!("Scan complete for user '{username}': found {} app(s)", apps.len());
    apps
}

/// Directory of an app inside the filebrowser root.
pub fn app_dir(state: &AppState, fqdn: &str) -> std::path::PathBuf {
    state.filebrowser_root.join(fqdn)
}

pub fn app_dir_exists(state: &AppState, fqdn: &str) -> bool {
    let path = app_dir(state, fqdn);
    path.is_dir() || path.exists()
}

pub fn path_exists(path: &Path) -> bool {
    path.exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_fqdns() {
        assert!(is_valid_fqdn("blog.mysite.com"));
        assert!(is_valid_fqdn("sub.blog.example.ru"));
        assert!(is_valid_fqdn("test.kiria-f.ru"));
        assert!(is_valid_fqdn("my-app.example.com"));
    }

    #[test]
    fn invalid_fqdns() {
        assert!(!is_valid_fqdn("area-selector"));
        assert!(!is_valid_fqdn("localhost"));
        assert!(!is_valid_fqdn("test"));
        assert!(!is_valid_fqdn("example..com"));
        assert!(!is_valid_fqdn("-blog.mysite.com"));
        assert!(!is_valid_fqdn("blog..mysite.com"));
        assert!(!is_valid_fqdn("blog.mysite.c0m"));
        assert!(!is_valid_fqdn(""));
        assert!(!is_valid_fqdn("blog.mysite.c"));
    }
}
