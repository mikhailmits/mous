"""Spaced and glued income lines in the quick-entry field.

Parser unit cases live in MousCoreCheck. This module types the same shapes
into the headless popup and checks the API row. Spaces in the field are
kept — do not assert a stripped line.
"""

from __future__ import annotations

import time

from e2e_mous.ax import send_keys
from e2e_mous.harness import expect, request


def _keys(pid: int, stroke: str, command: bool = False) -> bool:
    return send_keys(stroke, command=command, pid=pid)


def _default_symbol() -> str:
    currencies = request("GET", "/currencies")
    for item in (currencies or {}).get("items", []):
        if item.get("is_default"):
            return str(item.get("symbol") or "eur").lower()
    return "eur"


def _hii_count(value: float, symbol: str) -> int:
    currencies = request("GET", "/currencies")
    cid = next(
        (c["id"] for c in (currencies or {}).get("items", []) if c["symbol"] == symbol),
        None,
    )
    if cid is None:
        return 0
    txs = request("GET", "/transactions")
    n = 0
    for row in (txs or {}).get("items", []):
        if str(row.get("name") or "").lower() != "hii":
            continue
        try:
            if abs(float(row.get("value") or 0) - value) < 1e-6 and row.get("currency_id") == cid:
                n += 1
        except (TypeError, ValueError):
            continue
    return n


def _wait_hii(value: float, symbol: str, count: int, timeout: float = 8.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _hii_count(value, symbol) >= count:
            return True
        time.sleep(0.25)
    return False


def run_ui(pid: int, notes: list[str]) -> None:
    symbol = _default_symbol()

    expect(_keys(pid, "a", command=True), "select entry for spaced income")
    _keys(pid, "delete")
    time.sleep(0.05)
    before = _hii_count(10, symbol)
    expect(_keys(pid, "+ 10 hii"), "type spaced + 10 hii")
    time.sleep(0.08)
    expect(_keys(pid, "return"), "submit spaced income")
    expect(
        _wait_hii(10, symbol, before + 1),
        "spaced + 10 hii posted +10 default currency",
    )
    notes.append("parser + 10 hii income")

    expect(_keys(pid, "a", command=True), "select entry for glued income")
    _keys(pid, "delete")
    time.sleep(0.05)
    before = _hii_count(10, symbol)
    expect(_keys(pid, "+10hii"), "type glued +10hii")
    time.sleep(0.08)
    expect(_keys(pid, "return"), "submit glued income")
    expect(
        _wait_hii(10, symbol, before + 1),
        "glued +10hii posted +10 default currency",
    )
    notes.append("parser +10hii income")
