"""Deterministic 1000-row fake ledger for tokenization experiments."""

from __future__ import annotations

import argparse
import asyncio
import random
from datetime import date, timedelta

from oxyde.exceptions import IntegrityError, NotFoundError

from experiments.tokenization.db import database
from mous.db.utils import (
    create_account,
    create_category,
    create_currency,
    create_good,
    create_recurring_good,
    get_account_by_name,
    get_categories,
    get_category_by_name,
    get_currency_by_symbol,
    get_goods,
)

SEED = 42
TARGET_GOODS = 1000
START = date(2025, 3, 1)
END = date(2026, 9, 11)

CATEGORIES = [
    "rent",
    "groceries",
    "restaurants",
    "transport",
    "salary",
    "freelance",
    "subscriptions",
    "entertainment",
    "healthcare",
    "utilities",
    "shopping",
    "travel",
    "coffee",
    "insurance",
    "education",
    "gifts",
]

ACCOUNTS = ["main", "savings", "credit"]

MERCHANTS: dict[str, list[str]] = {
    "rent": ["apartment rent", "parking rent"],
    "groceries": ["lidl", "rewe", "aldi", "bio company", "weekly groceries"],
    "restaurants": ["trattoria roma", "sushi place", "burger joint", "ramen bar"],
    "transport": ["bvg ticket", "uber ride", "bolt ride", "fuel"],
    "salary": ["monthly salary"],
    "freelance": ["design invoice", "consulting fee", "weekend gig"],
    "subscriptions": ["netflix", "spotify", "icloud+", "github pro"],
    "entertainment": ["cinema", "concert", "steam game", "museum"],
    "healthcare": ["pharmacy", "dentist", "gp visit"],
    "utilities": ["electricity", "internet", "water bill"],
    "shopping": ["ikea", "zara", "amazon order", "media markt"],
    "travel": ["flixbus", "lufthansa", "airbnb weekend"],
    "coffee": ["espresso", "flat white", "bakery coffee"],
    "insurance": ["health insurance", "liability insurance"],
    "education": ["online course", "language class", "books"],
    "gifts": ["birthday gift", "flowers", "wedding gift"],
}

# Typical signed amounts: expenses negative, income positive.
AMOUNT_RANGES: dict[str, tuple[float, float, bool]] = {
    "rent": (1150, 1250, True),
    "groceries": (8, 95, True),
    "restaurants": (12, 85, True),
    "transport": (2.5, 38, True),
    "salary": (3100, 3350, False),
    "freelance": (180, 1400, False),
    "subscriptions": (4.99, 19.99, True),
    "entertainment": (8, 75, True),
    "healthcare": (6, 220, True),
    "utilities": (28, 140, True),
    "shopping": (12, 260, True),
    "travel": (19, 420, True),
    "coffee": (2.2, 6.8, True),
    "insurance": (70, 95, True),
    "education": (15, 199, True),
    "gifts": (8, 80, True),
}

WEIGHTS = {
    "rent": 0,
    "groceries": 18,
    "restaurants": 10,
    "transport": 10,
    "salary": 0,
    "freelance": 3,
    "subscriptions": 4,
    "entertainment": 6,
    "healthcare": 3,
    "utilities": 3,
    "shopping": 8,
    "travel": 4,
    "coffee": 14,
    "insurance": 0,
    "education": 3,
    "gifts": 3,
}


async def _get_or_create_account(name: str):
    try:
        return await get_account_by_name(name)
    except NotFoundError:
        try:
            return await create_account(name)
        except IntegrityError:
            return await get_account_by_name(name)


async def _get_or_create_category(name: str):
    try:
        return await get_category_by_name(name)
    except NotFoundError:
        try:
            return await create_category(name)
        except IntegrityError:
            return await get_category_by_name(name)


async def _get_or_create_currency(symbol: str, name: str, is_default: bool = False):
    try:
        return await get_currency_by_symbol(symbol)
    except NotFoundError:
        try:
            return await create_currency(symbol=symbol, name=name, is_default=is_default)
        except IntegrityError:
            return await get_currency_by_symbol(symbol)


def _months(start: date, end: date) -> list[date]:
    cursor = date(start.year, start.month, 1)
    last = date(end.year, end.month, 1)
    out: list[date] = []
    while cursor <= last:
        out.append(cursor)
        if cursor.month == 12:
            cursor = date(cursor.year + 1, 1, 1)
        else:
            cursor = date(cursor.year, cursor.month + 1, 1)
    return out


