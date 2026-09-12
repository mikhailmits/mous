"""Deterministic gold labels for the three agent tasks on the diagram."""

from __future__ import annotations

import json
from collections import defaultdict
from statistics import mean

from experiments.tokenization.bundle import Bundle, Transaction, load_bundle, month_key
from experiments.tokenization.paths import CORPUS

DISCRETIONARY = {
    "restaurants",
    "entertainment",
    "coffee",
    "shopping",
    "travel",
    "gifts",
}
NECESSARY = {
    "rent",
    "groceries",
    "transport",
    "utilities",
    "insurance",
    "healthcare",
}


def _round_money(value: float) -> float:
    return round(value, 2)


def compute_gold(bundle: Bundle) -> dict:
    txs = bundle.transactions
    income = [tx for tx in txs if tx.value > 0]
    expense = [tx for tx in txs if tx.value < 0]
    by_category: dict[str, float] = defaultdict(float)
    by_month_spend: dict[str, float] = defaultdict(float)
    by_month_income: dict[str, float] = defaultdict(float)
    by_account: dict[str, float] = defaultdict(float)
    for tx in txs:
        cat = tx.category or "uncategorized"
        by_category[cat] += tx.value
        by_account[tx.account] += tx.value
        mk = month_key(tx.occurred_on)
        if tx.value < 0:
            by_month_spend[mk] += -tx.value
        else:
            by_month_income[mk] += tx.value

    spend_by_category = {
        name: _round_money(-total) for name, total in by_category.items() if total < 0
    }
    ranked_spend = sorted(spend_by_category.items(), key=lambda kv: kv[1], reverse=True)
    months = sorted(set(by_month_spend) | set(by_month_income))
    last3 = months[-3:] if len(months) >= 3 else months
    avg_spend = mean(by_month_spend[m] for m in last3) if last3 else 0.0
    avg_income = mean(by_month_income[m] for m in last3) if last3 else 0.0
    net_monthly = avg_income - avg_spend
    discretionary = [
        {"category": name, "spend": spend, "cut_20pct_saves": _round_money(spend * 0.2)}
        for name, spend in ranked_spend
        if name in DISCRETIONARY
    ]
    sub_annual = _round_money(
        sum(-s.value * 12 for s in bundle.subscriptions if s.value is not None and s.value < 0)
    )
    top_expense = min(expense, key=lambda tx: tx.value) if expense else None
    reports = {
        "n_transactions": len(txs),
        "n_income": len(income),
        "n_expense": len(expense),
        "total_income": _round_money(sum(tx.value for tx in income)),
        "total_expense": _round_money(sum(-tx.value for tx in expense)),
        "net": _round_money(sum(tx.value for tx in txs)),
        "top_category_by_spend": ranked_spend[0][0] if ranked_spend else None,
        "top_category_spend": ranked_spend[0][1] if ranked_spend else 0.0,
        "top5_categories": [
            {"category": name, "spend": spend} for name, spend in ranked_spend[:5]
        ],
        "by_category_spend": {k: _round_money(v) for k, v in ranked_spend},
        "by_month_spend": {k: _round_money(v) for k, v in sorted(by_month_spend.items())},
        "by_month_income": {k: _round_money(v) for k, v in sorted(by_month_income.items())},
        "by_account_net": {k: _round_money(v) for k, v in by_account.items()},
        "largest_expense": (
            {
                "name": top_expense.name,
                "value": top_expense.value,
                "date": top_expense.occurred_on,
                "category": top_expense.category,
            }
            if top_expense
            else None
        ),
        "n_subscriptions": len(bundle.subscriptions),
    }
    optimize = {
        "highest_discretionary": discretionary[:5],
        "best_single_cut": discretionary[0] if discretionary else None,
        "subscription_annual_cost": sub_annual,
        "necessary_share": _round_money(
            sum(spend for name, spend in spend_by_category.items() if name in NECESSARY)
        ),
        "discretionary_share": _round_money(
            sum(spend for name, spend in spend_by_category.items() if name in DISCRETIONARY)
        ),
        "playbook": [
            f"Cut 20% of {row['category']} to save {row['cut_20pct_saves']}/period"
            for row in discretionary[:3]
        ],
    }
    forecast = {
        "months_observed": len(months),
        "last3_months": last3,
        "avg_monthly_spend_last3": _round_money(avg_spend),
        "avg_monthly_income_last3": _round_money(avg_income),
        "next_month_spend_naive": _round_money(avg_spend),
        "next_month_income_naive": _round_money(avg_income),
        "next_month_net_naive": _round_money(net_monthly),
        "annualized_net": _round_money(net_monthly * 12),
    }
    return {"reports": reports, "optimize": optimize, "forecasts": forecast}


