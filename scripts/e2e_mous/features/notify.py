"""In-app inbox and Mac banner flags: config + Settings toggles."""

from __future__ import annotations

from pathlib import Path

from e2e_mous.ax import click_until_config
from e2e_mous.harness import expect, read_config, write_config_dict


def run_http(directory: Path) -> None:
    cfg = read_config(directory)
    expect(cfg.get("notify_in_app") is True, "notify_in_app default on")
    expect(cfg.get("notify_macos") is False, "notify_macos e2e default off")
    from mous.config.utils import load_config

    loaded = load_config()
    expect(loaded.get("notify_in_app") is True, "python load notify_in_app")
    expect(loaded.get("notify_macos") is False, "python load notify_macos")

    cfg["notify_in_app"] = False
    cfg["notify_macos"] = True
    write_config_dict(directory, cfg)
    loaded = load_config()
    expect(loaded.get("notify_in_app") is False, "notify_in_app flipped off")
    expect(loaded.get("notify_macos") is True, "notify_macos flipped on")

    cfg["notify_in_app"] = True
    cfg["notify_macos"] = False
    write_config_dict(directory, cfg)
    loaded = load_config()
    expect(loaded.get("notify_in_app") is True, "notify_in_app restored")
    expect(loaded.get("notify_macos") is False, "notify_macos restored")


def run_ui(pid: int, directory: Path, notes: list[str]) -> None:
    cfg = read_config(directory)
    expect(cfg.get("notify_in_app") is True, "notify_in_app starts on")
    expect(cfg.get("notify_macos") is False, "notify_macos starts off")

    if click_until_config(pid, "Mac banners", directory, "notify_macos", True, toggle=True):
        notes.append("notify macos on")
        if click_until_config(pid, "Mac banners", directory, "notify_macos", False, toggle=True):
            notes.append("notify macos off")
        else:
            notes.append("WARN: Mac banners stayed on")
    else:
        notes.append("WARN: could not click Mac banners")

    if click_until_config(pid, "In-app inbox", directory, "notify_in_app", False, toggle=True):
        notes.append("notify in-app off")
        if click_until_config(pid, "In-app inbox", directory, "notify_in_app", True, toggle=True):
            notes.append("notify in-app on")
        else:
            notes.append("WARN: in-app inbox stayed off")
    else:
        notes.append("WARN: could not click In-app inbox")
