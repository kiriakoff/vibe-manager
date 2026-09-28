//! CLI helper: create or update a user in `users.txt`.
//!
//! Usage: create-user <username> <password>

use std::collections::HashMap;

use vibe_manager::auth::{hash_password, load_users, save_users};
use vibe_manager::config::Settings;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: create-user <username> <password>");
        std::process::exit(1);
    }
    let username = &args[1];
    let password = &args[2];

    let settings = Settings::from_env();
    let path = settings.users_file();

    let mut users: HashMap<String, String> = load_users(&path);
    match hash_password(password) {
        Ok(hash) => {
            users.insert(username.clone(), hash);
        }
        Err(e) => {
            eprintln!("Failed to hash password: {e}");
            std::process::exit(1);
        }
    }

    if let Err(e) = save_users(&path, &users) {
        eprintln!("Failed to write {}: {e}", path.display());
        std::process::exit(1);
    }

    println!("User '{username}' created/updated in {}", path.display());
}
