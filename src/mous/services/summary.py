"""Read-only figures for `mous summary`, computed from the local API."""

from __future__ import annotations

import re
from calendar import monthrange
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

from mous.api.time import unix_to_utc_date, utc_date_to_unix
from mous.config.utils import report_period
from mous.services.api import get_json, items

_DEFAULT_PERIOD = "14 days"
_FORECAST_PERIODS = 3
_MONTH_DAYS = 30
_PERIOD_UNITS = {
    "d": "day",
    "day": "day",
    "days": "day",
    "w": "week",
    "week": "week",
    "weeks": "week",
    "month": "month",
    "months": "month",
    "y": "year",
    "year": "year",
    "years": "year",
}
_PERIOD_PATTERN = re.compile(
    r"(?:(\d+)\s*)?(days?|weeks?|months?|years?|[dwy])",
    re.IGNORECASE,
)


class PeriodParseError(ValueError):
    """CLI period text could not be turned into a date range."""


@dataclass(frozen=True)
class SubscriptionCharge:
    name: str
    value: float
    """One charge amount, not accumulated over the period."""


@dataclass(frozen=True)
class GoodSpend:
    name: str
    spent: float
    """Total spent on this good over the period."""


@dataclass
class Summary:
    period: str
    """Human-readable datetime range, e.g. '1 Sep 2026 – 15 Sep 2026'."""
    n: int
    """How many transactions landed in this period."""
    currency: str
    """Default currency symbol; amounts are not converted."""
    income: float
    expense: float
    saved: float
    top: list[str]
    runway: float | None
    next_month_spent_predictions: float
    """Next month's spend, estimated from several prior periods."""
    keep_up_subscriptions: list[SubscriptionCharge] = field(default_factory=list)
    """Recurring charges you will keep paying if you do not cancel."""
    keep_up_goods: list[GoodSpend] = field(default_factory=list)
    """One-off goods with total spent accumulated over the period."""


def parse_period(text: str | None = None, *, end: date | None = None) -> tuple[date, date]:
    """Inclusive `[start, end]` for a duration ending today (default: last 14 days)."""
    last = end or date.today()
    raw = " ".join((text or "").split()).lower()
    if not raw:
        raw = " ".join(report_period().split()).lower() or _DEFAULT_PERIOD
    match = _PERIOD_PATTERN.fullmatch(raw)
    if match is None:
        raise PeriodParseError(
            f"unknown period {text!r}; try 14 days, month, 1 day, 2 weeks, 1 year"
        )
    count_text, unit_text = match.group(1), match.group(2).lower()
    unit = _PERIOD_UNITS[unit_text]
    count = int(count_text) if count_text else 1
    if count < 1:
        raise PeriodParseError(f"period must be at least 1 {unit}")
    first = _period_start(count, unit, last)
    if first > last:
        first = last
    return first, last


def _period_start(count: int, unit: str, end: date) -> date:
    if unit == "day":
        return end - timedelta(days=count - 1)
    if unit == "week":
        return end - timedelta(days=count * 7 - 1)
    if unit == "month":
        return _shift_months(end, -count) + timedelta(days=1)
    return _shift_years(end, -count) + timedelta(days=1)


def _shift_months(day: date, months: int) -> date:
    index = day.year * 12 + (day.month - 1) + months
    year, month0 = divmod(index, 12)
    month = month0 + 1
    return date(year, month, min(day.day, monthrange(year, month)[1]))


def _shift_years(day: date, years: int) -> date:
    return _shift_months(day, years * 12)


