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
_DEFAULT_THEME = "lime"
_DEFAULT_CURRENCY = "eur"
_DEFAULT_HIDE_BALANCE_STYLE = "scramble"
_LEGACY_THEMES = frozenset({"system", "light", "dark"})
_THEMES = frozenset({"lime", "leaf", "pale", "mint", "sea", "clay", "white"})
_HIDE_BALANCE_STYLES = frozenset({"scramble", "veil"})
_REQUIRED_KEYS = (
    "host",
    "port",
    "database_path",
    "dev",
    "theme",
    "currency",
    "hide_balance",
    "hide_balance_style",
)


class MousConfig(TypedDict):
    host: str
    port: int
    database_path: str
    dev: bool
    theme: str
    currency: str
    hide_balance: bool
    hide_balance_style: str


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
        "theme": _DEFAULT_THEME,
        "currency": _DEFAULT_CURRENCY,
        "hide_balance": False,
        "hide_balance_style": _DEFAULT_HIDE_BALANCE_STYLE,
    }


def _parse_port(value: object) -> int | None:
    """Accept int, int-like float, or digit string. Reject bools and out-of-range."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        port = value
    elif isinstance(value, float) and value.is_integer():
        port = int(value)
    elif isinstance(value, str) and value.strip().isdigit():
        port = int(value.strip())
    else:
        return None
    if 1 <= port <= 65535:
        return port
    return None


def _missing_required(raw: dict) -> bool:
    return any(key not in raw or raw[key] is None for key in _REQUIRED_KEYS)


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
    if isinstance(host, str) and host.strip():
        cfg["host"] = host.strip()
    port = _parse_port(raw.get("port"))
    if port is not None:
        cfg["port"] = port
    db = raw.get("database_path")
    if isinstance(db, str) and db.strip():
        cfg["database_path"] = db.strip()
    if isinstance(raw.get("dev"), bool):
        cfg["dev"] = raw["dev"]
    theme = raw.get("theme")
    if isinstance(theme, str) and theme.strip():
        normalized = theme.strip().lower()
        if normalized in _LEGACY_THEMES:
            cfg["theme"] = _DEFAULT_THEME
        elif normalized in _THEMES:
            cfg["theme"] = normalized
    currency = raw.get("currency")
    if isinstance(currency, str) and currency.strip():
        cfg["currency"] = currency.strip().lower()
    if isinstance(raw.get("hide_balance"), bool):
        cfg["hide_balance"] = raw["hide_balance"]
    style = raw.get("hide_balance_style")
    if isinstance(style, str) and style.strip().lower() in _HIDE_BALANCE_STYLES:
        cfg["hide_balance_style"] = style.strip().lower()
    return cfg


def save_config(cfg: MousConfig) -> None:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")


def ensure_config() -> MousConfig:
    """Create config.json with defaults if it does not exist.

    If the file exists but is missing required keys, write the merged
    defaults so those keys are visible without clobbering host / port /
    database_path.
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
    if not isinstance(raw, dict) or _missing_required(raw):
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
