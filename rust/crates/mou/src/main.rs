//! `mou` — the mous CLI client.
//!
//! Parses the command line, connects to `mousd` over its Unix socket
//! (auto-spawning the daemon if it isn't running), sends one request, and
//! renders the response as a table (default), JSON (`--json`), or YAML
//! (`--yaml`).

use std::env;
use std::io;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use clap::{Args, Parser, Subcommand};
use mous_proto::{
    paths, read_msg, write_msg, CurView, EditTx, NewTx, Request, Response, TxFilter, TxView,
};

#[derive(Parser, Debug)]
#[command(
    name = "mou",
    about = "mous CLI: a tiny box where finances are spinning",
    version
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Cmd>,

    // ---- transaction root flags (used when no subcommand is given) ----
    /// List all transactions.
    #[arg(long)]
    all: bool,
    /// Target a single transaction by id.
    #[arg(long)]
    id: Option<i64>,
    /// Delete the transaction given by --id.
    #[arg(short = 'd', long = "delete")]
    delete: bool,
    #[arg(long = "edit-amount", allow_hyphen_values = true)]
    edit_amount: Option<f64>,
    #[arg(long = "edit-name", allow_hyphen_values = true)]
    edit_name: Option<String>,
    #[arg(long = "edit-currency", allow_hyphen_values = true)]
    edit_currency: Option<String>,
    #[arg(long = "edit-category", allow_hyphen_values = true)]
    edit_category: Option<String>,
    #[arg(long = "edit-recurring", allow_hyphen_values = true)]
    edit_recurring: Option<String>,
    /// Civil day to store when editing (`YYYY-MM-DD`).
    #[arg(long = "edit-date")]
    edit_date: Option<String>,
    /// Assign a category when editing `--id`. Without `--id`, filter listings.
    #[arg(long = "ctg", allow_hyphen_values = true)]
    ctg: Option<String>,
    /// Filter listings by one or more native currency symbols.
    #[arg(long = "curr", num_args = 1.., value_name = "SYMBOL", allow_hyphen_values = true)]
    curr: Vec<String>,
    /// Filter listings to on/after this date (YYYY-MM-DD).
    #[arg(long)]
    since: Option<String>,
    /// Filter listings to on/before this date (YYYY-MM-DD).
    #[arg(long)]
    until: Option<String>,

    /// Stop the running daemon without starting a new one.
    #[arg(long)]
    shutdown: bool,
    #[arg(long, global = true)]
    json: bool,
    #[arg(long, global = true)]
    yaml: bool,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Create a transaction: mou new <±amount> [--name ...] [--curr ...] [--ctg ...] [--recurring ...]
    New(NewArgs),
    /// Manage currencies.
    Cur(CurArgs),
}

#[derive(Args, Debug)]
struct NewArgs {
    /// Signed amount: negative is an expense, positive is income.
    #[arg(allow_hyphen_values = true)]
    amount: f64,
    #[arg(long, allow_hyphen_values = true)]
    name: Option<String>,
    #[arg(long = "curr", allow_hyphen_values = true)]
    curr: Option<String>,
    #[arg(long = "ctg", allow_hyphen_values = true)]
    ctg: Option<String>,
    /// Recurrence (ISO datetime or cron), stored verbatim.
    #[arg(long = "recurring", allow_hyphen_values = true)]
    recurring: Option<String>,
    /// Civil day `YYYY-MM-DD`. Defaults to the local calendar day.
    #[arg(long = "date")]
    date: Option<String>,
}

#[derive(Args, Debug)]
struct CurArgs {
    /// List all currencies.
    #[arg(long)]
    all: bool,
    /// Target a currency by id.
    #[arg(long)]
    id: Option<i64>,
    /// Delete the currency given by --id.
    #[arg(short = 'd', long = "delete")]
    delete: bool,
    /// Change the symbol of the currency given by --id.
    #[arg(long = "edit-symbol", allow_hyphen_values = true)]
    edit_symbol: Option<String>,
    /// Set the default currency (auto-created if missing).
    #[arg(long = "set-default", value_name = "SYMBOL", allow_hyphen_values = true)]
    set_default: Option<String>,
}

