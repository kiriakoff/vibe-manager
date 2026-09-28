use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use rand::distr::{Alphanumeric, SampleString};

#[derive(Clone, Debug)]
pub struct Settings {
    pub jwt_secret: String,
    pub jwt_expiration_hours: i64,
    /// Filebrowser root inside the vibe-manager container (read-only mount).
    pub filebrowser_root: PathBuf,
    /// Filebrowser path on the host, used in generated compose volume mounts.
    pub filebrowser_host: PathBuf,
    /// Persistent data root (auth, previews, compose files).
    pub data_root: PathBuf,
    /// Directory with the built Flutter web app served as SPA.
    pub static_dir: PathBuf,
    pub port: u16,
}

impl Settings {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        jwt_secret: String,
        jwt_expiration_hours: i64,
        filebrowser_root: PathBuf,
        filebrowser_host: PathBuf,
        data_root: PathBuf,
        static_dir: PathBuf,
        port: u16,
    ) -> Self {
        Self {
            jwt_secret,
            jwt_expiration_hours,
            filebrowser_root,
            filebrowser_host,
            data_root,
            static_dir,
            port,
        }
    }

    pub fn from_env() -> Self {
        let data_root = PathBuf::from(env::var("DATA_ROOT").unwrap_or_else(|_| "/data".into()));
        let jwt_secret = match env::var("JWT_SECRET") {
            Ok(s) if !s.trim().is_empty() => s,
            _ => load_or_generate_jwt_secret(&jwt_secret_path(&data_root)),
        };
        let jwt_expiration_hours = env::var("JWT_EXPIRATION_HOURS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(24);
        let filebrowser_root =
            PathBuf::from(env::var("FILEBROWSER_ROOT").unwrap_or_else(|_| "/filebrowser".into()));
        let filebrowser_host = PathBuf::from(
            env::var("FILEBROWSER_HOST").unwrap_or_else(|_| "/data/filebrowser/files".into()),
        );
        let static_dir =
            PathBuf::from(env::var("STATIC_DIR").unwrap_or_else(|_| "/app/static".into()));
        let port = env::var("PORT")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(8000);

        Self::new(
            jwt_secret,
            jwt_expiration_hours,
            filebrowser_root,
            filebrowser_host,
            data_root,
            static_dir,
            port,
        )
    }

    pub fn auth_dir(&self) -> PathBuf {
        self.data_root.join("auth")
    }

    pub fn users_file(&self) -> PathBuf {
        self.auth_dir().join("users.txt")
    }

    pub fn previews_dir(&self) -> PathBuf {
        self.data_root.join("previews")
    }

    pub fn preview_path(&self, fqdn: &str) -> PathBuf {
        self.previews_dir().join(format!("{fqdn}.png"))
    }

    pub fn compose_dir(&self, owner: &str, fqdn: &str) -> PathBuf {
        self.data_root.join("compose").join(owner).join(fqdn)
    }
}

pub fn jwt_secret_path(data_root: &Path) -> PathBuf {
    data_root.join("auth").join("jwt_secret")
}

/// Load the JWT secret from file or generate a new one and persist it.
pub fn load_or_generate_jwt_secret(secret_file: &Path) -> String {
    if let Ok(existing) = fs::read_to_string(secret_file) {
        let trimmed = existing.trim().to_string();
        if !trimmed.is_empty() {
            return trimmed;
        }
    }

    let secret = Alphanumeric.sample_string(&mut rand::rng(), 48);
    if let Some(parent) = secret_file.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Err(e) = fs::write(secret_file, &secret) {
        tracing::warn!("Failed to persist JWT secret to {}: {e}", secret_file.display());
    }
    secret
}
