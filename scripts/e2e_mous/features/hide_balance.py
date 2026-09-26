"""Hide balance: Settings toggle + veil dots on the popup; API stays numeric."""

from __future__ import annotations

import re
import time
from pathlib import Path

from e2e_mous.ax import ax_tree_text, click_until_config, send_keys
from e2e_mous.harness import expect, read_config, request, write_config_dict

MASK_RE = re.compile(r"(?:[?#*!•]{4,})")


def run_http(directory: Path) -> None:
    cfg = read_config(directory)
    expect(cfg.get("hide_balance") is False, "hide_balance default off")
    expect(cfg.get("hide_balance_style") == "scramble", "hide_balance_style default scramble")
    from mous.config.utils import load_config

    loaded = load_config()
    expect(loaded.get("hide_balance") is False, "python load hide_balance off")
    expect(loaded.get("hide_balance_style") == "scramble", "python load hide_balance_style scramble")

    cfg["hide_balance"] = True
    cfg["hide_balance_style"] = "veil"
    write_config_dict(directory, cfg)
    loaded = load_config()
    expect(loaded.get("hide_balance") is True, "python load hide_balance on")
    expect(loaded.get("hide_balance_style") == "veil", "python load hide_balance_style veil")

    stripped = dict(cfg)
    stripped.pop("hide_balance_style", None)
    write_config_dict(directory, stripped)
    loaded = load_config()
    expect(loaded.get("hide_balance_style") == "scramble", "missing hide_balance_style defaults scramble")
    cfg["hide_balance_style"] = "scramble"
    write_config_dict(directory, cfg)

    txs = request("GET", "/transactions")
    for item in (txs or {}).get("items", []):
        amount = item.get("amount")
        if amount is not None:
            expect(isinstance(amount, (int, float)), f"API amount still numeric {item}")
        expect(isinstance(item.get("value"), (int, float)), f"ledger value still numeric {item}")
        expect(not (isinstance(amount, str) and MASK_RE.fullmatch(amount)), "API must not mask amount")

    accounts = request("GET", "/accounts")
    main_id = next(a["id"] for a in accounts["items"] if a["name"] == "main")
    balance = request("GET", f"/accounts/{main_id}/balance")
    expect(isinstance((balance or {}).get("amount"), (int, float)), "balance amount still numeric")
    spent = request("GET", f"/accounts/{main_id}/spent")
    expect(isinstance((spent or {}).get("amount"), (int, float)), "spent amount still numeric")

    cfg["hide_balance"] = False
    write_config_dict(directory, cfg)
    loaded = load_config()
    expect(loaded.get("hide_balance") is False, "hide_balance restored off")
    if loaded.get("hide_balance_style") is not None:
        expect(loaded.get("hide_balance_style") == "scramble", "hide_balance_style still scramble")


def run_ui(pid: int, directory: Path, notes: list[str]) -> None:
    if not click_until_config(pid, "Hide balance", directory, "hide_balance", True, toggle=True):
        notes.append("WARN: Hide balance did not write config")
        return
    notes.append("hide balance on")
    cfg = read_config(directory)
    if "hide_balance_style" in cfg:
        expect(cfg.get("hide_balance_style") == "scramble", "hide_balance_style stays scramble")
    send_keys("esc", pid=pid)
    time.sleep(0.25)
    hay = ax_tree_text(pid)
    if MASK_RE.search(hay) or "••••" in hay:
        notes.append("dashboard shows steady dots")
    else:
        notes.append("WARN: hidden amounts not in AX tree")
    send_keys("s", command=True, pid=pid)
    time.sleep(0.25)
    if not click_until_config(pid, "Hide balance", directory, "hide_balance", False, toggle=True):
        notes.append("WARN: hide balance stayed on")
        return
    notes.append("hide balance off")
