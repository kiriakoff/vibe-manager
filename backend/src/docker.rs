use std::process::Stdio;
use std::time::Duration;

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::time::timeout;

use crate::config::Settings;

const COMMAND_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, Clone)]
pub struct VibeContainer {
    pub fqdn: String,
    pub owner: String,
}

fn docker() -> Command {
    let mut cmd = Command::new("docker");
    cmd.stdin(Stdio::null());
    cmd
}

/// Current container state via `docker inspect`, "not found" when absent.
pub async fn container_status(fqdn: &str) -> String {
    let output = docker()
        .args(["inspect", "--format", "{{.State.Status}}", fqdn])
        .output()
        .await;

    match output {
        Ok(out) if out.status.success() => {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        }
        _ => "not found".to_string(),
    }
}

/// All running containers labeled `vibe.manager=true` with their vibe labels.
pub async fn vibe_containers() -> Vec<VibeContainer> {
    let format = r#"{{.Label "vibe.fqdn"}}|{{.Label "vibe.owner"}}"#;
    let output = docker()
        .args(["ps", "--filter", "label=vibe.manager=true", "--format", format])
        .output()
        .await;

    let mut result = Vec::new();
    if let Ok(out) = output {
        if out.status.success() {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                let (fqdn, owner) = match line.split_once('|') {
                    Some((f, o)) => (f.trim(), o.trim()),
                    None => (line, "unknown"),
                };
                result.push(VibeContainer {
                    fqdn: if fqdn.is_empty() { "unknown".into() } else { fqdn.to_string() },
                    owner: if owner.is_empty() { "unknown".into() } else { owner.to_string() },
                });
            }
        }
    }
    result
}

/// The label-safe router/service name (dots are not allowed in Traefik names here).
fn safe_name(fqdn: &str) -> String {
    fqdn.replace('.', "_")
}

/// Generate the temporary docker-compose.yml for an app.
pub fn generate_compose_file(settings: &Settings, fqdn: &str, owner: &str) -> std::io::Result<std::path::PathBuf> {
    let dir = settings.compose_dir(owner, fqdn);
    std::fs::create_dir_all(&dir)?;
    let compose_path = dir.join("docker-compose.yml");
    let safe = safe_name(fqdn);
    let content = format!(
        r#"services:
  app:
    image: nginx:alpine
    container_name: "{fqdn}"
    volumes:
      - "{host}/{fqdn}:/usr/share/nginx/html:ro"
    networks:
      - proxy
    labels:
      vibe.manager: "true"
      vibe.owner: "{owner}"
      vibe.fqdn: "{fqdn}"
      traefik.enable: "true"
      traefik.http.routers.{safe}.rule: 'Host(`{fqdn}`)'
      traefik.http.routers.{safe}.entrypoints: "websecure"
      traefik.http.routers.{safe}.tls: "true"
      traefik.http.routers.{safe}.tls.certresolver: "letsEncrypt"
      traefik.http.services.{safe}.loadbalancer.server.port: "80"

networks:
  proxy:
    external: true
"#,
        fqdn = fqdn,
        host = settings.filebrowser_host.display(),
        owner = owner,
        safe = safe,
    );
    std::fs::write(&compose_path, content)?;
    Ok(compose_path)
}

