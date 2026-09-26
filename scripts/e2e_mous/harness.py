"""Isolation, HTTP client, CLI helper, and process control for mous e2e."""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
E2E_PORT = 18765
SWIFT = ROOT / "macos" / "Mous"
PROD_DIR = Path.home() / "Library" / "Application Support" / "mous"
PROD_DB = PROD_DIR / "data.db"

API_SPEC_PATHS = (
    "/accounts",
    "/accounts/{account_id}",
    "/accounts/{account_id}/balance",
    "/accounts/{account_id}/spent",
    "/currencies",
    "/currencies/{id_or_symbol}",
    "/categories",
    "/categories/{id_or_name}",
    "/transactions",
    "/transactions/{transaction_id}",
    "/subscriptions",
    "/subscriptions/{subscription_id}",
)


class Failed(Exception):
    pass


def log(message: str) -> None:
    print(f"e2e: {message}", flush=True)


def expect(cond: bool, message: str) -> None:
    if not cond:
        raise Failed(message)


def unix_midnight(day: date) -> int:
    return int(datetime(day.year, day.month, day.day, tzinfo=timezone.utc).timestamp())


def prod_fingerprint() -> dict[str, tuple[int, int] | None]:
    out: dict[str, tuple[int, int] | None] = {}
    for name in (
        "data.db",
        "data.db-wal",
        "data.db-shm",
        "config.json",
        "report_inbox.json",
        "summary_report.json",
    ):
        path = PROD_DIR / name
        if path.is_file():
            st = path.stat()
            out[name] = (st.st_mtime_ns, st.st_size)
        else:
            out[name] = None
    return out


def assert_prod_untouched(before: dict[str, tuple[int, int] | None]) -> None:
    after = prod_fingerprint()
    if after != before:
        raise Failed(f"production {PROD_DIR} changed during e2e: {before} -> {after}")


def isolated_database(directory: Path) -> Path:
    cfg = json.loads((directory / "config.json").read_text(encoding="utf-8"))
    path = Path(cfg["database_path"]).expanduser().resolve()
    root = directory.resolve()
    if path == PROD_DB.resolve():
        raise Failed("refusing to use production data.db")
    if PROD_DIR.resolve() in path.parents or path.parent == PROD_DIR.resolve():
        raise Failed(f"database_path {path} is under production {PROD_DIR}")
    if root not in path.parents and path.parent != root:
        raise Failed(f"database_path {path} is not inside {root}")
    return path


REQUIRED_CONFIG_KEYS = (
    "host",
    "port",
    "database_path",
    "dev",
    "theme",
    "currency",
    "hide_balance",
    "hide_balance_style",
)
FORBIDDEN_CONFIG_KEYS = (
    "jev_api_key",
    "notify_in_app",
    "notify_macos",
    "report_period",
)


def default_e2e_config(directory: Path) -> dict:
    return {
        "host": "127.0.0.1",
        "port": E2E_PORT,
        "database_path": str(directory / "data.db"),
        "dev": True,
        "theme": "lime",
        "currency": "eur",
        "hide_balance": False,
        "hide_balance_style": "scramble",
    }


def assert_config_shape(cfg: dict, *, allow_missing_style: bool = False) -> None:
    required = REQUIRED_CONFIG_KEYS
    if allow_missing_style:
        required = tuple(k for k in required if k != "hide_balance_style")
    missing = [key for key in required if key not in cfg]
    if missing:
        raise Failed(f"config missing keys {missing}")
    forbidden = [key for key in FORBIDDEN_CONFIG_KEYS if key in cfg]
    if forbidden:
        raise Failed(f"config has removed keys {forbidden}")


def write_config(directory: Path, **overrides: object) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    cfg = default_e2e_config(directory)
    cfg.update(overrides)
    assert_config_shape(cfg)
    path = directory / "config.json"
    path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    isolated_database(directory)
    return path


def read_config(directory: Path) -> dict:
    return json.loads((directory / "config.json").read_text(encoding="utf-8"))


def write_config_dict(directory: Path, cfg: dict) -> None:
    assert_config_shape(cfg, allow_missing_style="hide_balance_style" not in cfg)
    (directory / "config.json").write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")


def env_for(directory: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.pop("MOUS_DATABASE_URL", None)
    env["MOUS_CONFIG_DIR"] = str(directory)
    env["MOUS_API_HOST"] = "127.0.0.1"
    env["MOUS_API_PORT"] = str(E2E_PORT)
    clt = Path("/Library/Developer/CommandLineTools")
    xcode = Path("/Applications/Xcode.app/Contents/Developer")
    if "DEVELOPER_DIR" not in env and clt.is_dir() and not xcode.is_dir():
        env["DEVELOPER_DIR"] = str(clt)
    return env


def request(
    method: str,
    path: str,
    *,
    body: dict | None = None,
    expected: int = 200,
    params: str = "",
) -> dict | None:
    url = f"http://127.0.0.1:{E2E_PORT}{path}{params}"
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as exc:
        status = exc.code
        raw = exc.read()
        if status != expected:
            raise Failed(f"{method} {path} -> {status}, expected {expected}: {raw[:400]!r}") from exc
        if not raw:
            return None
        return json.loads(raw.decode("utf-8"))
    if status != expected:
        raise Failed(f"{method} {path} -> {status}, expected {expected}: {raw[:400]!r}")
    if not raw:
        return None
    return json.loads(raw.decode("utf-8"))


def fetch_bytes(path: str, expected: int = 200) -> bytes:
    url = f"http://127.0.0.1:{E2E_PORT}{path}"
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raise Failed(f"GET {path} -> {exc.code}, expected {expected}") from exc
    if status != expected:
        raise Failed(f"GET {path} -> {status}, expected {expected}")
    return raw


def wait_health(timeout: float = 20.0, proc: subprocess.Popen | None = None) -> None:
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            raise Failed(f"API exited {proc.returncode} before health")
        try:
            payload = request("GET", "/health")
            if payload and payload.get("status") == "ok":
                return
        except Exception as exc:  # noqa: BLE001
            last = str(exc)
        time.sleep(0.15)
    raise Failed(f"API did not become healthy: {last}")


def port_listening(port: int = E2E_PORT) -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.2)
    try:
        return sock.connect_ex(("127.0.0.1", port)) == 0
    finally:
        sock.close()


def start_api(env: dict[str, str]) -> subprocess.Popen:
    if port_listening():
        raise Failed(f"port {E2E_PORT} already bound")
    return subprocess.Popen(
        ["uv", "run", "mous", "serve", "--host", "127.0.0.1", "--port", str(E2E_PORT)],
        cwd=ROOT,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def stop(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            proc.kill()
        proc.wait(timeout=3)


def mous_cli(env: dict[str, str], args: list[str], *, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["uv", "run", "mous", *args],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=check,
    )
