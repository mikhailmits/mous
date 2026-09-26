//! Domain model and SQLite-backed business logic for mous.
//!
//! This is the single source of truth the daemon serves. It has no knowledge
//! of the transport; it takes `mous-proto` request payloads and returns
//! `mous-proto` view types.

pub mod fx;
mod store;

pub use store::Store;

use std::fmt;

/// Errors surfaced to the daemon, which maps them to `Response::Error`.
#[derive(Debug)]
pub enum Error {
    Db(rusqlite::Error),
    NotFound(String),
    Invalid(String),
    InUse(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Db(e) => write!(f, "database error: {e}"),
            Error::NotFound(m) => write!(f, "{m}"),
            Error::Invalid(m) => write!(f, "{m}"),
            Error::InUse(m) => write!(f, "{m}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<rusqlite::Error> for Error {
    fn from(e: rusqlite::Error) -> Self {
        Error::Db(e)
    }
}

pub type Result<T> = std::result::Result<T, Error>;