/// Start an app: generate compose file, then `docker compose up -d`.
pub async fn start_app(settings: &Settings, fqdn: &str, owner: &str) -> Result<(), String> {
    let compose_path = generate_compose_file(settings, fqdn, owner).map_err(|e| e.to_string())?;
    tracing::info!("Starting app {fqdn}, compose_path={}", compose_path.display());

    let output = timeout(
        COMMAND_TIMEOUT,
        docker()
            .args(["compose", "-f"])
            .arg(&compose_path)
            .args(["up", "-d"])
            .output(),
    )
    .await
    .map_err(|_| format!("timeout starting app {fqdn}"))?
    .map_err(|e| e.to_string())?;

    tracing::debug!("docker compose up stdout: {}", String::from_utf8_lossy(&output.stdout).trim());
    tracing::debug!("docker compose up stderr: {}", String::from_utf8_lossy(&output.stderr).trim());

    if output.status.success() {
        Ok(())
    } else {
        Err(format!(
            "docker compose up failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}

/// Stop an app: `docker compose down` if the compose file exists,
/// otherwise remove the container directly (`docker rm -f`).
pub async fn stop_app(settings: &Settings, fqdn: &str, owner: &str) -> Result<(), String> {
    let compose_path = settings.compose_dir(owner, fqdn).join("docker-compose.yml");

    if !compose_path.exists() {
        tracing::warn!("Compose file not found for {fqdn}, removing container directly");
        let output = timeout(COMMAND_TIMEOUT, docker().args(["rm", "-f", fqdn]).output())
            .await
            .map_err(|_| format!("timeout removing container {fqdn}"))?
            .map_err(|e| e.to_string())?;

        if output.status.success() {
            tracing::info!("Container {fqdn} stopped and removed directly");
            return Ok(());
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.contains("No such container") {
            tracing::info!("Container {fqdn} not found, nothing to stop");
            return Ok(());
        }
        return Err(format!("failed to remove container {fqdn}: {}", stderr.trim()));
    }

    tracing::info!("Stopping app {fqdn}, compose_path={}", compose_path.display());

    let output = timeout(
        COMMAND_TIMEOUT,
        docker()
            .args(["compose", "-f"])
            .arg(&compose_path)
            .arg("down")
            .output(),
    )
    .await
    .map_err(|_| format!("timeout stopping app {fqdn}"))?
    .map_err(|e| e.to_string())?;

    tracing::debug!("docker compose down stdout: {}", String::from_utf8_lossy(&output.stdout).trim());
    tracing::debug!("docker compose down stderr: {}", String::from_utf8_lossy(&output.stderr).trim());

    if output.status.success() {
        Ok(())
    } else {
        Err(format!(
            "docker compose down failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}

/// Spawn `docker logs --tail 100 --follow` with merged stdout/stderr.
/// The child process is killed when the returned handle is dropped,
/// which happens automatically when the SSE client disconnects.
pub fn spawn_log_follow(fqdn: &str) -> Result<tokio::process::Child, String> {
    Command::new("sh")
        .arg("-c")
        .arg(format!("docker logs --tail 100 --follow {fqdn} 2>&1"))
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .stdin(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| format!("failed to spawn docker logs: {e}"))
}

/// Take a line reader over the merged log output of a spawned `docker logs --follow`.
pub fn take_log_lines(
    child: &mut tokio::process::Child,
) -> Option<tokio::io::Lines<BufReader<tokio::process::ChildStdout>>> {
    child.stdout.take().map(|stdout| BufReader::new(stdout).lines())
}

/// Best-effort cleanup of the temporary compose file for an app.
pub fn cleanup_compose_file(settings: &Settings, fqdn: &str, owner: &str) {
    let path = settings.compose_dir(owner, fqdn).join("docker-compose.yml");
    if path.exists() {
        let _ = std::fs::remove_file(&path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compose_file_matches_template() {
        let tmp = tempfile::tempdir().unwrap();
        let settings = Settings::new(
            "secret".into(),
            24,
            tmp.path().join("filebrowser"),
            "/data/filebrowser/files".into(),
            tmp.path().join("data"),
            tmp.path().join("static"),
            8000,
        );

        let path = generate_compose_file(&settings, "blog.mysite.com", "admin").unwrap();
        let content = std::fs::read_to_string(path).unwrap();

        assert!(content.contains(r#"container_name: "blog.mysite.com""#));
        assert!(content.contains("/data/filebrowser/files/blog.mysite.com:/usr/share/nginx/html:ro"));
        assert!(content.contains(r#"vibe.owner: "admin""#));
        assert!(content.contains(r#"traefik.http.routers.blog_mysite_com.rule: 'Host(`blog.mysite.com`)'"#));
        assert!(content.contains("letsEncrypt"));
        assert!(content.contains("external: true"));
    }

    #[test]
    fn safe_name_replaces_dots() {
        assert_eq!(safe_name("a.b.example.com"), "a_b_example_com");
    }
}
