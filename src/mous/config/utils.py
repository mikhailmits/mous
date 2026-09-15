"""Read and write the public mous config.json.

On macOS this lives in Application Support, the same place apps keep
user-level files (alongside data.db). Linux uses XDG config; Windows
uses %APPDATA%.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import TypedDict

APP_NAME = "mous"

_DEFAULT_HOST = "127.0.0.1"
_DEFAULT_PORT = 8000
_DEFAULT_REPORT_PERIOD = "14 days"
_DEFAULT_THEME = "system"
_DEFAULT_CURRENCY = "eur"
_THEMES = frozenset({"system", "light", "dark"})
_REQUIRED_KEYS = ("dev", "report_period", "theme", "currency", "notify_in_app", "notify_macos")


class MousConfig(TypedDict):
    host: str
    port: int
    database_path: str
    dev: bool
    report_period: str
    theme: str
    currency: str
    notify_in_app: bool
    notify_macos: bool


def is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def source_repo_root() -> Path | None:
    """Repo root when running from a source checkout; otherwise None."""
    candidate = Path(__file__).resolve().parents[3]
    if (candidate / "pyproject.toml").is_file() and (candidate / "macos" / "Mous").is_dir():
        return candidate
    return None


def is_dev_environment() -> bool:
    """Whether to use the checkout CLI. Set `dev` in config.json; default false."""
    return load_config()["dev"]


def config_dir() -> Path:
    override = os.environ.get("MOUS_CONFIG_DIR")
    if override:
        return Path(override)
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    if sys.platform == "win32":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        return Path(base) / APP_NAME
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return Path(xdg) / APP_NAME
    return Path.home() / ".config" / APP_NAME


def config_path() -> Path:
    return config_dir() / "config.json"


def default_database_path() -> Path:
    return config_dir() / "data.db"


def default_config() -> MousConfig:
    return {
        "host": _DEFAULT_HOST,
        "port": _DEFAULT_PORT,
        "database_path": str(default_database_path()),
        "dev": False,
        "report_period": _DEFAULT_REPORT_PERIOD,
        "theme": _DEFAULT_THEME,
        "currency": _DEFAULT_CURRENCY,
        "notify_in_app": True,
        "notify_macos": True,
    }


def load_config() -> MousConfig:
    """Return config.json merged over defaults. Missing file → defaults."""
    cfg = default_config()
    path = config_path()
    if not path.is_file():
        return cfg
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return cfg
    if not isinstance(raw, dict):
        return cfg
    host = raw.get("host")
    if isinstance(host, str) and host:
        cfg["host"] = host
    port = raw.get("port")
    if isinstance(port, int) and not isinstance(port, bool) and 1 <= port <= 65535:
        cfg["port"] = port
    db = raw.get("database_path")
    if isinstance(db, str) and db:
        cfg["database_path"] = db
    if isinstance(raw.get("dev"), bool):
        cfg["dev"] = raw["dev"]
    period = raw.get("report_period")
    if isinstance(period, str) and period.strip():
        cfg["report_period"] = " ".join(period.split())
    theme = raw.get("theme")
    if isinstance(theme, str) and theme.strip().lower() in _THEMES:
        cfg["theme"] = theme.strip().lower()
    currency = raw.get("currency")
    if isinstance(currency, str) and currency.strip():
        cfg["currency"] = currency.strip().lower()
    if isinstance(raw.get("notify_in_app"), bool):
        cfg["notify_in_app"] = raw["notify_in_app"]
    if isinstance(raw.get("notify_macos"), bool):
        cfg["notify_macos"] = raw["notify_macos"]
    return cfg


def save_config(cfg: MousConfig) -> None:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")


def ensure_config() -> MousConfig:
    """Create config.json with defaults if it does not exist.

    If the file exists but is missing `dev`, `report_period`, `theme`, `currency`,
    or the notify flags, write the merged defaults so those keys are visible
    without clobbering host / port / database_path.
    """
    path = config_path()
    if not path.is_file():
        cfg = default_config()
        save_config(cfg)
        return cfg
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raw = {}
    cfg = load_config()
    if not isinstance(raw, dict) or any(key not in raw for key in _REQUIRED_KEYS):
        save_config(cfg)
    return cfg


def database_path() -> Path:
    return Path(load_config()["database_path"])


def database_url() -> str:
    override = os.environ.get("MOUS_DATABASE_URL")
    if override:
        return override
    return f"sqlite:///{database_path()}"


def api_host() -> str:
    override = os.environ.get("MOUS_API_HOST")
    if override:
        return override
    return load_config()["host"]


def api_port() -> int:
    override = os.environ.get("MOUS_API_PORT")
    if override:
        try:
            return int(override)
        except ValueError:
            pass
    return load_config()["port"]


def report_period() -> str:
    """How often to capture `mous summary`, and the window that command covers."""
    return load_config()["report_period"]
