"""Pull live API data into the experiment corpus."""

from __future__ import annotations

import json
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date, datetime, timezone
from typing import Any

import httpx

from experiments.tokenization.paths import CORPUS

DEFAULT_BASE = "http://127.0.0.1:8000"


@dataclass(frozen=True)
class Transaction:
    id: int
    name: str
    value: float
    occurred_on: str
    currency: str
    account: str
    category: str | None


@dataclass(frozen=True)
class Subscription:
    id: int
    name: str | None
    value: float | None
    cron_stamp: str
    account: str | None


@dataclass
class Bundle:
    generated_at: str
    transactions: list[Transaction]
    subscriptions: list[Subscription]
    accounts: dict[int, str]
    currencies: dict[int, str]
    categories: dict[int, str]

    def as_json(self) -> dict[str, Any]:
        return {
            "generated_at": self.generated_at,
            "accounts": self.accounts,
            "currencies": self.currencies,
            "categories": self.categories,
            "subscriptions": [asdict(item) for item in self.subscriptions],
            "transactions": [asdict(item) for item in self.transactions],
        }


def _id_map(items: list[dict[str, Any]], key: str) -> dict[int, str]:
    return {int(item["id"]): str(item[key]) for item in items}


def unix_to_iso(unix_time: int) -> str:
    return datetime.fromtimestamp(unix_time, tz=timezone.utc).date().isoformat()


def fetch_bundle(base: str = DEFAULT_BASE) -> Bundle:
    with httpx.Client(base_url=base, timeout=30.0) as client:
        health = client.get("/health")
        health.raise_for_status()
        accounts = client.get("/accounts").json()["items"]
        currencies = client.get("/currencies").json()["items"]
        categories = client.get("/categories").json()["items"]
        subscriptions = client.get("/subscriptions").json()["items"]
        tx_by_id: dict[int, dict[str, Any]] = {}
        for account in accounts:
            page = client.get("/transactions", params={"account_id": account["id"]}).json()["items"]
            for row in page:
                tx_by_id[int(row["id"])] = row
        transactions = list(tx_by_id.values())

    account_names = _id_map(accounts, "name")
    currency_symbols = _id_map(currencies, "symbol")
    category_names = _id_map(categories, "name")
    tx = [
        Transaction(
            id=int(row["id"]),
            name=row["name"],
            value=float(row["value"]),
            occurred_on=unix_to_iso(int(row["occurred_unix_time"])),
            currency=currency_symbols[int(row["currency_id"])],
            account=account_names[int(row["account_id"])],
            category=category_names.get(int(row["category_id"])) if row.get("category_id") else None,
        )
        for row in sorted(transactions, key=lambda item: item["occurred_unix_time"])
    ]
    subs = [
        Subscription(
            id=int(row["id"]),
            name=row.get("name"),
            value=float(row["value"]) if row.get("value") is not None else None,
            cron_stamp=row["cron_stamp"],
            account=account_names.get(int(row["account_id"])) if row.get("account_id") else None,
        )
        for row in subscriptions
    ]
    return Bundle(
        generated_at=datetime.now(timezone.utc).isoformat(),
        transactions=tx,
        subscriptions=subs,
        accounts=account_names,
        currencies=currency_symbols,
        categories=category_names,
    )


def save_bundle(bundle: Bundle) -> None:
    (CORPUS / "bundle.json").write_text(json.dumps(bundle.as_json(), indent=2), encoding="utf-8")
    print(f"wrote {CORPUS / 'bundle.json'} transactions={len(bundle.transactions)}")


def load_bundle() -> Bundle:
    raw = json.loads((CORPUS / "bundle.json").read_text(encoding="utf-8"))
    return Bundle(
        generated_at=raw["generated_at"],
        accounts={int(k): v for k, v in raw["accounts"].items()},
        currencies={int(k): v for k, v in raw["currencies"].items()},
        categories={int(k): v for k, v in raw["categories"].items()},
        subscriptions=[Subscription(**row) for row in raw["subscriptions"]],
        transactions=[Transaction(**row) for row in raw["transactions"]],
    )


def month_key(iso_date: str) -> str:
    return iso_date[:7]


def group_by_month(transactions: list[Transaction]) -> dict[str, list[Transaction]]:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in transactions:
        grouped[month_key(tx.occurred_on)].append(tx)
    return dict(sorted(grouped.items()))


def parse_iso(iso_date: str) -> date:
    return date.fromisoformat(iso_date)