enum Format {
    Table,
    Json,
    Yaml,
}

fn main() {
    let cli = Cli::parse();
    if cli.shutdown {
        shutdown_if_running();
        return;
    }
    let format = if cli.json {
        Format::Json
    } else if cli.yaml {
        Format::Yaml
    } else {
        Format::Table
    };

    let request = match build_request(&cli) {
        Ok(Some(req)) => req,
        Ok(None) => {
            // Nothing to do; show help.
            print_usage();
            return;
        }
        Err(msg) => {
            eprintln!("mou: {msg}");
            std::process::exit(2);
        }
    };

    match call(&request) {
        Ok(resp) => {
            if !render(&resp, &format) {
                if let Response::Error(msg) = &resp {
                    eprintln!("mou: {msg}");
                }
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("mou: cannot talk to daemon: {e}");
            std::process::exit(1);
        }
    }
}

fn build_request(cli: &Cli) -> Result<Option<Request>, String> {
    match &cli.command {
        Some(Cmd::New(args)) => Ok(Some(Request::TxNew(NewTx {
            amount: args.amount,
            name: args.name.clone(),
            currency: args.curr.clone(),
            category: args.ctg.clone(),
            recurring: args.recurring.clone(),
            occurred_on: args.date.clone(),
        }))),
        Some(Cmd::Cur(args)) => build_cur_request(args).map(Some),
        None => build_tx_root_request(cli),
    }
}

fn build_cur_request(args: &CurArgs) -> Result<Request, String> {
    if let Some(symbol) = &args.set_default {
        return Ok(Request::CurSetDefault {
            symbol: symbol.clone(),
        });
    }
    if args.delete {
        let id = args.id.ok_or("cur -d requires --id")?;
        return Ok(Request::CurDelete(id));
    }
    if let Some(symbol) = &args.edit_symbol {
        let id = args.id.ok_or("cur --edit-symbol requires --id")?;
        return Ok(Request::CurEditSymbol {
            id,
            symbol: symbol.clone(),
        });
    }
    if let Some(id) = args.id {
        return Ok(Request::CurGet(id));
    }
    // default (including --all): list
    Ok(Request::CurList)
}

fn build_tx_root_request(cli: &Cli) -> Result<Option<Request>, String> {
    let has_field_edit = cli.edit_amount.is_some()
        || cli.edit_name.is_some()
        || cli.edit_currency.is_some()
        || cli.edit_category.is_some()
        || cli.edit_recurring.is_some()
        || cli.edit_date.is_some();
    // `--ctg` with `--id` assigns a category. Without `--id` it filters a listing.
    let assigning_category = cli.ctg.is_some() && cli.id.is_some();

    if cli.delete {
        let id = cli.id.ok_or("-d requires --id")?;
        return Ok(Some(Request::TxDelete(id)));
    }
    if has_field_edit || assigning_category {
        let id = cli.id.ok_or("editing requires --id")?;
        return Ok(Some(Request::TxEdit(EditTx {
            id,
            amount: cli.edit_amount,
            name: cli.edit_name.clone(),
            currency: cli.edit_currency.clone(),
            category: cli.edit_category.clone().or_else(|| cli.ctg.clone()),
            recurring: cli.edit_recurring.clone(),
            occurred_on: cli.edit_date.clone(),
        })));
    }
    if let Some(id) = cli.id {
        return Ok(Some(Request::TxGet(id)));
    }
    let has_filter = !cli.curr.is_empty()
        || cli.since.is_some()
        || cli.until.is_some()
        || cli.ctg.is_some();
    if cli.all || has_filter {
        return Ok(Some(Request::TxList(TxFilter {
            since: cli.since.clone(),
            until: cli.until.clone(),
            currencies: cli.curr.clone(),
            category: cli.ctg.clone(),
        })));
    }
    Ok(None)
}

// ---- transport -------------------------------------------------------------

fn call(request: &Request) -> io::Result<Response> {
    let mut stream = connect_or_spawn()?;
    write_msg(&mut stream, request)?;
    read_msg(&mut stream)
}

fn connect_or_spawn() -> io::Result<UnixStream> {
    replace_stale_daemon();
    let sock = paths::socket_path();
    if let Ok(stream) = UnixStream::connect(&sock) {
        return Ok(stream);
    }
    spawn_daemon()?;
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        match UnixStream::connect(&sock) {
            Ok(stream) => return Ok(stream),
            Err(_) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            Err(e) => return Err(e),
        }
    }
}

