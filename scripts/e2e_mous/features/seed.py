"""Seed books + inbox so the headless popup has dashboard and notifications."""

from __future__ import annotations

import json
import time
from datetime import date, datetime, timezone
from pathlib import Path

from e2e_mous.harness import Failed, mous_cli, request, unix_midnight


def run(env: dict[str, str], directory: Path) -> None:
    today = unix_midnight(date.today())
    accounts = request("GET", "/accounts")
    main_id = next(a["id"] for a in accounts["items"] if a["name"] == "main")
    currencies = request("GET", "/currencies")
    eur_id = next(c["id"] for c in currencies["items"] if c["symbol"] == "eur")
    request(
        "POST",
        "/transactions",
        body={
            "name": "coffee",
            "value": -4,
            "currency_id": eur_id,
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    request(
        "POST",
        "/transactions",
        body={
            "name": "rent",
            "value": -800,
            "currency_id": eur_id,
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    usd = request(
        "POST",
        "/currencies",
        body={"symbol": "usd", "name": "US Dollar", "is_default": False},
        expected=201,
    )
    uah = request(
        "POST",
        "/currencies",
        body={"symbol": "uah", "name": "Hryvnia", "is_default": False},
        expected=201,
    )
    request(
        "POST",
        "/transactions",
        body={
            "name": "usd-lunch",
            "value": -11,
            "currency_id": usd["id"],
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    request(
        "POST",
        "/transactions",
        body={
            "name": "uah-metro",
            "value": -40,
            "currency_id": uah["id"],
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    completed = mous_cli(env, ["summary", "14", "days"])
    if completed.returncode != 0:
        raise Failed(f"summary seed failed: {completed.stderr}")
    stdout = completed.stdout
    captured = datetime.now(timezone.utc).isoformat()
    (directory / "summary_report.json").write_text(
        json.dumps({"captured_at": captured, "period": "14 days", "stdout": stdout}, indent=2) + "\n",
        encoding="utf-8",
    )
    inbox = {
        "items": [
            {
                "captured_at": time.time(),
                "period": "14 days",
                "stdout": stdout,
                "read": False,
            }
        ]
    }
    (directory / "report_inbox.json").write_text(json.dumps(inbox, indent=2) + "\n", encoding="utf-8")
