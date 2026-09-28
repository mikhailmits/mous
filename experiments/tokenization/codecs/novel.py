"""(x) Compact finance codecs, schema dictionaries, and prompt-friendly layouts."""

from __future__ import annotations

import json
from datetime import date

from experiments.tokenization.bundle import Bundle, Transaction
from experiments.tokenization.codecs.base import fn_codec

EPOCH = date(2025, 1, 1)


def _cents(value: float) -> int:
    return int(round(value * 100))


def _day(iso: str) -> int:
    return (date.fromisoformat(iso) - EPOCH).days


@fn_codec("csv", "novel", "CSV with header. Strong baseline for tabular data.")
def csv_codec(bundle: Bundle) -> str:
    lines = ["date,name,value,ccy,account,category"]
    for tx in bundle.transactions:
        lines.append(
            f"{tx.occurred_on},{tx.name.replace(',', ' ')},{tx.value},{tx.currency},{tx.account},{tx.category or ''}"
        )
    return "\n".join(lines)


@fn_codec("tsv", "novel", "Tab-separated, no header.")
def tsv_codec(bundle: Bundle) -> str:
    lines = [
        f"{tx.occurred_on}\t{tx.name}\t{tx.value}\t{tx.currency}\t{tx.account}\t{tx.category or ''}"
        for tx in bundle.transactions
    ]
    return "\n".join(lines)


@fn_codec(
    "dict_ids",
    "novel",
    "Legend + integer ids + cents + day offsets. Usually the token winner among reversible codecs.",
)
def dict_ids(bundle: Bundle) -> str:
    cats = sorted({tx.category or "-" for tx in bundle.transactions})
    accs = sorted({tx.account for tx in bundle.transactions})
    ccys = sorted({tx.currency for tx in bundle.transactions})
    names = sorted({tx.name for tx in bundle.transactions})
    ci = {v: i for i, v in enumerate(cats)}
    ai = {v: i for i, v in enumerate(accs)}
    yi = {v: i for i, v in enumerate(ccys)}
    ni = {v: i for i, v in enumerate(names)}
    legend = [
        "D=days since 2025-01-01 V=cents",
        "C=" + ",".join(f"{i}={c}" for i, c in enumerate(cats)),
        "A=" + ",".join(f"{i}={a}" for i, a in enumerate(accs)),
        "Y=" + ",".join(f"{i}={y}" for i, y in enumerate(ccys)),
        "N=" + ",".join(f"{i}={n}" for i, n in enumerate(names)),
        "rows=D,N,V,Y,A,C",
    ]
    rows = [
        f"{_day(tx.occurred_on)},{ni[tx.name]},{_cents(tx.value)},{yi[tx.currency]},{ai[tx.account]},{ci[tx.category or '-']}"
        for tx in bundle.transactions
    ]
    return "\n".join(legend + rows)


@fn_codec("columnar", "novel", "Column-wise arrays. Helps models scan one field.")
def columnar(bundle: Bundle) -> str:
    payload = {
        "d": [tx.occurred_on[5:] for tx in bundle.transactions],
        "n": [tx.name for tx in bundle.transactions],
        "v": [_cents(tx.value) for tx in bundle.transactions],
        "y": [tx.currency for tx in bundle.transactions],
        "a": [tx.account for tx in bundle.transactions],
        "c": [tx.category for tx in bundle.transactions],
    }
    return json.dumps(payload, separators=(",", ":"))


@fn_codec("toon", "novel", "Token-oriented object notation: declared columns, then rows.")
def toon(bundle: Bundle) -> str:
    header = f"tx[{len(bundle.transactions)}]{{d,n,v,y,a,c}}:"
    rows = [
        f"{tx.occurred_on[2:]},{tx.name},{tx.value},{tx.currency[0]},{tx.account[0]},{(tx.category or '-')[:3]}"
        for tx in bundle.transactions
    ]
    return header + "\n" + "\n".join(rows)