def _clamp_day(year: int, month: int, day: int) -> date:
    for candidate in (day, 28, 27):
        try:
            return date(year, month, candidate)
        except ValueError:
            continue
    return date(year, month, 1)


def _amount(rng: random.Random, category: str) -> float:
    lo, hi, expense = AMOUNT_RANGES[category]
    raw = rng.uniform(lo, hi)
    cents = round(raw, 2)
    return -cents if expense else cents


async def seed(force: bool = False) -> int:
    async with database():
        existing = await get_goods()
        if len(existing) >= TARGET_GOODS and not force:
            return len(existing)

        if force and existing:
            for good in existing:
                await good.delete()

        rng = random.Random(SEED)
        accounts = {name: await _get_or_create_account(name) for name in ACCOUNTS}
        eur = await _get_or_create_currency("eur", "Euro", is_default=True)
        usd = await _get_or_create_currency("usd", "US Dollar", is_default=False)
        categories = {name: await _get_or_create_category(name) for name in CATEGORIES}

        created = 0
        templates: list[tuple[str, str, str, date, float]] = []

        for month in _months(START, END):
            templates.append(
                (
                    "monthly salary",
                    "salary",
                    "main",
                    _clamp_day(month.year, month.month, 1),
                    round(rng.uniform(3180, 3280), 2),
                )
            )
            templates.append(
                (
                    "apartment rent",
                    "rent",
                    "main",
                    _clamp_day(month.year, month.month, 3),
                    -round(rng.uniform(1180, 1220), 2),
                )
            )
            templates.append(
                (
                    "health insurance",
                    "insurance",
                    "main",
                    _clamp_day(month.year, month.month, 5),
                    -round(rng.uniform(78, 86), 2),
                )
            )
            templates.append(
                (
                    "netflix",
                    "subscriptions",
                    "main",
                    _clamp_day(month.year, month.month, 8),
                    -15.99,
                )
            )
            templates.append(
                (
                    "gym",
                    "subscriptions",
                    "main",
                    _clamp_day(month.year, month.month, 8),
                    -49.99,
                )
            )

        weighted = [(name, w) for name, w in WEIGHTS.items() if w > 0]
        names = [n for n, _ in weighted]
        probs = [w for _, w in weighted]
        total_w = sum(probs)
        probs = [w / total_w for w in probs]

        span_days = (END - START).days
        while len(templates) < TARGET_GOODS:
            day = START + timedelta(days=rng.randrange(span_days + 1))
            category = rng.choices(names, weights=probs, k=1)[0]
            merchant = rng.choice(MERCHANTS[category])
            account = "credit" if category in {"shopping", "travel", "restaurants"} and rng.random() < 0.35 else "main"
            if category == "freelance" and rng.random() < 0.4:
                account = "savings"
            templates.append((merchant, category, account, day, _amount(rng, category)))

        templates = templates[:TARGET_GOODS]
        templates.sort(key=lambda row: row[3])

        first_of: dict[str, int] = {}
        for name, category, account_name, occurred_on, value in templates:
            currency = usd if (category == "travel" and rng.random() < 0.12) else eur
            good = await create_good(
                name=name,
                value=value,
                currency_id=currency.id,
                account_id=accounts[account_name].id,
                occurred_on=occurred_on,
                category_id=categories[category].id,
            )
            created += 1
            if name in {"apartment rent", "netflix", "gym", "monthly salary", "health insurance"}:
                first_of.setdefault(name, good.id)

        crons = {
            "apartment rent": "0 8 3 * *",
            "netflix": "0 9 8 * *",
            "gym": "0 9 8 * *",
            "monthly salary": "0 7 1 * *",
            "health insurance": "0 8 5 * *",
        }
        for name, cron in crons.items():
            good_id = first_of.get(name)
            if good_id is not None:
                await create_recurring_good(good_id=good_id, cron_stamp=cron)

        goods = await get_goods()
        cats = await get_categories()
        print(
            f"seeded goods={len(goods)} created_this_run={created} "
            f"categories={len(cats)} accounts={len(accounts)}"
        )
        return len(goods)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    n = asyncio.run(seed(force=args.force))
    print(f"good_count={n}")


if __name__ == "__main__":
    main()
