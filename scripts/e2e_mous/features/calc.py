"""Inline FX calculator in the quick-entry field."""

from __future__ import annotations

import time

from e2e_mous.ax import send_keys, wait_ui
from e2e_mous.harness import expect, request


def _keys(pid: int, stroke: str, command: bool = False) -> bool:
    return send_keys(stroke, command=command, pid=pid)


def _wait_named(name: str, value: float, symbol: str, timeout: float = 8.0) -> dict | None:
    currencies = request("GET", "/currencies")
    cid = next(
        (c["id"] for c in (currencies or {}).get("items", []) if c["symbol"] == symbol),
        None,
    )
    if cid is None:
        return None
    deadline = time.time() + timeout
    needle = name.lower()
    while time.time() < deadline:
        txs = request("GET", "/transactions")
        for row in (txs or {}).get("items", []):
            if str(row.get("name") or "").lower() != needle:
                continue
            if abs(float(row.get("value") or 0) - value) < 1e-6 and row.get("currency_id") == cid:
                return row
        time.sleep(0.25)
    return None


def _named_count(name: str) -> int:
    txs = request("GET", "/transactions")
    needle = name.lower()
    return sum(
        1
        for row in (txs or {}).get("items", [])
        if str(row.get("name") or "").lower() == needle
    )


def _leftover() -> float | None:
    accounts = request("GET", "/accounts")
    main_id = next(a["id"] for a in (accounts or {}).get("items", []) if a["name"] == "main")
    balance = request("GET", f"/accounts/{main_id}/balance")
    try:
        return float((balance or {}).get("amount"))
    except (TypeError, ValueError):
        return None


def _tx_count() -> int:
    txs = request("GET", "/transactions")
    if (txs or {}).get("count") is not None:
        return int(txs["count"])
    return len((txs or {}).get("items") or [])


def _same_money(left: float | None, right: float | None) -> bool:
    if left is None or right is None:
        return left is right
    return abs(left - right) < 1e-6


def run_ui(pid: int, notes: list[str]) -> None:
    leftover = _leftover()
    posted = _tx_count()
    expect(_keys(pid, "a", command=True), "select entry for unsigned calc")
    _keys(pid, "delete")
    time.sleep(0.15)
    expect(_keys(pid, "10 eur to usd"), "type unsigned tab calc")
    time.sleep(0.2)
    expect(_keys(pid, "tab"), "unsigned tab converts")
    time.sleep(0.4)
    expect(_tx_count() == posted, "unsigned tab must not post")
    expect(_same_money(_leftover(), leftover), "unsigned tab leftover unchanged")
    expect(_keys(pid, "return"), "return on unsigned convert")
    time.sleep(0.35)
    expect(_tx_count() == posted, "return on unsigned converted line must not post")
    expect(_same_money(_leftover(), leftover), "unsigned convert leftover unchanged")
    notes.append("fx calc unsigned tab 10eur→11usd no post")

    expect(_keys(pid, "a", command=True), "select entry for calc")
    _keys(pid, "delete")
    time.sleep(0.15)
    expect(_keys(pid, "-10 eur to usd"), "type tab calc line")
    time.sleep(0.2)
    expect(_keys(pid, "tab"), "tab converts")
    time.sleep(0.4)
    expect(_keys(pid, " fxcalc"), "description after tab convert")
    expect(_keys(pid, "return"), "submit tab-converted usd")
    expect(
        _wait_named("fxcalc", -11, "usd") is not None,
        "tab calc posted -11 usd fxcalc",
    )
    notes.append("fx calc tab 10eur→11usd")

    expect(_keys(pid, "a", command=True), "select entry for enter calc")
    _keys(pid, "delete")
    time.sleep(0.15)
    before = _named_count("fxenter")
    leftover = _leftover()
    posted = _tx_count()
    expect(_keys(pid, "-10 eur to uah"), "type enter calc line")
    time.sleep(0.2)
    expect(_keys(pid, "return"), "enter converts without posting")
    time.sleep(0.4)
    expect(_named_count("fxenter") == before, "enter on calc must not post")
    expect(_tx_count() == posted, "enter on calc API unchanged")
    expect(_same_money(_leftover(), leftover), "enter on calc leftover unchanged")
    wait_ui(pid, "400uah", timeout=2.0)
    expect(_keys(pid, " fxenter"), "description after enter convert")
    expect(_keys(pid, "return"), "submit enter-converted uah")
    expect(
        _wait_named("fxenter", -400, "uah") is not None,
        "enter calc posted -400 uah fxenter",
    )
    notes.append("fx calc enter 10eur→400uah")

    time.sleep(0.45)
    expect(_keys(pid, "a", command=True), "select entry for coffee to go")
    _keys(pid, "delete")
    time.sleep(0.15)
    expect(_keys(pid, "-3 coffee to go"), "type coffee to go")
    time.sleep(0.25)
    expect(_keys(pid, "return"), "post coffee to go")
    expect(
        _wait_named("coffee to go", -3, "eur") is not None,
        "coffee to go stayed a spending description",
    )
    notes.append("fx calc skips coffee to go")
