//! Shared wire types and framing for the mous CLI (`mou`) and daemon (`mousd`).
//!
//! The transport is a Unix domain socket. Each message is a little-endian
//! `u32` length prefix followed by a `postcard`-encoded body. Both sides are
//! Rust, so we skip HTTP/JSON entirely and share these types directly.

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

pub mod paths;

/// Bumped when the wire format changes incompatibly.
pub const PROTOCOL_VERSION: u32 = 1;

/// Guard against absurd allocations from a corrupt/hostile length prefix.
pub const MAX_FRAME_BYTES: usize = 64 * 1024 * 1024;

/// A request from the client to the daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Request {
    Ping,
    Shutdown,
    // Transactions
    TxList(TxFilter),
    TxGet(i64),
    TxNew(NewTx),
    TxEdit(EditTx),
    TxDelete(i64),
    // Currencies
    CurList,
    CurGet(i64),
    CurEditSymbol { id: i64, symbol: String },
    CurSetDefault { symbol: String },
    CurDelete(i64),
}

/// Filters for listing transactions. All fields are optional/empty by default.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TxFilter {
    /// Inclusive lower bound on `occurred_on` (YYYY-MM-DD).
    pub since: Option<String>,
    /// Inclusive upper bound on `occurred_on` (YYYY-MM-DD).
    pub until: Option<String>,
    /// Restrict to these native currency symbols (empty = all).
    pub currencies: Vec<String>,
}

/// Create a transaction. `amount` is signed: >0 income, <0 expense.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewTx {
    pub amount: f64,
    pub name: Option<String>,
    /// Native currency symbol; auto-created if unknown. Defaults to the default currency.
    pub currency: Option<String>,
    /// Category name; created if missing.
    pub category: Option<String>,
    /// Recurrence schedule (ISO datetime or cron), stored verbatim.
    pub recurring: Option<String>,
}

/// Edit an existing transaction. Only `Some` fields are changed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EditTx {
    pub id: i64,
    pub amount: Option<f64>,
    pub name: Option<String>,
    pub currency: Option<String>,
    pub category: Option<String>,
    pub recurring: Option<String>,
}

/// A transaction as shown to the user. Native `value`/`currency` are what is
/// stored; `amount`/`display_currency` are converted to the default currency.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TxView {
    pub id: i64,
    pub name: String,
    pub value: f64,
    pub currency: String,
    pub amount: f64,
    pub display_currency: String,
    /// False when the native currency has no FX quote and `amount` fell back to native.
    pub convertible: bool,
    pub category: Option<String>,
    pub occurred_on: String,
    pub recurring: Vec<String>,
}

/// A currency row.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CurView {
    pub id: i64,
    pub symbol: String,
    pub name: String,
    pub is_default: bool,
}

/// A response from the daemon to the client.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Response {
    Ok,
    Pong,
    Tx(TxView),
    Txs(Vec<TxView>),
    Cur(CurView),
    Curs(Vec<CurView>),
    Error(String),
}

fn encode_err(e: postcard::Error) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, e)
}

/// Write a length-prefixed, postcard-encoded message.
pub fn write_msg<W: Write, T: Serialize>(w: &mut W, msg: &T) -> io::Result<()> {
    let bytes = postcard::to_allocvec(msg).map_err(encode_err)?;
    let len = bytes.len() as u32;
    w.write_all(&len.to_le_bytes())?;
    w.write_all(&bytes)?;
    w.flush()
}

/// Read a length-prefixed, postcard-encoded message.
pub fn read_msg<R: Read, T: DeserializeOwned>(r: &mut R) -> io::Result<T> {
    let mut len_buf = [0u8; 4];
    r.read_exact(&mut len_buf)?;
    let len = u32::from_le_bytes(len_buf) as usize;
    if len > MAX_FRAME_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "frame exceeds MAX_FRAME_BYTES",
        ));
    }
    let mut buf = vec![0u8; len];
    r.read_exact(&mut buf)?;
    postcard::from_bytes(&buf).map_err(encode_err)
}