fn replace_stale_daemon() {
    let sock = paths::socket_path();
    if UnixStream::connect(&sock).is_err() {
        return;
    }
    let stamp = std::fs::read_to_string(paths::protocol_stamp_path()).ok();
    let current = mous_proto::PROTOCOL_VERSION.to_string();
    if stamp.as_deref().map(str::trim) == Some(current.as_str()) {
        return;
    }
    shutdown_if_running();
    let deadline = Instant::now() + Duration::from_secs(2);
    while sock.exists() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(20));
    }
}

fn shutdown_if_running() {
    let sock = paths::socket_path();
    let Ok(mut stream) = UnixStream::connect(&sock) else {
        return;
    };
    let _ = write_msg(&mut stream, &Request::Shutdown);
    let _ = read_msg::<_, Response>(&mut stream);
}

fn spawn_daemon() -> io::Result<()> {
    let bin = daemon_bin();
    // mousd double-forks and the initial process exits 0 quickly, so wait() returns fast.
    let status = Command::new(&bin)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| io::Error::new(e.kind(), format!("failed to spawn {}: {e}", bin.display())))?
        .wait()?;
    if !status.success() {
        return Err(io::Error::other(format!(
            "failed to spawn {}: {status}",
            bin.display()
        )));
    }
    Ok(())
}

fn daemon_bin() -> PathBuf {
    if let Some(p) = env::var_os("MOUSD_BIN") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidate = dir.join("mousd");
            if candidate.exists() {
                return candidate;
            }
        }
    }
    PathBuf::from("mousd")
}

// ---- rendering -------------------------------------------------------------

/// Returns true if the response was rendered (i.e. not an unhandled error).
fn render(resp: &Response, format: &Format) -> bool {
    match resp {
        Response::Ok => {
            match format {
                Format::Json => println!("{{\"status\":\"ok\"}}"),
                Format::Yaml => println!("status: ok"),
                Format::Table => println!("ok"),
            }
            true
        }
        Response::Pong => {
            println!("pong");
            true
        }
        Response::Tx(tx) => render_one(format, tx, print_tx_table),
        Response::Txs(txs) => render_many(format, txs, print_tx_table),
        Response::Cur(cur) => render_one(format, cur, print_cur_table),
        Response::Curs(curs) => render_many(format, curs, print_cur_table),
        Response::Error(_) => false,
    }
}

fn render_one<T: serde::Serialize>(
    format: &Format,
    value: &T,
    table: impl FnOnce(&[T]),
) -> bool {
    match format {
        Format::Json => print_json(value),
        Format::Yaml => print_yaml(value),
        Format::Table => {
            table(std::slice::from_ref(value));
            true
        }
    }
}

fn render_many<T: serde::Serialize>(format: &Format, values: &[T], table: impl FnOnce(&[T])) -> bool {
    match format {
        Format::Json => print_json(values),
        Format::Yaml => print_yaml(values),
        Format::Table => {
            table(values);
            true
        }
    }
}

fn print_json<T: serde::Serialize + ?Sized>(value: &T) -> bool {
    match serde_json::to_string_pretty(value) {
        Ok(s) => {
            println!("{s}");
            true
        }
        Err(e) => {
            eprintln!("mou: json error: {e}");
            false
        }
    }
}