def format_summary(report: Summary) -> str:
    """CLI stdout for one `Summary` — the text `mous summary` prints."""
    money = report.currency
    top = "[" + ", ".join(report.top) + "]" if report.top else "[]"
    runway_value = "..." if report.runway is None else f"{report.runway:g}"
    lines = [
        "summary",
        f"  {report.period}",
        f"    currency = {money}",
        f"    n = {report.n}",
        f"    in = {report.income:g} {money}",
        f"    out = {report.expense:g} {money}",
        f"    saved = {report.saved:g} {money}",
        f"    top = {top}",
        f"    runway = {runway_value}",
        f"    next_month_spent_predictions = {report.next_month_spent_predictions:g} {money}",
        "",
        "    if you keep up you will spend money on:",
    ]
    for item in report.keep_up_subscriptions:
        lines.append(f"      {item.name} = {item.value:g} {money}")
    total = subscription_spend_total(report.keep_up_subscriptions)
    lines.append(f"      Total spent on subscriptions = {total:g} {money}")
    for item in report.keep_up_goods:
        lines.append(f"      {item.name} = {item.spent:g} {money}")
    return "\n".join(lines) + "\n"


def build_summary(
    period: str | None = None,
    *,
    start: date | None = None,
    end: date | None = None,
) -> Summary:
    """Assemble one summary for `[start, end]` (default: last 14 days through today)."""
    last = end or date.today()
    if start is None:
        first, last = parse_period(period, end=last)
    else:
        first = start
        if first > last:
            first, last = last, first
    span = (last - first).days + 1
    txs = _transactions(first, last)
    history = _transactions(
        last - timedelta(days=span * _FORECAST_PERIODS - 1),
        last,
    )
    categories = _category_names()
    subs = keep_up_subscriptions()
    sub_names = {item.name for item in subs}
    goods = keep_up_goods(txs, exclude_names=sub_names)
    spent = period_expense(txs)
    return Summary(
        period=period_label(first, last),
        n=transaction_count(txs),
        currency=_currency_symbol(),
        income=period_in(txs),
        expense=spent,
        saved=period_saved(txs),
        top=top_spend(txs, categories),
        runway=runway(_balance(), spent, span),
        next_month_spent_predictions=next_month_spent_prediction(history, last, span),
        keep_up_subscriptions=subs,
        keep_up_goods=goods,
    )


def period_label(start: date, end: date) -> str:
    """Human-readable datetime range."""
    if start == end:
        return _short_date(start)
    return f"{_short_date(start)} – {_short_date(end)}"


def _short_date(day: date) -> str:
    return f"{day.day} {day.strftime('%b %Y')}"


def transaction_count(transactions: list[dict[str, Any]]) -> int:
    """How many transactions in the period (`n`)."""
    return len(transactions)


def period_in(transactions: list[dict[str, Any]]) -> float:
    """Income over the period."""
    return sum(value for value in (_value(row) for row in transactions) if value > 0)


def period_expense(transactions: list[dict[str, Any]]) -> float:
    """Expense magnitude over the period."""
    return sum(-value for value in (_value(row) for row in transactions) if value < 0)


def period_saved(transactions: list[dict[str, Any]]) -> float:
    """Income minus expenses over the period."""
    return period_in(transactions) - period_expense(transactions)


def top_spend(
    transactions: list[dict[str, Any]],
    categories: dict[int, str] | None = None,
) -> list[str]:
    """Highest-spend category names (or good names if nothing is tagged)."""
    names = categories or {}
    by_category: dict[int, float] = defaultdict(float)
    for row in transactions:
        value = _value(row)
        if value >= 0:
            continue
        category_id = row.get("category_id")
        if isinstance(category_id, int) and category_id in names:
            by_category[category_id] += -value
    if by_category:
        ranked = sorted(by_category, key=lambda cid: (-by_category[cid], names[cid]))
        return [names[cid] for cid in ranked]
    by_name: dict[str, float] = defaultdict(float)
    for row in transactions:
        value = _value(row)
        if value >= 0:
            continue
        by_name[str(row.get("name") or "")] += -value
    return [name for name, _spent in sorted(by_name.items(), key=lambda item: (-item[1], item[0])) if name]


def runway(balance: float, expense: float, span_days: int) -> float | None:
    """Days the current balance lasts at this period's burn rate."""
    if span_days <= 0 or expense <= 0:
        return None
    daily = expense / span_days
    if daily <= 0:
        return None
    days = balance / daily
    return days if days > 0 else 0.0