def save_gold(gold: dict) -> None:
    path = CORPUS / "gold.json"
    path.write_text(json.dumps(gold, indent=2), encoding="utf-8")
    print(f"wrote {path}")


def load_gold() -> dict:
    return json.loads((CORPUS / "gold.json").read_text(encoding="utf-8"))


def score_prediction(pred: dict, gold: dict, task: str | None = None) -> dict:
    """Numeric + ranking score. Missing keys count as failures, not zeros."""

    def num(path: list[str], tolerance: float = 0.05, abs_ok: bool = False) -> dict:
        g = gold
        p = pred
        for key in path:
            if not isinstance(g, dict) or key not in g:
                return {"ok": False, "reason": "missing_gold"}
            if not isinstance(p, dict) or key not in p:
                return {"ok": False, "reason": "missing_pred", "gold": g.get(key) if isinstance(g, dict) else None}
            g = g[key]
            p = p[key]
        try:
            gf = float(g)
            pf = float(p)
        except (TypeError, ValueError):
            return {"ok": False, "reason": "not_numeric", "gold": g, "pred": p}
        if abs_ok:
            pf = abs(pf)
            gf = abs(gf)
        if gf == 0:
            ok = abs(pf) < 1e-6
            rel = 0.0 if ok else 1.0
        else:
            rel = abs(pf - gf) / abs(gf)
            ok = rel <= tolerance
        return {"ok": ok, "rel_error": round(rel, 4), "gold": gf, "pred": pf}

    def exact(path: list[str]) -> dict:
        g = gold
        p = pred
        for key in path:
            if not isinstance(g, dict) or key not in g:
                return {"ok": False, "reason": "missing_gold"}
            if not isinstance(p, dict) or key not in p:
                return {"ok": False, "reason": "missing_pred"}
            g = g[key]
            p = p[key]
        if isinstance(g, str) and isinstance(p, str):
            return {"ok": p.strip().lower() == g.strip().lower(), "gold": g, "pred": p}
        return {"ok": p == g, "gold": g, "pred": p}

    catalog = {
        "n_transactions": lambda: num(["reports", "n_transactions"], 0.0),
        "total_income": lambda: num(["reports", "total_income"], abs_ok=True),
        "total_expense": lambda: num(["reports", "total_expense"], abs_ok=True),
        "net": lambda: num(["reports", "net"]),
        "top_category": lambda: exact(["reports", "top_category_by_spend"]),
        "next_month_spend": lambda: num(["forecasts", "next_month_spend_naive"], abs_ok=True),
        "next_month_income": lambda: num(["forecasts", "next_month_income_naive"], abs_ok=True),
        "discretionary_share": lambda: num(["optimize", "discretionary_share"], abs_ok=True),
        "best_cut_category": lambda: exact(["optimize", "best_single_cut", "category"]),
    }
    by_task = {
        "reports": ["n_transactions", "total_income", "total_expense", "net", "top_category"],
        "optimize": ["discretionary_share", "best_cut_category"],
        "forecasts": ["next_month_spend", "next_month_income"],
    }
    names = by_task.get(task or "", list(catalog))
    checks = {name: catalog[name]() for name in names}
    oks = [1 if item["ok"] else 0 for item in checks.values()]
    return {
        "accuracy": round(sum(oks) / len(oks), 4) if oks else 0.0,
        "passed": int(sum(oks)),
        "total": len(oks),
        "checks": checks,
        "task": task,
    }
