//! Filesystem locations shared by the client and daemon.
//!
//! `config_dir` mirrors the Python `mous.config.utils.config_dir` so both
//! implementations agree on where state lives. Runtime state (socket, lock)
//! prefers `$XDG_RUNTIME_DIR` on Linux and falls back to the config dir.

use std::path::{Path, PathBuf};

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

/// Where config.json / data.db live.
pub fn config_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("MOUS_CONFIG_DIR") {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }
    if cfg!(target_os = "macos") {
        return home_dir()
            .join("Library")
            .join("Application Support")
            .join("mous");
    }
    if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg).join("mous");
        }
    }
    home_dir().join(".config").join("mous")
}

/// Where ephemeral runtime state (socket, lock) lives.
pub fn runtime_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("MOUS_RUNTIME_DIR") {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }
    if cfg!(target_os = "linux") {
        if let Some(xdg) = std::env::var_os("XDG_RUNTIME_DIR") {
            if !xdg.is_empty() {
                return PathBuf::from(xdg).join("mous");
            }
        }
    }
    config_dir()
}

/// The Unix domain socket the daemon listens on.
pub fn socket_path() -> PathBuf {
    if let Some(p) = std::env::var_os("MOUS_SOCKET") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    runtime_dir().join("mousd.sock")
}

/// Single-instance lock file.
pub fn lock_path() -> PathBuf {
    runtime_dir().join("mousd.lock")
}

/// Protocol generation written by the running daemon. `mou` restarts `mousd`
/// when this file is missing or does not match `PROTOCOL_VERSION`.
pub fn protocol_stamp_path() -> PathBuf {
    runtime_dir().join("mousd.protocol")
}

/// The SQLite database file.
///
/// `MOUS_DB` wins. Otherwise `database_path` from `config.json` is honored so
/// the daemon opens the same file the Python service and the macOS app use.
pub fn db_path() -> PathBuf {
    if let Some(p) = std::env::var_os("MOUS_DB") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    if let Some(p) = database_path_from_config(&config_dir()) {
        return p;
    }
    config_dir().join("data.db")
}

/// `database_path` inside `config.json`, when that file is readable JSON.
pub fn database_path_from_config(dir: &Path) -> Option<PathBuf> {
    let text = std::fs::read_to_string(dir.join("config.json")).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    let raw = value.get("database_path")?.as_str()?.trim();
    if raw.is_empty() {
        None
    } else {
        Some(PathBuf::from(raw))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn database_path_reads_config_json() {
        let dir = std::env::temp_dir().join(format!("mous-paths-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            "{\n  \"database_path\": \"/tmp/books.db\"\n}\n",
        )
        .unwrap();
        assert_eq!(
            database_path_from_config(&dir).unwrap(),
            PathBuf::from("/tmp/books.db")
        );
        std::fs::write(dir.join("config.json"), "{}\n").unwrap();
        assert!(database_path_from_config(&dir).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
