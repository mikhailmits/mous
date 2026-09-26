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
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

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
/// because it runs before any threads are spawned. A failed `fork` exits
/// instead of continuing in the parent with stdio discarded.
unsafe fn daemonize() {
    match libc::fork() {
        pid if pid < 0 => std::process::exit(1),
        pid if pid > 0 => std::process::exit(0),
        _ => {}
    }
    if libc::setsid() < 0 {
        std::process::exit(1);
    }
    match libc::fork() {
        pid if pid < 0 => std::process::exit(1),
        pid if pid > 0 => std::process::exit(0),
        _ => {}
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
        let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
    }
    // Safe to remove a stale socket now that we hold the lock.
    retire_runtime(&socket_path);

    let listener = match bind_private_socket(&socket_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("mousd: cannot bind {}: {e}", socket_path.display());
            std::process::exit(1);
        }
    };

    let db_path = paths::db_path();
    let store = match Store::open(&db_path) {
        Ok(s) => Arc::new(Mutex::new(s)),
        Err(e) => {
            eprintln!("mousd: cannot open db {}: {e}", db_path.display());
            retire_runtime(&socket_path);
            std::process::exit(1);
        }
    };

    if let Err(e) = fs::write(
        paths::protocol_stamp_path(),
        mous_proto::PROTOCOL_VERSION.to_string(),
    ) {
        eprintln!("mousd: cannot write protocol stamp: {e}");
        retire_runtime(&socket_path);
        std::process::exit(1);
    }
    let _ = fs::set_permissions(
        paths::protocol_stamp_path(),
        fs::Permissions::from_mode(0o600),
    );

    // Last-activity clock in epoch-millis for the idle watcher.
    let last_activity = Arc::new(AtomicU64::new(now_millis()));
    let shutdown = Arc::new(AtomicBool::new(false));
    let inflight = Arc::new(AtomicU64::new(0));

    if cfg.idle_secs > 0 {
        let watcher_last = last_activity.clone();
        let watcher_shutdown = shutdown.clone();
        let idle = cfg.idle_secs;
        thread::spawn(move || loop {
            thread::sleep(Duration::from_secs(5));
            if watcher_shutdown.load(Ordering::SeqCst) {
                return;
            }
            let idle_for = now_millis().saturating_sub(watcher_last.load(Ordering::Relaxed));
            if idle_for >= idle * 1000 {
                watcher_shutdown.store(true, Ordering::SeqCst);
                return;
            }
        });
    }

    if let Err(e) = listener.set_nonblocking(true) {
        eprintln!("mousd: cannot set nonblocking on {}: {e}", socket_path.display());
        std::process::exit(1);
    }
    loop {
        if shutdown.load(Ordering::SeqCst) {
            break;
        }
        match listener.accept() {
            Ok((stream, _)) => {
                inflight.fetch_add(1, Ordering::SeqCst);
                let store = store.clone();
                let last = last_activity.clone();
                let flag = shutdown.clone();
                let inflight = inflight.clone();
                thread::spawn(move || {
                    handle_conn(stream, store, last, &flag);
                    inflight.fetch_sub(1, Ordering::SeqCst);
                });
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::Interrupted => {
                thread::sleep(Duration::from_millis(20));
            }
            Err(_) => break,
        }
    }

    let deadline = Instant::now() + Duration::from_secs(2);
    while inflight.load(Ordering::SeqCst) > 0 && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(20));
    }
    retire_runtime(&socket_path);
}

fn retire_runtime(socket_path: &Path) {
    let _ = fs::remove_file(socket_path);
    let _ = fs::remove_file(paths::protocol_stamp_path());
}

fn bind_private_socket(path: &Path) -> io::Result<UnixListener> {
    // Create the inode as 0600 even if the process umask is group-writable.
    let previous = unsafe { libc::umask(0o077) };
    let bound = UnixListener::bind(path);
    unsafe {
        libc::umask(previous);
    }
    let listener = bound?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    let mode = fs::metadata(path)?.permissions().mode() & 0o777;
    if mode & 0o077 != 0 {
        let _ = fs::remove_file(path);
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("socket mode is {mode:o}; refusing to listen"),
        ));
    }
    Ok(listener)
}

fn handle_conn(
    mut stream: UnixStream,
    store: Arc<Mutex<Store>>,
    last_activity: Arc<AtomicU64>,
    shutdown: &AtomicBool,
) {
    loop {
        if shutdown.load(Ordering::SeqCst) {
            return;
        }
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
            shutdown.store(true, Ordering::SeqCst);
            return;
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
        Request::CurEnsure {
            symbol,
            name,
            make_default,
        } => wrap(
            store.cur_ensure(&symbol, name.as_deref(), make_default),
            Response::Cur,
        ),
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
