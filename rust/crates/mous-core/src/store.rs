//! SQLite-backed persistence and domain rules.
//!
//! Schema semantics match the original Python model: `good.value` is signed
//! (>0 income, <0 expense); a good's currency is `RESTRICT` on delete, its
//! category is `SET NULL`; categories with zero transactions are pruned;
//! currencies are auto-created when referenced.

use std::path::Path;

use rusqlite::{params, params_from_iter, Connection, OptionalExtension};
use time::macros::format_description;
use time::{Date, OffsetDateTime};
#[cfg(test)]
use time::UtcOffset;

use crate::fx;
use crate::{Error, Result};
use mous_proto::{CurView, EditTx, NewTx, TxFilter, TxView};

const DATE_FMT: &[time::format_description::FormatItem<'static>] =
    format_description!("[year]-[month]-[day]");

/// Unit-separator used to pack recurring schedules in a single grouped column.
const REC_SEP: char = '\u{1f}';

pub struct Store {
    conn: Connection,
}

impl Store {
    /// Open (creating if needed) the database at `path`, apply schema, seed defaults.
    pub fn open(path: &Path) -> Result<Store> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let conn = Connection::open(path)?;
        Self::from_conn(conn)
    }

    /// In-memory store for tests.
    pub fn open_in_memory() -> Result<Store> {
        let conn = Connection::open_in_memory()?;
        Self::from_conn(conn)
    }

    fn from_conn(conn: Connection) -> Result<Store> {
        conn.pragma_update(None, "journal_mode", "WAL").ok();
        conn.pragma_update(None, "synchronous", "NORMAL").ok();
        conn.pragma_update(None, "foreign_keys", "ON")?;
        let store = Store { conn };
        store.adopt_legacy_tables()?;
        store.init_schema()?;
        store.ensure_defaults()?;
        Ok(store)
    }

    /// The first Rust cut created `category` / `recurring_good`. Python and the
    /// macOS books use `goodcategory` / `recurringgood`. Rename before creating
    /// the real tables so an empty shadow table cannot hide the rows.
    fn adopt_legacy_tables(&self) -> Result<()> {
        self.rename_table_if_destination_missing("category", "goodcategory")?;
        self.rename_table_if_destination_missing("recurring_good", "recurringgood")?;
        Ok(())
    }

    fn rename_table_if_destination_missing(&self, from: &str, to: &str) -> Result<()> {
        if self.table_exists(from)? && !self.table_exists(to)? {
            // Names are fixed literals chosen by the caller, not user input.
            self.conn
                .execute(&format!("ALTER TABLE {from} RENAME TO {to}"), [])?;
        }
        Ok(())
    }

    fn table_exists(&self, name: &str) -> Result<bool> {
        let found: Option<String> = self
            .conn
            .query_row(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?1",
                params![name],
                |r| r.get(0),
            )
            .optional()?;
        Ok(found.is_some())
    }

    fn init_schema(&self) -> Result<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS currency (
                id         INTEGER PRIMARY KEY,
                symbol     TEXT NOT NULL UNIQUE,
                name       TEXT NOT NULL UNIQUE,
                is_default INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS account (
                id   INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE DEFAULT 'main'
            );
            CREATE TABLE IF NOT EXISTS goodcategory (
                id   INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS good (
                id          INTEGER PRIMARY KEY,
                name        TEXT NOT NULL,
                value       REAL NOT NULL,
                occurred_on TEXT NOT NULL,
                currency_id INTEGER NOT NULL REFERENCES currency(id) ON DELETE RESTRICT,
                account_id  INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                category_id INTEGER REFERENCES goodcategory(id) ON DELETE SET NULL
            );
            CREATE INDEX IF NOT EXISTS idx_good_occurred_on ON good(occurred_on);
            CREATE INDEX IF NOT EXISTS idx_good_currency ON good(currency_id);
            CREATE INDEX IF NOT EXISTS idx_good_category ON good(category_id);
            CREATE TABLE IF NOT EXISTS recurringgood (
                id         INTEGER PRIMARY KEY,
                good_id    INTEGER NOT NULL REFERENCES good(id) ON DELETE CASCADE,
                cron_stamp TEXT NOT NULL
            );
            "#,
        )?;
        Ok(())
    }

    fn ensure_defaults(&self) -> Result<()> {
        let accounts: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM account", [], |r| r.get(0))?;
        if accounts == 0 {
            self.conn
                .execute("INSERT INTO account (name) VALUES ('main')", [])?;
        }
        let currencies: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM currency", [], |r| r.get(0))?;
        if currencies == 0 {
            self.conn.execute(
                "INSERT INTO currency (symbol, name, is_default) VALUES ('eur', 'Euro', 1)",
                [],
            )?;
        }
        Ok(())
    }

    // ---- helpers -----------------------------------------------------------

    fn default_account_id(&self) -> Result<i64> {
        let id: Option<i64> = self
            .conn
            .query_row(
                "SELECT id FROM account ORDER BY (name='main') DESC, id ASC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .optional()?;
        id.ok_or_else(|| Error::Invalid("no account configured".into()))
    }

    fn default_currency_symbol(&self) -> Result<String> {
        let sym: Option<String> = self
            .conn
            .query_row(
                "SELECT symbol FROM currency ORDER BY is_default DESC, id ASC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .optional()?;
        Ok(sym.unwrap_or_else(|| "eur".to_string()))
    }

    fn resolve_or_create_currency(&self, symbol: &str) -> Result<i64> {
        let sym = symbol.trim().to_lowercase();
        if sym.is_empty() {
            return Err(Error::Invalid("currency symbol cannot be empty".into()));
        }
        if let Some(id) = self
            .conn
            .query_row(
                "SELECT id FROM currency WHERE symbol = ?1",
                params![sym],
                |r| r.get::<_, i64>(0),
            )
            .optional()?
        {
            return Ok(id);
        }
        self.conn.execute(
            "INSERT INTO currency (symbol, name, is_default) VALUES (?1, ?2, 0)",
            params![sym, sym],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    fn resolve_or_create_category(&self, name: &str) -> Result<i64> {
        let name = name.trim();
        if name.is_empty() {
            return Err(Error::Invalid("category name cannot be empty".into()));
        }
        if let Some(id) = self
            .conn
            .query_row(
                "SELECT id FROM goodcategory WHERE name = ?1",
                params![name],
                |r| r.get::<_, i64>(0),
            )
            .optional()?
        {
            return Ok(id);
        }
        self.conn
            .execute("INSERT INTO goodcategory (name) VALUES (?1)", params![name])?;
        Ok(self.conn.last_insert_rowid())
    }

    fn prune_category_if_empty(&self, category_id: Option<i64>) -> Result<()> {
        if let Some(cid) = category_id {
            let count: i64 = self.conn.query_row(
                "SELECT COUNT(*) FROM good WHERE category_id = ?1",
                params![cid],
                |r| r.get(0),
            )?;
            if count == 0 {
                self.conn
                    .execute("DELETE FROM goodcategory WHERE id = ?1", params![cid])?;
            }
        }
        Ok(())
    }

    fn good_category_id(&self, good_id: i64) -> Result<Option<i64>> {
        self.conn
            .query_row(
                "SELECT category_id FROM good WHERE id = ?1",
                params![good_id],
                |r| r.get::<_, Option<i64>>(0),
            )
            .optional()
            .map(|opt| opt.flatten())
            .map_err(Error::from)
    }

    fn replace_recurring(&self, good_id: i64, schedule: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM recurringgood WHERE good_id = ?1",
            params![good_id],
        )?;
        let trimmed = schedule.trim();
        if !trimmed.is_empty() {
            self.conn.execute(
                "INSERT INTO recurringgood (good_id, cron_stamp) VALUES (?1, ?2)",
                params![good_id, trimmed],
            )?;
        }
        Ok(())
    }

    // ---- currencies --------------------------------------------------------

    pub fn cur_list(&self) -> Result<Vec<CurView>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, symbol, name, is_default FROM currency ORDER BY id ASC")?;
        let rows = stmt.query_map([], |r| {
            Ok(CurView {
                id: r.get(0)?,
                symbol: r.get(1)?,
                name: r.get(2)?,
                is_default: r.get::<_, i64>(3)? != 0,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn cur_get(&self, id: i64) -> Result<CurView> {
        self.conn
            .query_row(
                "SELECT id, symbol, name, is_default FROM currency WHERE id = ?1",
                params![id],
                |r| {
                    Ok(CurView {
                        id: r.get(0)?,
                        symbol: r.get(1)?,
                        name: r.get(2)?,
                        is_default: r.get::<_, i64>(3)? != 0,
                    })
                },
            )
            .optional()?
            .ok_or_else(|| Error::NotFound(format!("currency {id} not found")))
    }

    pub fn cur_edit_symbol(&self, id: i64, symbol: &str) -> Result<CurView> {
        let sym = symbol.trim().to_lowercase();
        if sym.is_empty() {
            return Err(Error::Invalid("currency symbol cannot be empty".into()));
        }
        let changed = self.conn.execute(
            "UPDATE currency SET symbol = ?1 WHERE id = ?2",
            params![sym, id],
        )?;
        if changed == 0 {
            return Err(Error::NotFound(format!("currency {id} not found")));
        }
        self.cur_get(id)
    }

    pub fn cur_set_default(&self, symbol: &str) -> Result<CurView> {
        let id = self.resolve_or_create_currency(symbol)?;
        self.conn
            .execute("UPDATE currency SET is_default = 0", [])?;
        self.conn.execute(
            "UPDATE currency SET is_default = 1 WHERE id = ?1",
            params![id],
        )?;
        self.cur_get(id)
    }

    pub fn cur_delete(&self, id: i64) -> Result<()> {
        let existing = self.cur_get(id)?;
        if existing.is_default {
            return Err(Error::Invalid(
                "cannot delete the default currency".into(),
            ));
        }
        let in_use: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM good WHERE currency_id = ?1",
            params![id],
            |r| r.get(0),
        )?;
        if in_use > 0 {
            return Err(Error::InUse(format!(
                "currency {} is used by {in_use} transaction(s)",
                existing.symbol
            )));
        }
        self.conn
            .execute("DELETE FROM currency WHERE id = ?1", params![id])?;
        Ok(())
    }

    // ---- transactions ------------------------------------------------------

    pub fn tx_new(&self, tx: &NewTx) -> Result<TxView> {
        if !tx.amount.is_finite() {
            return Err(Error::Invalid("amount must be a finite number".into()));
        }
        if tx.amount == 0.0 {
            return Err(Error::Invalid(
                "zero is not a transaction (use a signed amount)".into(),
            ));
        }
        let account_id = self.default_account_id()?;
        let currency_id = match &tx.currency {
            Some(sym) => self.resolve_or_create_currency(sym)?,
            None => self.resolve_or_create_currency(&self.default_currency_symbol()?)?,
        };
        let category_id = match &tx.category {
            Some(name) => Some(self.resolve_or_create_category(name)?),
            None => None,
        };
        let name = tx
            .name
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .or_else(|| tx.category.clone())
            .unwrap_or_else(|| "unnamed".to_string());
        let occurred_on = match &tx.occurred_on {
            Some(raw) => normalize_date_filter(&Some(raw.clone()))?
                .ok_or_else(|| Error::Invalid("date must be YYYY-MM-DD".into()))?,
            None => fmt_date(civil_today()),
        };
        self.conn.execute(
            "INSERT INTO good (name, value, occurred_on, currency_id, account_id, category_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                name,
                tx.amount,
                occurred_on,
                currency_id,
                account_id,
                category_id
            ],
        )?;
        let good_id = self.conn.last_insert_rowid();
        if let Some(schedule) = &tx.recurring {
            self.replace_recurring(good_id, schedule)?;
        }
        self.tx_view(good_id)
    }

    pub fn tx_get(&self, id: i64) -> Result<TxView> {
        self.tx_view(id)
    }

    pub fn tx_delete(&self, id: i64) -> Result<()> {
        let old_category = self.good_category_id(id)?;
        let changed = self
            .conn
            .execute("DELETE FROM good WHERE id = ?1", params![id])?;
        if changed == 0 {
            return Err(Error::NotFound(format!("transaction {id} not found")));
        }
        self.prune_category_if_empty(old_category)?;
        Ok(())
    }

    pub fn tx_edit(&self, edit: &EditTx) -> Result<TxView> {
        // Ensure it exists first.
        let old_category = self.good_category_id(edit.id)?;
        let exists: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM good WHERE id = ?1",
            params![edit.id],
            |r| r.get(0),
        )?;
        if exists == 0 {
            return Err(Error::NotFound(format!(
                "transaction {} not found",
                edit.id
            )));
        }
        if let Some(amount) = edit.amount {
            if !amount.is_finite() || amount == 0.0 {
                return Err(Error::Invalid(
                    "amount must be a finite non-zero number".into(),
                ));
            }
            self.conn.execute(
                "UPDATE good SET value = ?1 WHERE id = ?2",
                params![amount, edit.id],
            )?;
        }
        if let Some(name) = &edit.name {
            let name = name.trim();
            if name.is_empty() {
                return Err(Error::Invalid("name cannot be empty".into()));
            }
            self.conn.execute(
                "UPDATE good SET name = ?1 WHERE id = ?2",
                params![name, edit.id],
            )?;
        }
        if let Some(sym) = &edit.currency {
            let currency_id = self.resolve_or_create_currency(sym)?;
            self.conn.execute(
                "UPDATE good SET currency_id = ?1 WHERE id = ?2",
                params![currency_id, edit.id],
            )?;
        }
        let mut category_changed = false;
        if let Some(cat) = &edit.category {
            let new_id = self.resolve_or_create_category(cat)?;
            self.conn.execute(
                "UPDATE good SET category_id = ?1 WHERE id = ?2",
                params![new_id, edit.id],
            )?;
            category_changed = true;
        }
        if let Some(raw) = &edit.occurred_on {
            let occurred_on = normalize_date_filter(&Some(raw.clone()))?
                .ok_or_else(|| Error::Invalid("date must be YYYY-MM-DD".into()))?;
            self.conn.execute(
                "UPDATE good SET occurred_on = ?1 WHERE id = ?2",
                params![occurred_on, edit.id],
            )?;
        }
        if let Some(schedule) = &edit.recurring {
            self.replace_recurring(edit.id, schedule)?;
        }
        if category_changed {
            let new_category = self.good_category_id(edit.id)?;
            if old_category != new_category {
                self.prune_category_if_empty(old_category)?;
            }
        }
        self.tx_view(edit.id)
    }

    pub fn tx_list(&self, filter: &TxFilter) -> Result<Vec<TxView>> {
        let default = self.default_currency_symbol()?;
        let mut sql = String::from(
            "SELECT g.id, g.name, g.value, c.symbol, cat.name, g.occurred_on, \
             group_concat(r.cron_stamp, '\u{1f}'), g.currency_id, g.account_id, g.category_id \
             FROM good g \
             JOIN currency c ON c.id = g.currency_id \
             LEFT JOIN goodcategory cat ON cat.id = g.category_id \
             LEFT JOIN recurringgood r ON r.good_id = g.id \
             WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();
        if let Some(since) = normalize_date_filter(&filter.since)? {
            sql.push_str(" AND g.occurred_on >= ?");
            args.push(Box::new(since));
        }
        if let Some(until) = normalize_date_filter(&filter.until)? {
            sql.push_str(" AND g.occurred_on <= ?");
            args.push(Box::new(until));
        }
        if !filter.currencies.is_empty() {
            let placeholders = filter
                .currencies
                .iter()
                .map(|_| "?")
                .collect::<Vec<_>>()
                .join(", ");
            sql.push_str(&format!(" AND lower(c.symbol) IN ({placeholders})"));
            for sym in &filter.currencies {
                args.push(Box::new(sym.trim().to_lowercase()));
            }
        }
        if let Some(category) = filter
            .category
            .as_deref()
            .map(str::trim)
            .filter(|name| !name.is_empty())
        {
            sql.push_str(" AND cat.name = ?");
            args.push(Box::new(category.to_string()));
        }
        sql.push_str(" GROUP BY g.id ORDER BY g.occurred_on DESC, g.id DESC");

        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(args.iter().map(|b| b.as_ref())), |r| {
            Ok(RawGood {
                id: r.get(0)?,
                name: r.get(1)?,
                value: r.get(2)?,
                currency: r.get(3)?,
                category: r.get(4)?,
                occurred_on: r.get(5)?,
                recurring: r.get(6)?,
                currency_id: r.get(7)?,
                account_id: r.get(8)?,
                category_id: r.get(9)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?.into_view(&default));
        }
        Ok(out)
    }

    fn tx_view(&self, id: i64) -> Result<TxView> {
        let default = self.default_currency_symbol()?;
        let raw = self
            .conn
            .query_row(
                "SELECT g.id, g.name, g.value, c.symbol, cat.name, g.occurred_on, \
                 group_concat(r.cron_stamp, '\u{1f}'), g.currency_id, g.account_id, g.category_id \
                 FROM good g \
                 JOIN currency c ON c.id = g.currency_id \
                 LEFT JOIN goodcategory cat ON cat.id = g.category_id \
                 LEFT JOIN recurringgood r ON r.good_id = g.id \
                 WHERE g.id = ?1 GROUP BY g.id",
                params![id],
                |r| {
                    Ok(RawGood {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        value: r.get(2)?,
                        currency: r.get(3)?,
                        category: r.get(4)?,
                        occurred_on: r.get(5)?,
                        recurring: r.get(6)?,
                        currency_id: r.get(7)?,
                        account_id: r.get(8)?,
                        category_id: r.get(9)?,
                    })
                },
            )
            .optional()?
            .ok_or_else(|| Error::NotFound(format!("transaction {id} not found")))?;
        Ok(raw.into_view(&default))
    }
}

struct RawGood {
    id: i64,
    name: String,
    value: f64,
    currency: String,
    category: Option<String>,
    occurred_on: String,
    recurring: Option<String>,
    currency_id: i64,
    account_id: i64,
    category_id: Option<i64>,
}

impl RawGood {
    fn into_view(self, default_symbol: &str) -> TxView {
        let (amount, display_currency, convertible) =
            match fx::convert(self.value, &self.currency, default_symbol) {
                Some(converted) => (converted, default_symbol.to_string(), true),
                None => (self.value, self.currency.clone(), false),
            };
        let recurring = match self.recurring {
            Some(s) if !s.is_empty() => s.split(REC_SEP).map(str::to_string).collect(),
            _ => Vec::new(),
        };
        let occurred_unix_time = Date::parse(&self.occurred_on, &DATE_FMT)
            .ok()
            .map(civil_to_unix)
            .unwrap_or(0);
        TxView {
            id: self.id,
            name: self.name,
            value: self.value,
            currency: self.currency,
            amount,
            display_currency,
            convertible,
            category: self.category,
            occurred_on: self.occurred_on,
            recurring,
            currency_id: self.currency_id,
            account_id: self.account_id,
            category_id: self.category_id,
            occurred_unix_time,
            default_currency: default_symbol.to_string(),
        }
    }
}

/// Local civil day via `localtime_r` (same calendar day as Python `date.today()`).
/// The `time` crate's offset helper errors once the daemon has spawned threads.
fn civil_today() -> Date {
    local_civil_day().unwrap_or_else(|| OffsetDateTime::now_utc().date())
}

fn local_civil_day() -> Option<Date> {
    let now = unsafe { libc::time(std::ptr::null_mut()) };
    if now < 0 {
        return None;
    }
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    if unsafe { libc::localtime_r(&now, &mut tm) }.is_null() {
        return None;
    }
    let year = tm.tm_year + 1900;
    let month = u8::try_from(tm.tm_mon + 1).ok()?;
    let month = time::Month::try_from(month).ok()?;
    let day = u8::try_from(tm.tm_mday).ok()?;
    Date::from_calendar_date(year, month, day).ok()
}

#[cfg(test)]
fn civil_date(utc: OffsetDateTime, offset: Option<UtcOffset>) -> Date {
    match offset {
        Some(offset) => utc.to_offset(offset).date(),
        None => utc.date(),
    }
}

fn civil_to_unix(day: Date) -> i64 {
    day.with_hms(0, 0, 0)
        .expect("midnight")
        .assume_utc()
        .unix_timestamp()
}

fn fmt_date(d: Date) -> String {
    d.format(&DATE_FMT).unwrap_or_else(|_| "1970-01-01".into())
}

/// Validate a `YYYY-MM-DD` filter string, returning the canonical form.
fn normalize_date_filter(raw: &Option<String>) -> Result<Option<String>> {
    match raw {
        None => Ok(None),
        Some(s) if s.trim().is_empty() => Ok(None),
        Some(s) => {
            let parsed = Date::parse(s.trim(), &DATE_FMT)
                .map_err(|_| Error::Invalid(format!("invalid date {s:?}; use YYYY-MM-DD")))?;
            Ok(Some(fmt_date(parsed)))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> Store {
        Store::open_in_memory().unwrap()
    }

    #[test]
    fn seeds_defaults() {
        let s = store();
        let curs = s.cur_list().unwrap();
        assert_eq!(curs.len(), 1);
        assert_eq!(curs[0].symbol, "eur");
        assert!(curs[0].is_default);
    }

    #[test]
    fn new_transaction_uses_default_currency_and_converts() {
        let s = store();
        let tx = s
            .tx_new(&NewTx {
                amount: -23.10,
                name: Some("groceries".into()),
                currency: None,
                category: Some("food".into()),
                recurring: None,
                occurred_on: None,
            })
            .unwrap();
        assert_eq!(tx.currency, "eur");
        assert_eq!(tx.display_currency, "eur");
        assert!((tx.value - -23.10).abs() < 1e-9);
        assert!((tx.amount - -23.10).abs() < 1e-9); // eur -> eur identity
        assert_eq!(tx.category.as_deref(), Some("food"));
    }

    #[test]
    fn foreign_currency_is_auto_created_and_converted_for_display() {
        let s = store();
        let tx = s
            .tx_new(&NewTx {
                amount: 110.0,
                name: Some("salary".into()),
                currency: Some("usd".into()),
                category: None,
                recurring: None,
                occurred_on: None,
            })
            .unwrap();
        assert_eq!(tx.currency, "usd");
        assert!(tx.convertible);
        // 110 USD -> EUR = 100
        assert!((tx.amount - 100.0).abs() < 1e-9);
        // usd was auto-created
        assert!(s.cur_list().unwrap().iter().any(|c| c.symbol == "usd"));
    }

    #[test]
    fn category_pruned_when_last_transaction_leaves_it() {
        let s = store();
        let tx = s
            .tx_new(&NewTx {
                amount: -5.0,
                name: Some("coffee".into()),
                currency: None,
                category: Some("drinks".into()),
                recurring: None,
                occurred_on: None,
            })
            .unwrap();
        // Re-tag to a different category; old one becomes empty and is pruned.
        s.tx_edit(&EditTx {
            id: tx.id,
            category: Some("cafe".into()),
            ..Default::default()
        })
        .unwrap();
        let names: Vec<String> = {
            let mut stmt = s
                .conn
                .prepare("SELECT name FROM goodcategory ORDER BY name")
                .unwrap();
            let rows = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap();
            rows.map(|r| r.unwrap()).collect()
        };
        assert_eq!(names, vec!["cafe".to_string()]);
    }

    #[test]
    fn filters_by_currency() {
        let s = store();
        s.tx_new(&NewTx {
            amount: -1.0,
            name: None,
            currency: Some("usd".into()),
            category: None,
            recurring: None,
                occurred_on: None,
        })
        .unwrap();
        s.tx_new(&NewTx {
            amount: -2.0,
            name: None,
            currency: Some("eur".into()),
            category: None,
            recurring: None,
                occurred_on: None,
        })
        .unwrap();
        let usd_only = s
            .tx_list(&TxFilter {
                currencies: vec!["USD".into()],
                ..Default::default()
            })
            .unwrap();
        assert_eq!(usd_only.len(), 1);
        assert_eq!(usd_only[0].currency, "usd");
    }

    #[test]
    fn cannot_delete_currency_in_use() {
        let s = store();
        s.tx_new(&NewTx {
            amount: 1.0,
            name: None,
            currency: Some("usd".into()),
            category: None,
            recurring: None,
                occurred_on: None,
        })
        .unwrap();
        let usd = s
            .cur_list()
            .unwrap()
            .into_iter()
            .find(|c| c.symbol == "usd")
            .unwrap();
        let err = s.cur_delete(usd.id).unwrap_err();
        assert!(matches!(err, Error::InUse(_)));
    }

    #[test]
    fn set_default_currency_auto_creates() {
        let s = store();
        let cur = s.cur_set_default("uah").unwrap();
        assert!(cur.is_default);
        assert_eq!(cur.symbol, "uah");
        assert_eq!(s.default_currency_symbol().unwrap(), "uah");
    }

    #[test]
    fn recurring_is_stored() {
        let s = store();
        let tx = s
            .tx_new(&NewTx {
                amount: -9.99,
                name: Some("netflix".into()),
                currency: None,
                category: None,
                recurring: Some("0 0 1 * *".into()),
                occurred_on: None,
            })
            .unwrap();
        assert_eq!(tx.recurring, vec!["0 0 1 * *".to_string()]);
    }

    #[test]
    fn uses_python_table_names() {
        let s = store();
        let names: Vec<String> = {
            let mut stmt = s
                .conn
                .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
                .unwrap();
            let rows = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap();
            rows.map(|r| r.unwrap()).collect()
        };
        assert!(names.iter().any(|n| n == "goodcategory"));
        assert!(names.iter().any(|n| n == "recurringgood"));
        assert!(!names.iter().any(|n| n == "category"));
        assert!(!names.iter().any(|n| n == "recurring_good"));
    }

    #[test]
    fn renames_legacy_category_table() {
        let dir = std::env::temp_dir().join(format!("mous-legacy-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("data.db");
        {
            let conn = rusqlite::Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE category (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
                 INSERT INTO category (name) VALUES ('legacy');",
            )
            .unwrap();
        }
        let s = Store::open(&path).unwrap();
        let name: String = s
            .conn
            .query_row("SELECT name FROM goodcategory", [], |r| r.get(0))
            .unwrap();
        assert_eq!(name, "legacy");
        assert!(!s.table_exists("category").unwrap());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn reads_python_shaped_category() {
        let dir = std::env::temp_dir().join(format!("mous-py-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("data.db");
        {
            let conn = rusqlite::Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE currency (
                    id INTEGER PRIMARY KEY,
                    symbol TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL UNIQUE,
                    is_default INTEGER NOT NULL DEFAULT 0
                 );
                 CREATE TABLE account (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE
                 );
                 CREATE TABLE goodcategory (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE
                 );
                 CREATE TABLE good (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    value REAL NOT NULL,
                    occurred_on TEXT NOT NULL,
                    currency_id INTEGER NOT NULL,
                    account_id INTEGER NOT NULL,
                    category_id INTEGER
                 );
                 INSERT INTO currency (symbol, name, is_default) VALUES ('eur', 'Euro', 1);
                 INSERT INTO account (name) VALUES ('main');
                 INSERT INTO goodcategory (name) VALUES ('food');
                 INSERT INTO good (name, value, occurred_on, currency_id, account_id, category_id)
                 VALUES ('groceries', -23.1, '2026-09-26', 1, 1, 1);",
            )
            .unwrap();
        }
        let s = Store::open(&path).unwrap();
        let txs = s.tx_list(&TxFilter::default()).unwrap();
        assert_eq!(txs.len(), 1);
        assert_eq!(txs[0].category.as_deref(), Some("food"));
        assert_eq!(txs[0].category_id, Some(1));
        assert_eq!(txs[0].name, "groceries");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn cannot_delete_default_currency() {
        let s = store();
        let eur = s
            .cur_list()
            .unwrap()
            .into_iter()
            .find(|c| c.is_default)
            .unwrap();
        let err = s.cur_delete(eur.id).unwrap_err();
        assert!(matches!(err, Error::Invalid(_)));
    }

    #[test]
    fn unquoted_currency_does_not_pretend_to_be_default() {
        let s = store();
        let tx = s
            .tx_new(&NewTx {
                amount: -5.0,
                name: Some("ticket".into()),
                currency: Some("gbp".into()),
                category: None,
                recurring: None,
                occurred_on: None,
            })
            .unwrap();
        assert!(!tx.convertible);
        assert_eq!(tx.display_currency, "gbp");
        assert_eq!(tx.default_currency, "eur");
        assert!((tx.amount - -5.0).abs() < 1e-9);
    }

    #[test]
    fn civil_date_crosses_midnight_in_local_offset() {
        let utc = Date::from_calendar_date(2026, time::Month::September, 26)
            .unwrap()
            .with_hms(23, 30, 0)
            .unwrap()
            .assume_utc();
        let plus_two = UtcOffset::from_hms(2, 0, 0).unwrap();
        assert_eq!(
            civil_date(utc, Some(plus_two)),
            Date::from_calendar_date(2026, time::Month::September, 27).unwrap()
        );
        assert_eq!(
            civil_date(utc, None),
            Date::from_calendar_date(2026, time::Month::September, 26).unwrap()
        );
    }

    #[test]
    fn filters_by_category_and_stores_explicit_date() {
        let s = store();
        s.tx_new(&NewTx {
            amount: -1.0,
            name: Some("coffee".into()),
            currency: None,
            category: Some("drinks".into()),
            recurring: None,
            occurred_on: Some("2026-01-02".into()),
        })
        .unwrap();
        s.tx_new(&NewTx {
            amount: -2.0,
            name: Some("rent".into()),
            currency: None,
            category: Some("home".into()),
            recurring: None,
            occurred_on: Some("2026-01-03".into()),
        })
        .unwrap();
        let drinks = s
            .tx_list(&TxFilter {
                category: Some("drinks".into()),
                ..Default::default()
            })
            .unwrap();
        assert_eq!(drinks.len(), 1);
        assert_eq!(drinks[0].occurred_on, "2026-01-02");
        let day = Date::from_calendar_date(2026, time::Month::January, 2).unwrap();
        assert_eq!(drinks[0].occurred_unix_time, civil_to_unix(day));
    }
}