fn print_yaml<T: serde::Serialize + ?Sized>(value: &T) -> bool {
    match serde_yaml::to_string(value) {
        Ok(s) => {
            print!("{s}");
            true
        }
        Err(e) => {
            eprintln!("mou: yaml error: {e}");
            false
        }
    }
}

fn print_tx_table(txs: &[TxView]) {
    if txs.is_empty() {
        println!("(no transactions)");
        return;
    }
    let mut rows: Vec<[String; 6]> = Vec::with_capacity(txs.len());
    let mut any_native = false;
    for tx in txs {
        let category = tx.category.clone().unwrap_or_else(|| "-".into());
        // Always display in the default currency; only fall back to the native
        // currency (marked '*') when there is no FX quote to convert with.
        let amount = if tx.convertible {
            format!("{:.2} {}", tx.amount, tx.display_currency)
        } else {
            any_native = true;
            format!("{:.2} {}*", tx.value, tx.currency)
        };
        let recurring = if tx.recurring.is_empty() {
            String::new()
        } else {
            format!("↻ {}", tx.recurring.join(", "))
        };
        rows.push([
            tx.id.to_string(),
            tx.occurred_on.clone(),
            tx.name.clone(),
            category,
            amount,
            recurring,
        ]);
    }
    let headers = ["ID", "DATE", "NAME", "CATEGORY", "AMOUNT", "RECUR"];
    print_table(&headers, &rows);
    if any_native {
        let target = txs
            .first()
            .map(|tx| tx.default_currency.as_str())
            .unwrap_or("the default currency");
        println!("* no FX quote to {target}; shown in native currency");
    }
}

fn print_cur_table(curs: &[CurView]) {
    if curs.is_empty() {
        println!("(no currencies)");
        return;
    }
    let rows: Vec<[String; 4]> = curs
        .iter()
        .map(|c| {
            [
                c.id.to_string(),
                c.symbol.clone(),
                c.name.clone(),
                if c.is_default {
                    "default".into()
                } else {
                    String::new()
                },
            ]
        })
        .collect();
    let headers = ["ID", "SYMBOL", "NAME", ""];
    print_table(&headers, &rows);
}

fn print_table<const N: usize>(headers: &[&str; N], rows: &[[String; N]]) {
    let mut widths = [0usize; N];
    for (i, h) in headers.iter().enumerate() {
        widths[i] = h.len();
    }
    for row in rows {
        for (i, cell) in row.iter().enumerate() {
            widths[i] = widths[i].max(cell.chars().count());
        }
    }
    let mut header_line = String::new();
    for (i, h) in headers.iter().enumerate() {
        header_line.push_str(&pad(h, widths[i]));
        if i + 1 < N {
            header_line.push_str("  ");
        }
    }
    println!("{}", header_line.trim_end());
    for row in rows {
        let mut line = String::new();
        for (i, cell) in row.iter().enumerate() {
            line.push_str(&pad(cell, widths[i]));
            if i + 1 < N {
                line.push_str("  ");
            }
        }
        println!("{}", line.trim_end());
    }
}

fn pad(s: &str, width: usize) -> String {
    let len = s.chars().count();
    if len >= width {
        s.to_string()
    } else {
        format!("{s}{}", " ".repeat(width - len))
    }
}

fn print_usage() {
    println!("mou — finances CLI");
    println!();
    println!("Transactions:");
    println!("  mou --all [--curr SYM..] [--ctg NAME] [--since D] [--until D]");
    println!("  mou --id N | -d --id N");
    println!("  mou new <±amount> [--name ..] [--curr SYM] [--ctg NAME] [--date YYYY-MM-DD] [--recurring S]");
    println!("  mou --id N --edit-amount ±V --edit-date YYYY-MM-DD --edit-category NAME");
    println!();
    println!("Currencies:");
    println!("  mou cur --all | --id N | --set-default SYM   (currencies auto-create on use)");
    println!("  mou cur --edit-symbol SYM --id N | -d --id N");
    println!();
    println!("Output: --json | --yaml (default: table)");
}
