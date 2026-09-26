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
    #[arg(long = "edit-name")]
    edit_name: Option<String>,
    #[arg(long = "edit-currency")]
    edit_currency: Option<String>,
    #[arg(long = "edit-category")]
    edit_category: Option<String>,
    #[arg(long = "edit-recurring")]
    edit_recurring: Option<String>,
    /// Assign a category (created if missing) to --id, or filter is not applied here.
    #[arg(long = "ctg")]
    ctg: Option<String>,
    /// Filter listings by one or more native currency symbols.
    #[arg(long = "curr", num_args = 1.., value_name = "SYMBOL")]
    curr: Vec<String>,
    /// Filter listings to on/after this date (YYYY-MM-DD).
    #[arg(long)]
    since: Option<String>,
    /// Filter listings to on/before this date (YYYY-MM-DD).
    #[arg(long)]
    until: Option<String>,

    // ---- global output format ----
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
    #[arg(long)]
    name: Option<String>,
    #[arg(long = "curr")]
    curr: Option<String>,
    #[arg(long = "ctg")]
    ctg: Option<String>,
    /// Recurrence (ISO datetime or cron), stored verbatim.
    #[arg(long = "recurring")]
    recurring: Option<String>,
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
    #[arg(long = "edit-symbol")]
    edit_symbol: Option<String>,
    /// Set the default currency (auto-created if missing).
    #[arg(long = "set-default", value_name = "SYMBOL")]
    set_default: Option<String>,
}

enum Format {
    Table,
    Json,
    Yaml,
}

fn main() {
    let cli = Cli::parse();
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
            if render(&resp, &format) {
                // rendered fine
            } else if let Response::Error(msg) = &resp {
                eprintln!("mou: {msg}");
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
    let has_edit = cli.edit_amount.is_some()
        || cli.edit_name.is_some()
        || cli.edit_currency.is_some()
        || cli.edit_category.is_some()
        || cli.edit_recurring.is_some()
        || cli.ctg.is_some();

    if cli.delete {
        let id = cli.id.ok_or("-d requires --id")?;
        return Ok(Some(Request::TxDelete(id)));
    }
    if has_edit {
        let id = cli.id.ok_or("editing requires --id")?;
        return Ok(Some(Request::TxEdit(EditTx {
            id,
            amount: cli.edit_amount,
            name: cli.edit_name.clone(),
            currency: cli.edit_currency.clone(),
            category: cli.edit_category.clone().or_else(|| cli.ctg.clone()),
            recurring: cli.edit_recurring.clone(),
        })));
    }
    if let Some(id) = cli.id {
        return Ok(Some(Request::TxGet(id)));
    }
    let has_filter = !cli.curr.is_empty() || cli.since.is_some() || cli.until.is_some();
    if cli.all || has_filter {
        return Ok(Some(Request::TxList(TxFilter {
            since: cli.since.clone(),
            until: cli.until.clone(),
            currencies: cli.curr.clone(),
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

fn spawn_daemon() -> io::Result<()> {
    let bin = daemon_bin();
    // mousd double-forks and the initial process exits 0 quickly, so wait() returns fast.
    Command::new(&bin)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| io::Error::new(e.kind(), format!("failed to spawn {}: {e}", bin.display())))?
        .wait()?;
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
        Response::Tx(tx) => {
            match format {
                Format::Json => print_json(tx),
                Format::Yaml => print_yaml(tx),
                Format::Table => print_tx_table(std::slice::from_ref(tx)),
            }
            true
        }
        Response::Txs(txs) => {
            match format {
                Format::Json => print_json(txs),
                Format::Yaml => print_yaml(txs),
                Format::Table => print_tx_table(txs),
            }
            true
        }
        Response::Cur(cur) => {
            match format {
                Format::Json => print_json(cur),
                Format::Yaml => print_yaml(cur),
                Format::Table => print_cur_table(std::slice::from_ref(cur)),
            }
            true
        }
        Response::Curs(curs) => {
            match format {
                Format::Json => print_json(curs),
                Format::Yaml => print_yaml(curs),
                Format::Table => print_cur_table(curs),
            }
            true
        }
        Response::Error(_) => false,
    }
}

fn print_json<T: serde::Serialize>(value: &T) {
    match serde_json::to_string_pretty(value) {
        Ok(s) => println!("{s}"),
        Err(e) => eprintln!("mou: json error: {e}"),
    }
}

fn print_yaml<T: serde::Serialize>(value: &T) {
    match serde_yaml::to_string(value) {
        Ok(s) => print!("{s}"),
        Err(e) => eprintln!("mou: yaml error: {e}"),
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
        println!(
            "* no FX quote to {}; shown in native currency",
            txs[0].display_currency
        );
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
    println!("  mou --all [--curr SYM..] [--since YYYY-MM-DD] [--until YYYY-MM-DD]   list");
    println!("  mou --id N                                                          get one");
    println!("  mou -d --id N                                                       delete");
    println!("  mou new <±amount> [--name ..] [--curr SYM] [--ctg NAME] [--recurring S]");
    println!("  mou --id N --edit-amount ±V --edit-name .. --edit-currency SYM \\");
    println!("        --edit-category NAME --ctg NAME --edit-recurring S           edit");
    println!();
    println!("Currencies:");
    println!("  mou cur --all | --id N | --edit-symbol SYM --id N | -d --id N | --set-default SYM");
    println!();
    println!("Output: --json | --yaml (default: table)");
}