def next_month_spent_prediction(
    transactions: list[dict[str, Any]],
    end: date,
    span_days: int,
    periods: int = _FORECAST_PERIODS,
) -> float:
    """Predict next month's spend from several prior periods of `span_days`."""
    if span_days <= 0 or periods <= 0:
        return 0.0
    cursor = end
    spent = 0.0
    days = 0
    for _ in range(periods):
        start = cursor - timedelta(days=span_days - 1)
        chunk = [
            row
            for row in transactions
            if start <= _occurred_on(row) <= cursor
        ]
        spent += period_expense(chunk)
        days += span_days
        cursor = start - timedelta(days=1)
    if days <= 0:
        return 0.0
    return spent / days * _MONTH_DAYS


def keep_up_subscriptions() -> list[SubscriptionCharge]:
    """Subscriptions that will still charge if you keep this up (each row is one value)."""
    rows = items(get_json("/subscriptions"))
    charges: list[SubscriptionCharge] = []
    for row in rows:
        name = str(row.get("name") or "").strip()
        raw = row.get("value")
        if not name or not isinstance(raw, (int, float)) or isinstance(raw, bool):
            continue
        charges.append(SubscriptionCharge(name=name, value=float(raw)))
    charges.sort(key=lambda item: (item.value, item.name))
    return charges


def subscription_spend_total(charges: list[SubscriptionCharge]) -> float:
    """Sum of expense charges (magnitude). Income subscriptions are ignored."""
    return sum(-item.value for item in charges if item.value < 0)


def keep_up_goods(
    transactions: list[dict[str, Any]],
    exclude_names: set[str] | None = None,
) -> list[GoodSpend]:
    """Goods you will keep buying, with spend accumulated over the period."""
    skip = exclude_names or set()
    totals: dict[str, float] = defaultdict(float)
    for row in transactions:
        value = _value(row)
        if value >= 0:
            continue
        name = str(row.get("name") or "").strip()
        if not name or name in skip:
            continue
        totals[name] += -value
    return [
        GoodSpend(name=name, spent=spent)
        for name, spent in sorted(totals.items(), key=lambda item: (-item[1], item[0]))
    ]


def _transactions(start: date, end: date) -> list[dict[str, Any]]:
    payload = get_json(
        "/transactions",
        {
            "from_unix_time": utc_date_to_unix(start),
            "to_unix_time": utc_date_to_unix(end),
        },
    )
    return items(payload)


def _category_names() -> dict[int, str]:
    names: dict[int, str] = {}
    for row in items(get_json("/categories")):
        cid = row.get("id")
        name = row.get("name")
        if isinstance(cid, int) and isinstance(name, str) and name:
            names[cid] = name
    return names


def _currency_symbol() -> str:
    rows = items(get_json("/currencies"))
    for row in rows:
        symbol = row.get("symbol")
        if row.get("is_default") is True and isinstance(symbol, str) and symbol:
            return symbol
    if rows:
        symbol = rows[0].get("symbol")
        if isinstance(symbol, str) and symbol:
            return symbol
    return "eur"


def _balance() -> float:
    accounts = items(get_json("/accounts"))
    account_id = None
    for row in accounts:
        if row.get("name") == "main" and isinstance(row.get("id"), int):
            account_id = row["id"]
            break
    if account_id is None and accounts and isinstance(accounts[0].get("id"), int):
        account_id = accounts[0]["id"]
    if account_id is None:
        return 0.0
    payload = get_json(f"/accounts/{account_id}/balance")
    if isinstance(payload, dict) and isinstance(payload.get("amount"), (int, float)):
        return float(payload["amount"])
    return 0.0


def _value(row: dict[str, Any]) -> float:
    raw = row.get("value")
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        return 0.0
    return float(raw)


def _occurred_on(row: dict[str, Any]) -> date:
    raw = row.get("occurred_unix_time")
    if isinstance(raw, int):
        return unix_to_utc_date(raw)
    return date.min
