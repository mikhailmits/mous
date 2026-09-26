//! `mousd` — the mous daemon.
//!
//! Owns the SQLite store and serves requests over a Unix domain socket using
//! the length-prefixed `postcard` protocol from `mous-proto`. It is normally
//! auto-spawned by the `mou` CLI: it double-forks to detach, holds a
//! single-instance lock, and self-exits after an idle timeout.

use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use mous_core::Store;
use mous_proto::{paths, read_msg, write_msg, Request, Response};

/// Seconds of inactivity before the daemon exits (0 = never).
const DEFAULT_IDLE_SECS: u64 = 300;

struct Config {
    foreground: bool,
    idle_secs: u64,
}

fn parse_args() -> Config {
    let mut cfg = Config {
        foreground: false,
        idle_secs: std::env::var("MOUS_IDLE_TIMEOUT")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(DEFAULT_IDLE_SECS),
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--foreground" | "-f" => cfg.foreground = true,
            "--idle-timeout" => {
                if let Some(v) = args.next() {
                    cfg.idle_secs = v.parse().unwrap_or(cfg.idle_secs);
                }
            }
            _ => {}
        }
    }
    cfg
}

/// Detach from the controlling terminal via the classic double-fork. Safe here
/// because it runs before any threads are spawned.
unsafe fn daemonize() {
    if libc::fork() > 0 {
        std::process::exit(0);
    }
    if libc::setsid() < 0 {
        std::process::exit(1);
    }
    if libc::fork() > 0 {
        std::process::exit(0);
    }
    redirect_std_to_devnull();
}

unsafe fn redirect_std_to_devnull() {
    let devnull = libc::open(c"/dev/null".as_ptr(), libc::O_RDWR);
    if devnull >= 0 {
        libc::dup2(devnull, 0);
        libc::dup2(devnull, 1);
        libc::dup2(devnull, 2);
        if devnull > 2 {
            libc::close(devnull);
        }
    }
}

/// Acquire the single-instance lock. Returns the held file (keep it alive) or
/// `None` if another daemon already holds it.
fn acquire_lock(path: &Path) -> io::Result<Option<fs::File>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let file = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(path)?;
    let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        let err = io::Error::last_os_error();
        if err.raw_os_error() == Some(libc::EWOULDBLOCK) {
            return Ok(None);
        }
        return Err(err);
    }
    Ok(Some(file))
}

fn main() {
    let cfg = parse_args();

    if !cfg.foreground {
        unsafe { daemonize() };
    }

    let lock_path = paths::lock_path();
    // Keep the lock file alive for the whole process lifetime.
    let _lock = match acquire_lock(&lock_path) {
        Ok(Some(file)) => file,
        Ok(None) => {
            // Another daemon owns the lock; nothing to do.
            std::process::exit(0);
        }
        Err(e) => {
            eprintln!("mousd: cannot acquire lock {}: {e}", lock_path.display());
            std::process::exit(1);
        }
    };

    let socket_path = paths::socket_path();
    if let Some(parent) = socket_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    // Safe to remove a stale socket now that we hold the lock.
    let _ = fs::remove_file(&socket_path);

    let listener = match UnixListener::bind(&socket_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("mousd: cannot bind {}: {e}", socket_path.display());
            std::process::exit(1);
        }
    };
    let _ = fs::set_permissions(&socket_path, fs::Permissions::from_mode(0o600));

    let db_path = paths::db_path();
    let store = match Store::open(&db_path) {
        Ok(s) => Arc::new(Mutex::new(s)),
        Err(e) => {
            eprintln!("mousd: cannot open db {}: {e}", db_path.display());
            let _ = fs::remove_file(&socket_path);
            std::process::exit(1);
        }
    };

    // Last-activity clock in epoch-millis for the idle watcher.
    let last_activity = Arc::new(AtomicU64::new(now_millis()));

    if cfg.idle_secs > 0 {
        let watcher_last = last_activity.clone();
        let watcher_socket = socket_path.clone();
        let idle = cfg.idle_secs;
        thread::spawn(move || loop {
            thread::sleep(Duration::from_secs(5));
            let idle_for = now_millis().saturating_sub(watcher_last.load(Ordering::Relaxed));
            if idle_for >= idle * 1000 {
                let _ = fs::remove_file(&watcher_socket);
                std::process::exit(0);
            }
        });
    }

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let store = store.clone();
                let last = last_activity.clone();
                let sock = socket_path.clone();
                thread::spawn(move || handle_conn(stream, store, last, &sock));
            }
            Err(_) => break,
        }
    }
}

fn handle_conn(
    mut stream: UnixStream,
    store: Arc<Mutex<Store>>,
    last_activity: Arc<AtomicU64>,
    socket_path: &Path,
) {
    loop {
        let req: Request = match read_msg(&mut stream) {
            Ok(r) => r,
            Err(_) => return, // client closed or bad frame
        };
        last_activity.store(now_millis(), Ordering::Relaxed);

        let is_shutdown = matches!(req, Request::Shutdown);
        let resp = dispatch(&store, req);
        if write_msg(&mut stream, &resp).is_err() {
            return;
        }
        if is_shutdown {
            let _ = fs::remove_file(socket_path);
            std::process::exit(0);
        }
    }
}

fn dispatch(store: &Mutex<Store>, req: Request) -> Response {
    let store = match store.lock() {
        Ok(s) => s,
        Err(_) => return Response::Error("daemon store poisoned".into()),
    };
    match req {
        Request::Ping => Response::Pong,
        Request::Shutdown => Response::Ok,
        Request::TxList(filter) => wrap(store.tx_list(&filter), Response::Txs),
        Request::TxGet(id) => wrap(store.tx_get(id), Response::Tx),
        Request::TxNew(tx) => wrap(store.tx_new(&tx), Response::Tx),
        Request::TxEdit(edit) => wrap(store.tx_edit(&edit), Response::Tx),
        Request::TxDelete(id) => wrap(store.tx_delete(id), |_| Response::Ok),
        Request::CurList => wrap(store.cur_list(), Response::Curs),
        Request::CurGet(id) => wrap(store.cur_get(id), Response::Cur),
        Request::CurEditSymbol { id, symbol } => {
            wrap(store.cur_edit_symbol(id, &symbol), Response::Cur)
        }
        Request::CurSetDefault { symbol } => wrap(store.cur_set_default(&symbol), Response::Cur),
        Request::CurDelete(id) => wrap(store.cur_delete(id), |_| Response::Ok),
    }
}

fn wrap<T>(result: mous_core::Result<T>, ok: impl FnOnce(T) -> Response) -> Response {
    match result {
        Ok(value) => ok(value),
        Err(e) => Response::Error(e.to_string()),
    }
}

fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
