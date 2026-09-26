"""Seed a few transactions so the headless popup has a dashboard."""

from __future__ import annotations

from datetime import date
from pathlib import Path

from e2e_mous.harness import request, unix_midnight


def _currency(symbol: str) -> dict:
    currencies = request("GET", "/currencies")
    return next(c for c in currencies["items"] if c["symbol"] == symbol)


def run(env: dict[str, str], directory: Path) -> None:
    del env, directory
    today = unix_midnight(date.today())
    accounts = request("GET", "/accounts")
    main_id = next(a["id"] for a in accounts["items"] if a["name"] == "main")
    eur_id = _currency("eur")["id"]
    usd_id = _currency("usd")["id"]
    uah_id = _currency("uah")["id"]
    for name, value, currency_id in (
        ("coffee", -4, eur_id),
        ("rent", -800, eur_id),
        ("usd-lunch", -11, usd_id),
        ("uah-metro", -40, uah_id),
    ):
        request(
            "POST",
            "/transactions",
            body={
                "name": name,
                "value": value,
                "currency_id": currency_id,
                "account_id": main_id,
                "occurred_unix_time": today,
            },
            expected=201,
        )
