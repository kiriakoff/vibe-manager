use std::collections::HashMap;
use std::fs;
use std::path::Path;

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use crate::error::ApiError;
use crate::AppState;

/// Load users from a `username:bcrypt_hash` flat file. Missing file = no users.
pub fn load_users(path: &Path) -> HashMap<String, String> {
    let mut users = HashMap::new();
    let Ok(content) = fs::read_to_string(path) else {
        return users;
    };
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((username, hash)) = line.split_once(':') {
            users.insert(username.trim().to_string(), hash.trim().to_string());
        }
    }
    users
}

/// Persist users back to the `username:bcrypt_hash` flat file.
pub fn save_users(path: &Path, users: &HashMap<String, String>) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut usernames: Vec<&String> = users.keys().collect();
    usernames.sort();
    let mut content = String::new();
    for username in usernames {
        content.push_str(&format!("{username}:{}\n", users[username]));
    }
    fs::write(path, content)
}

pub fn hash_password(password: &str) -> Result<String, bcrypt::BcryptError> {
    bcrypt::hash(password, bcrypt::DEFAULT_COST)
}

pub fn verify_password(password: &str, hash: &str) -> bool {
    bcrypt::verify(password, hash).unwrap_or(false)
}

pub fn authenticate(username: &str, password: &str, users: &HashMap<String, String>) -> bool {
    match users.get(username) {
        Some(hash) => verify_password(password, hash),
        None => {
            // Burn comparable time to avoid trivial user enumeration.
            let _ = bcrypt::hash(password, 10);
            false
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub exp: u64,
}

pub fn create_token(
    username: &str,
    secret: &str,
    expiration_hours: i64,
) -> Result<String, jsonwebtoken::errors::Error> {
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
        + (expiration_hours.max(1) as u64) * 3600;
    encode(
        &Header::new(Algorithm::HS256),
        &Claims {
            sub: username.to_string(),
            exp,
        },
        &EncodingKey::from_secret(secret.as_bytes()),
    )
}

pub fn decode_token(token: &str, secret: &str) -> Option<Claims> {
    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::new(Algorithm::HS256),
    )
    .ok()?;
    Some(data.claims)
}

/// Extractor that authenticates the request via `Authorization: Bearer <jwt>`.
pub struct CurrentUser(pub String);

impl FromRequestParts<AppState> for CurrentUser {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let unauthorized = || ApiError::unauthorized("Not authenticated");

        let header = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(unauthorized)?;

        let token = header
            .strip_prefix("Bearer ")
            .or_else(|| header.strip_prefix("bearer "))
            .map(str::trim)
            .filter(|t| !t.is_empty())
            .ok_or_else(unauthorized)?;

        let claims =
            decode_token(token, &state.jwt_secret).ok_or_else(|| ApiError::unauthorized("Invalid or expired token"))?;

        Ok(Self(claims.sub))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn users_file_roundtrip() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("users.txt");

        let mut users = HashMap::new();
        users.insert("admin".to_string(), "$2a$10$xyz".to_string());
        users.insert("bob".to_string(), "$2a$10$abc".to_string());
        save_users(&path, &users).unwrap();

        let loaded = load_users(&path);
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded["admin"], "$2a$10$xyz");
        assert_eq!(loaded["bob"], "$2a$10$abc");
    }

    #[test]
    fn users_file_missing_is_empty() {
        let tmp = tempfile::tempdir().unwrap();
        let users = load_users(&tmp.path().join("nope.txt"));
        assert!(users.is_empty());
    }

    #[test]
    fn password_hash_and_verify() {
        let hash = hash_password("s3cret").unwrap();
        assert!(verify_password("s3cret", &hash));
        assert!(!verify_password("wrong", &hash));
    }

    #[test]
    fn jwt_roundtrip_and_expiry_claim() {
        let token = create_token("admin", "top-secret", 24).unwrap();
        let claims = decode_token(&token, "top-secret").unwrap();
        assert_eq!(claims.sub, "admin");
        assert!(claims.exp > std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs());
        assert!(decode_token(&token, "wrong-secret").is_none());
    }

    #[test]
    fn authenticate_rejects_unknown_user() {
        let mut users = HashMap::new();
        users.insert("admin".to_string(), hash_password("pw").unwrap());
        assert!(authenticate("admin", "pw", &users));
        assert!(!authenticate("admin", "nope", &users));
        assert!(!authenticate("ghost", "pw", &users));
    }
}
