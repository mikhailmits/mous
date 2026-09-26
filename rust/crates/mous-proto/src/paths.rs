//! Filesystem locations shared by the client and daemon.
//!
//! `config_dir` mirrors the Python `mous.config.utils.config_dir` so both
//! implementations agree on where state lives. Runtime state (socket, lock)
//! prefers `$XDG_RUNTIME_DIR` on Linux and falls back to the config dir.

use std::path::PathBuf;

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

/// The SQLite database file.
pub fn db_path() -> PathBuf {
    if let Some(p) = std::env::var_os("MOUS_DB") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    config_dir().join("data.db")
}
