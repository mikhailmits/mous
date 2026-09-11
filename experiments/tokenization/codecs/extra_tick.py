"""Tick-2 codecs: tool-shaped views and tighter fair encodings.

The diagram is input → agent (+ tools) → reports / optimize / forecasts.
These codecs encode what those tools should return, plus a name-dropping
row format that is still enough for the three tasks.
"""

from __future__ import annotations

import json
from collections import defaultdict

from experiments.tokenization.bundle import Bundle, month_key
from experiments.tokenization.codecs.base import CodecResult, fn_codec
from experiments.tokenization.gold import compute_gold, DISCRETIONARY


def _cents(value: float) -> int:
    return int(round(value * 100))


def _cat_legend(bundle: Bundle) -> dict[str, str]:
    cats = sorted({tx.category or "-" for tx in bundle.transactions})
    codes = {}
    used: set[str] = set()
    for name in cats:
        stem = "".join(ch for ch in name if ch.isalnum())[:3] or "x"
        code = stem
        n = 2
        while code in used:
            code = (stem + str(n))[:4]
            n += 1
        used.add(code)
        codes[name] = code
    return codes


@fn_codec(
    "tool_views",
    "tools",
    "What the agent should get from API tools: balances, monthly series, category spend, subs, forecast window. Not a raw ledger.",
    reversible=False,
)
def tool_views(bundle: Bundle) -> str:
    gold = compute_gold(bundle)
    reports = gold["reports"]
    optimize = gold["optimize"]
    forecasts = gold["forecasts"]
    payload = {
        "tools": {
            "list_transactions.count": reports["n_transactions"],
            "get_balance": reports["by_account_net"],
            "get_spent.by_month": reports["by_month_spend"],
            "get_income.by_month": reports["by_month_income"],
            "list_categories.spend": reports["by_category_spend"],
            "list_subscriptions": [
                {"name": s.name, "value": s.value, "cron": s.cron_stamp}
                for s in bundle.subscriptions
            ],
        },
        "reports": {
            "n_transactions": reports["n_transactions"],
            "n_income": reports["n_income"],
            "n_expense": reports["n_expense"],
            "total_income": reports["total_income"],
            "total_expense": reports["total_expense"],
            "net": reports["net"],
            "top_category_by_spend": reports["top_category_by_spend"],
            "top_category_spend": reports["top_category_spend"],
            "top5_categories": reports["top5_categories"],
        },
        "optimize": {
            "best_single_cut": optimize["best_single_cut"],
            "discretionary_share": optimize["discretionary_share"],
            "subscription_annual_cost": optimize["subscription_annual_cost"],
            "playbook": optimize["playbook"],
        },
        "forecasts": {
            "avg_monthly_spend_last3": forecasts["avg_monthly_spend_last3"],
            "avg_monthly_income_last3": forecasts["avg_monthly_income_last3"],
            "next_month_spend_naive": forecasts["next_month_spend_naive"],
            "next_month_income_naive": forecasts["next_month_income_naive"],
            "next_month_net_naive": forecasts["next_month_net_naive"],
            "last3_months": forecasts["last3_months"],
        },
    }
    return json.dumps(payload, separators=(",", ":"))


@fn_codec(
    "month_cat_sums",
    "tools",
    "GROUP BY month, category. Amounts are integer cents (divide by 100 for euros). Signed: +income -expense. discretionary=restaurants,entertainment,coffee,shopping,travel,gifts. Enough for reports/optimize/forecasts.",
    reversible=False,
)
def month_cat_sums(bundle: Bundle) -> str:
    table: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    counts: dict[str, int] = defaultdict(int)
    for tx in bundle.transactions:
        table[month_key(tx.occurred_on)][tx.category or "-"] += tx.value
        counts[month_key(tx.occurred_on)] += 1
    legend = "value signed (+:income -:expense). discretionary=" + ",".join(sorted(DISCRETIONARY))
    lines = [legend, "format=YYYY-MM cat:cents ... | n"]
    for month in sorted(table):
        parts = [f"{cat}:{_cents(total)}" for cat, total in sorted(table[month].items())]
        lines.append(f"{month} n={counts[month]} " + " ".join(parts))
    return "\n".join(lines)


@fn_codec(
    "task_rows",
    "novel",
    "Fair-enough for the three tasks: YYMMDD cents cat-code. Drops merchant names.",
)
def task_rows(bundle: Bundle) -> str:
    codes = _cat_legend(bundle)
    inv = ",".join(f"{code}={name}" for name, code in codes.items())
    lines = [
        "rows=YYMMDD cents cat. spend magnitude = abs(negative cents)/100",
        "C=" + inv,
    ]
    for tx in bundle.transactions:
        ymd = tx.occurred_on.replace("-", "")[2:]
        lines.append(f"{ymd} {_cents(tx.value)} {codes[tx.category or '-']}")
    return "\n".join(lines)


@fn_codec(
    "month_ids",
    "novel",
    "Monthly groups + 1-3 char name codes + cents + day-of-month. Full line items, reversible with legend.",
)
def month_ids(bundle: Bundle) -> str:
    names = sorted({tx.name for tx in bundle.transactions})
    ni: dict[str, str] = {}
    used: set[str] = set()
    # shortest unique prefix, then numeric suffix
    for name in sorted(names, key=lambda n: (-len(n), n)):
        stem = "".join(ch for ch in name if ch.isalnum()) or "x"
        for width in range(1, min(6, len(stem) + 1)):
            cand = stem[:width]
            if cand not in used:
                ni[name] = cand
                used.add(cand)
                break
        else:
            k = 2
            cand = stem[:3] + str(k)
            while cand in used:
                k += 1
                cand = stem[:3] + str(k)
            ni[name] = cand
            used.add(cand)
    cats = _cat_legend(bundle)
    acc = {"main": "m", "savings": "s", "credit": "c"}
    ymap = {"eur": "e", "usd": "u"}
    lines = [
        "V=cents day=DD. N=" + ",".join(f"{ni[n]}={n}" for n in names),
        "C=" + ",".join(f"{c}={n}" for n, c in cats.items()),
        "A=m main,s savings,c credit Y=e eur,u usd",
    ]
    grouped: dict[str, list] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[month_key(tx.occurred_on)].append(tx)
    for month in sorted(grouped):
        bits = []
        for tx in grouped[month]:
            day = tx.occurred_on[8:]
            bits.append(
                f"{day} {ni[tx.name]} {_cents(tx.value)} {ymap.get(tx.currency, tx.currency[0])}{acc.get(tx.account, tx.account[0])} {cats[tx.category or '-']}"
            )
        lines.append(month[2:] + ":" + ";".join(bits))
    return "\n".join(lines)


@fn_codec(
    "cat_inverted",
    "novel",
    "Inverted index: category -> cents list in date order, month marks. Reversible amounts+timing, names dropped.",
)
def cat_inverted(bundle: Bundle) -> str:
    codes = _cat_legend(bundle)
    lines = ["C=" + ",".join(f"{c}={n}" for n, c in codes.items()), "series=month|cents,cents,..."]
    by_cat: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for tx in bundle.transactions:
        by_cat[tx.category or "-"].append((month_key(tx.occurred_on), _cents(tx.value)))
    for cat in sorted(by_cat):
        grouped: dict[str, list[int]] = defaultdict(list)
        for month, cents in by_cat[cat]:
            grouped[month].append(cents)
        blob = " ".join(
            f"{month[2:]}:" + ",".join(str(v) for v in vals) for month, vals in sorted(grouped.items())
        )
        lines.append(f"{codes[cat]} {blob}")
    return "\n".join(lines)