@fn_codec("abbrev_vowels", "novel", "Drop vowels from names/categories. Lossy-ish but often readable.")
def abbrev_vowels(bundle: Bundle) -> str:
    def crush(text: str) -> str:
        if len(text) <= 3:
            return text
        crushed = "".join(ch for ch in text if ch.lower() not in "aeiou")
        return crushed or text

    lines = [
        f"{tx.occurred_on[2:]} {crush(tx.name)} {tx.value} {tx.currency} {crush(tx.account)} {crush(tx.category or '-')}"
        for tx in bundle.transactions
    ]
    return "\n".join(lines)


@fn_codec("finance_asm", "novel", "Tiny DSL: dYYMMDD nName vCents yA aA cCAT")
def finance_asm(bundle: Bundle) -> str:
    lines = []
    for tx in bundle.transactions:
        d = tx.occurred_on.replace("-", "")[2:]
        cat = (tx.category or "x")[:3]
        lines.append(
            f"d{d} n{tx.name.replace(' ', '_')} v{_cents(tx.value)} y{tx.currency} a{tx.account[0]} c{cat}"
        )
    return "\n".join(lines)


@fn_codec("delta_dates", "novel", "First date absolute, then day deltas. Amounts in cents.")
def delta_dates(bundle: Bundle) -> str:
    txs = bundle.transactions
    if not txs:
        return ""
    prev = _day(txs[0].occurred_on)
    lines = [f"epoch={EPOCH.isoformat()} first={txs[0].occurred_on}"]
    for i, tx in enumerate(txs):
        d = _day(tx.occurred_on)
        delta = d if i == 0 else d - prev
        prev = d
        lines.append(
            f"{delta}|{tx.name}|{_cents(tx.value)}|{tx.currency}|{tx.account}|{tx.category or ''}"
        )
    return "\n".join(lines)


@fn_codec(
    "aggregates_only",
    "novel",
    "Pre-aggregate for the three agent tasks. Fewest tokens, not a fair raw encoding.",
    reversible=False,
)
def aggregates_only(bundle: Bundle) -> str:
    from experiments.tokenization.gold import compute_gold

    gold = compute_gold(bundle)
    slim = {
        "n": gold["reports"]["n_transactions"],
        "in": gold["reports"]["total_income"],
        "out": gold["reports"]["total_expense"],
        "net": gold["reports"]["net"],
        "top": gold["reports"]["top5_categories"],
        "month_out": gold["reports"]["by_month_spend"],
        "month_in": gold["reports"]["by_month_income"],
        "disc": gold["optimize"]["highest_discretionary"],
        "subs_yr": gold["optimize"]["subscription_annual_cost"],
        "fc": gold["forecasts"],
    }
    return json.dumps(slim, separators=(",", ":"))


@fn_codec("yaml_like", "novel", "YAML-ish nested months. Extra punctuation, usually worse.")
def yaml_like(bundle: Bundle) -> str:
    from collections import defaultdict

    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[tx.occurred_on[:7]].append(tx)
    parts = []
    for month, rows in grouped.items():
        parts.append(f"{month}:")
        for tx in rows:
            parts.append(f"  - {tx.occurred_on[8:]} {tx.name} {tx.value} {tx.category}")
    return "\n".join(parts)


@fn_codec("cjk_digits", "novel", "Pack numbers with CJK fullwidth digits + compact cats.")
def cjk_digits(bundle: Bundle) -> str:
    trans = str.maketrans("0123456789.-", "零一二三四五六七八九負點")
    from experiments.tokenization.codecs.languages import CAT_ZH

    lines = []
    for tx in bundle.transactions:
        mag = f"{tx.value:.2f}".translate(trans)
        cat = CAT_ZH.get(tx.category or "", tx.category or "")
        lines.append(f"{tx.occurred_on[2:]}{mag}{cat}")
    return "\n".join(lines)
