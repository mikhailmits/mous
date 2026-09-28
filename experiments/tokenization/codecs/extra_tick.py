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
    "What the agent should get from API tools: balances, monthly series, category spend, subs, forecast window. Copy reports/optimize/forecasts JSON as-is; do not re-sum months (use last3 already computed).",
    reversible=False,
)
def tool_views(bundle: Bundle) -> str:
    gold = compute_gold(bundle)
    reports = gold["reports"]
    optimize = gold["optimize"]
    forecasts = gold["forecasts"]
    last3 = forecasts["last3_months"]
    payload = {
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
            "last3_months": last3,
        },
        "tools": {
            "list_transactions.count": reports["n_transactions"],
            "get_balance": reports["by_account_net"],
            "get_spent.last3_months": {m: reports["by_month_spend"][m] for m in last3},
            "get_income.last3_months": {m: reports["by_month_income"][m] for m in last3},
            "list_categories.spend": reports["by_category_spend"],
            "list_subscriptions": [
                {"name": s.name, "value": s.value, "cron": s.cron_stamp}
                for s in bundle.subscriptions
            ],
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


def _round2(value: float) -> float:
    return round(value, 2)


def _income_by_category(bundle: Bundle) -> dict[str, float]:
    totals: dict[str, float] = defaultdict(float)
    for tx in bundle.transactions:
        if tx.value > 0:
            totals[tx.category or "-"] += tx.value
    return {name: _round2(total) for name, total in sorted(totals.items())}


@fn_codec(
    "tool_copy",
    "tools",
    "Minified copy-paste of the three task JSON blobs. Copy reports/optimize/forecasts as written; do not re-sum.",
    reversible=False,
)
def tool_copy(bundle: Bundle) -> str:
    gold = compute_gold(bundle)
    payload = {
        "reports": {
            "n_transactions": gold["reports"]["n_transactions"],
            "n_income": gold["reports"]["n_income"],
            "n_expense": gold["reports"]["n_expense"],
            "total_income": gold["reports"]["total_income"],
            "total_expense": gold["reports"]["total_expense"],
            "net": gold["reports"]["net"],
            "top_category_by_spend": gold["reports"]["top_category_by_spend"],
            "top_category_spend": gold["reports"]["top_category_spend"],
        },
        "optimize": {
            "best_single_cut": gold["optimize"]["best_single_cut"],
            "discretionary_share": gold["optimize"]["discretionary_share"],
            "subscription_annual_cost": gold["optimize"]["subscription_annual_cost"],
        },
        "forecasts": {
            "avg_monthly_spend_last3": gold["forecasts"]["avg_monthly_spend_last3"],
            "avg_monthly_income_last3": gold["forecasts"]["avg_monthly_income_last3"],
            "next_month_spend_naive": gold["forecasts"]["next_month_spend_naive"],
            "next_month_income_naive": gold["forecasts"]["next_month_income_naive"],
            "next_month_net_naive": gold["forecasts"]["next_month_net_naive"],
            "last3_months": gold["forecasts"]["last3_months"],
        },
    }
    return json.dumps(payload, separators=(",", ":"))


@fn_codec(
    "tool_rollup",
    "tools",
    "Tool GROUP-BYs only. total_expense=sum(spend_by_category); total_income=sum(income_by_category); net=income-expense; top=argmax(spend_by_category); discretionary_share=sum(discretionary_spend) as MONEY not percent; best_single_cut=argmax(discretionary_spend); subscription_annual_cost=sum(-value*12) for negative subs; last3 naive forecast=mean of last3_spend / last3_income. Do not use months outside last3.",
    reversible=False,
)
def tool_rollup(bundle: Bundle) -> str:
    gold = compute_gold(bundle)
    reports = gold["reports"]
    last3 = gold["forecasts"]["last3_months"]
    spend = reports["by_category_spend"]
    payload = {
        "n": reports["n_transactions"],
        "n_income": reports["n_income"],
        "n_expense": reports["n_expense"],
        "spend_by_category": spend,
        "income_by_category": _income_by_category(bundle),
        "last3_spend": {month: reports["by_month_spend"][month] for month in last3},
        "last3_income": {month: reports["by_month_income"][month] for month in last3},
        "discretionary_spend": {
            name: spend[name] for name in sorted(DISCRETIONARY) if name in spend
        },
        "subscriptions": [
            {"name": sub.name, "value": sub.value, "cron": sub.cron_stamp}
            for sub in bundle.subscriptions
        ],
    }
    return json.dumps(payload, separators=(",", ":"))


def _desc(mapping: dict[str, float]) -> dict[str, float]:
    return dict(sorted(mapping.items(), key=lambda kv: (-kv[1], kv[0])))


@fn_codec(
    "tool_rollup_ranked",
    "tools",
    "Same GROUP-BYs as tool_rollup, but spend maps are sorted high-to-low so argmax is the first key. total_expense=sum(spend_by_category); total_income=sum(income_by_category); net=income-expense; top=first spend key; discretionary_share=sum(discretionary_spend) MONEY; best_single_cut=first discretionary key; last3 naive=mean. Do not use months outside last3.",
    reversible=False,
)
def tool_rollup_ranked(bundle: Bundle) -> str:
    payload = json.loads(tool_rollup.encode(bundle).token_payload)
    payload["spend_by_category"] = _desc(payload["spend_by_category"])
    payload["income_by_category"] = _desc(payload["income_by_category"])
    payload["discretionary_spend"] = _desc(payload["discretionary_spend"])
    return json.dumps(payload, separators=(",", ":"))


def reconstruct_from_rollup(payload: dict) -> dict:
    """Local check that tool_rollup numbers reconstruct gold task fields."""
    spend = payload["spend_by_category"]
    income = payload["income_by_category"]
    disc = payload["discretionary_spend"]
    last3_spend = list(payload["last3_spend"].values())
    last3_income = list(payload["last3_income"].values())
    total_income = _round2(sum(income.values()))
    total_expense = _round2(sum(spend.values()))
    avg_spend = _round2(sum(last3_spend) / len(last3_spend))
    avg_income = _round2(sum(last3_income) / len(last3_income))
    best = max(disc.items(), key=lambda kv: kv[1])
    sub_annual = _round2(
        sum(-row["value"] * 12 for row in payload["subscriptions"] if row["value"] is not None and row["value"] < 0)
    )
    return {
        "n_transactions": payload["n"],
        "total_income": total_income,
        "total_expense": total_expense,
        "net": _round2(total_income - total_expense),
        "top_category_by_spend": max(spend.items(), key=lambda kv: kv[1])[0],
        "discretionary_share": _round2(sum(disc.values())),
        "best_single_cut": best[0],
        "subscription_annual_cost": sub_annual,
        "next_month_spend_naive": avg_spend,
        "next_month_income_naive": avg_income,
        "next_month_net_naive": _round2(avg_income - avg_spend),
    }
