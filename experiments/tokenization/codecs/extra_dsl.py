"""Readable finance DSLs aimed at beating yaml_like on GPT-5 / o200k_base.

Attacks (all keep spaces; none glue fields):
- monthly buckets + dict_ids + cents
- cron/template extraction for salary, rent, netflix, gym
- category-major inverted indexes with run-length amounts
- drop year, cents, 1-char field tags, monthly structure
"""

from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Callable

from experiments.tokenization.bundle import Bundle, Transaction
from experiments.tokenization.codecs.base import CodecResult, fn_codec

# Unique 1-char category tags (mnemonic, not first-letter — that collides).
CAT_CODE = {
    "coffee": "c",
    "education": "d",
    "entertainment": "e",
    "freelance": "f",
    "gifts": "z",
    "groceries": "g",
    "healthcare": "h",
    "insurance": "i",
    "rent": "r",
    "restaurants": "o",
    "salary": "y",
    "shopping": "p",
    "subscriptions": "b",
    "transport": "t",
    "travel": "v",
    "utilities": "u",
}
ACC_CODE = {"main": "m", "credit": "k", "savings": "w"}
CCY_CODE = {"eur": "e", "usd": "$"}

_CRON_SPECS = (
    ("monthly salary", 1, None, "salary"),
    ("apartment rent", 3, None, "rent"),
    ("netflix", 8, -15.99, "subscriptions"),
    ("gym", 8, -49.99, "subscriptions"),
)


def _cents(value: float) -> int:
    return int(round(value * 100))


def _money(value: float) -> str:
    """Signed dollars without useless trailing zeros (-1181.0 → -1181)."""
    cents = _cents(value)
    if cents % 100 == 0:
        return str(cents // 100)
    text = f"{cents / 100:.2f}"
    if text.endswith("0"):
        text = text[:-1]
    return text


def _rle(values: list[float], *, as_cents: bool = False, sep: str = " ") -> str:
    counts: Counter[int] = Counter()
    order: list[int] = []
    for value in values:
        key = _cents(value)
        if key not in counts:
            order.append(key)
        counts[key] += 1
    parts = []
    for key in order:
        token = str(key) if as_cents else _money(key / 100)
        n = counts[key]
        parts.append(f"{token}*{n}" if n > 1 else token)
    return sep.join(parts)


def _name_cat(bundle: Bundle) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for tx in bundle.transactions:
        mapping[tx.name] = tx.category or "-"
    return mapping


def _months(txs: list[Transaction]) -> dict[str, list[Transaction]]:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in txs:
        grouped[tx.occurred_on[:7]].append(tx)
    return dict(sorted(grouped.items()))


def _sub_line(bundle: Bundle, *, as_cents: bool = False) -> str:
    bits = []
    for sub in bundle.subscriptions:
        if sub.value is None:
            continue
        amount = str(_cents(sub.value)) if as_cents else _money(sub.value)
        bits.append(f"{sub.name}={amount}")
    return "SUB " + " ".join(bits)


def _sparse_suffix(tx: Transaction) -> str:
    extra = []
    if tx.account != "main":
        extra.append(ACC_CODE.get(tx.account, tx.account[:1]))
    if tx.currency != "eur":
        extra.append(CCY_CODE.get(tx.currency, tx.currency[:1]))
    return (" " + " ".join(extra)) if extra else ""


def _legend_cats() -> str:
    return "C " + " ".join(f"{code}={name}" for name, code in CAT_CODE.items())


def _pack(
    name: str,
    family: str,
    text: str,
    notes: str,
    decode: str,
    reversible: bool,
) -> CodecResult:
    return CodecResult(
        name=name,
        family=family,
        text=text,
        notes=notes,
        decode_instructions=decode,
        reversible=reversible,
    )


def _year_then_month_rows(
    grouped: dict[str, list[Transaction]],
    row: Callable[[Transaction], str],
) -> list[str]:
    parts: list[str] = []
    year: str | None = None
    for month, txs in grouped.items():
        y = month[:4]
        if y != year:
            parts.append(f"Y{y[2:]}")
            year = y
        parts.append(month[5:])
        for tx in txs:
            parts.append(row(tx))
    return parts


@fn_codec(
    "dsl_month_ids",
    "novel",
    "Monthly buckets + name dict ids + cents. Spaces. Defaults a=main ccy=eur.",
)
def dsl_month_ids(bundle: Bundle) -> CodecResult:
    names = sorted({tx.name for tx in bundle.transactions})
    name_cat = _name_cat(bundle)
    nid = {name: i for i, name in enumerate(names)}
    legend = [
        "V=cents/100 D=day N=id. Yxx then MM. default a=m ccy=e. k=credit w=savings $=usd",
        _legend_cats(),
        "N " + " ".join(f"{i}={name}/{CAT_CODE.get(name_cat[name], '?')}" for i, name in enumerate(names)),
        _sub_line(bundle, as_cents=True),
    ]

    def row(tx: Transaction) -> str:
        return f"{tx.occurred_on[8:]} {nid[tx.name]} {_cents(tx.value)}{_sparse_suffix(tx)}"

    parts = legend + _year_then_month_rows(_months(bundle.transactions), row)
    decode = (
        "Monthly ledger. Y25 then MM headers. Rows: DD name_id cents [k|w] [$]. "
        "N legend is id=merchant/category_code. Dollars=cents/100. SUB already in rows; "
        "annual sub cost = sum(-v*12) for SUB values < 0 (cents/100)."
    )
    return _pack(
        "dsl_month_ids",
        "novel",
        "\n".join(parts),
        "Monthly buckets + dict_ids + cents; sparse account/ccy; spaces kept.",
        decode,
        True,
    )


@fn_codec(
    "dsl_cron",
    "novel",
    "Salary/rent/netflix/gym as monthly cron expansions; remaining rows as exceptions.",
)
def dsl_cron(bundle: Bundle) -> CodecResult:
    grouped = _months(bundle.transactions)
    month_keys = list(grouped)
    n_months = len(month_keys)
    covered: set[int] = set()
    cron_lines = [
        f"RANGE {month_keys[0][2:]}..{month_keys[-1][2:]} n={n_months} default a=m ccy=e V=cents",
        _legend_cats(),
        _sub_line(bundle, as_cents=True),
    ]

    for name, day, fixed, cat in _CRON_SPECS:
        matched: list[Transaction] = []
        seen_month: set[str] = set()
        for tx in bundle.transactions:
            if tx.name != name:
                continue
            if int(tx.occurred_on[8:]) != day:
                continue
            if fixed is not None and abs(tx.value - fixed) > 1e-9:
                continue
            mk = tx.occurred_on[:7]
            if mk in seen_month:
                continue
            seen_month.add(mk)
            matched.append(tx)
        matched.sort(key=lambda tx: tx.occurred_on)
        # Keep a full RANGE expansion only when every month is present.
        if len(matched) != n_months:
            continue
        for tx in matched:
            covered.add(tx.id)
        code = CAT_CODE.get(cat, cat[:1])
        if fixed is not None:
            cron_lines.append(f"CRON {name} d{day} v{_cents(fixed)} {code} x{n_months}")
        else:
            vals = " ".join(str(_cents(tx.value)) for tx in matched)
            cron_lines.append(f"CRON {name} d{day} {code} {vals}")

    exceptions = [tx for tx in bundle.transactions if tx.id not in covered]
    cron_lines.append("X")
    cron_lines.extend(
        _year_then_month_rows(
            _months(exceptions),
            lambda tx: (
                f"{tx.occurred_on[8:]} {tx.name} {_cents(tx.value)} "
                f"{CAT_CODE.get(tx.category or '-', '?')}{_sparse_suffix(tx)}"
            ),
        )
    )
    decode = (
        "CRON expands once per month in RANGE: day d, cents v (or per-month value list). "
        "X rows are extra txs: DD name cents cat_code [k|w] [$]. "
        "Dollars=cents/100. *Do not* count CRON rows twice — they are not in X. "
        "SUB metadata for annual cost only (already expanded into CRON)."
    )
    return _pack(
        "dsl_cron",
        "novel",
        "\n".join(cron_lines),
        "Template extraction: salary/rent/netflix/gym cron + exception ledger.",
        decode,
        True,
    )


@fn_codec(
    "dsl_cat_idx",
    "novel",
    "Category-major inverted index: `shopping: -12.3*3, -88`. Lossy on dates/names.",
    reversible=False,
)
def dsl_cat_idx(bundle: Bundle) -> CodecResult:
    by_cat: dict[str, list[float]] = defaultdict(list)
    for tx in bundle.transactions:
        by_cat[tx.category or "uncategorized"].append(tx.value)
    lines = [
        "+income -expense. *k = amount repeats k times. Count *k as k txs.",
        _sub_line(bundle),
    ]
    for cat in sorted(by_cat):
        lines.append(f"{cat}: {_rle(by_cat[cat], sep=', ')}")
    decode = (
        "Category inverted index. After each category name, signed dollar amounts. "
        "a*k means amount a appears k times. Dates/names omitted. "
        "total_expense = -sum of negatives; top spend category = largest -sum. "
        "SUB already included in the lists; annual = sum(-v*12) for SUB v<0. "
        "No month keys — do not use this encoding for forecasts."
    )
    return _pack(
        "dsl_cat_idx",
        "novel",
        "\n".join(lines),
        "Category-major RLE amounts (user style). Drops dates — forecasts need dsl_cat_month.",
        decode,
        False,
    )


@fn_codec(
    "dsl_cat_month",
    "novel",
    "Category-major monthly buckets: `shopping / 25-03 -12.3*3 -88`. Task-complete.",
    reversible=False,
)
def dsl_cat_month(bundle: Bundle) -> CodecResult:
    nested: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for tx in bundle.transactions:
        nested[tx.category or "uncategorized"][tx.occurred_on[:7]].append(tx.value)
    lines = [
        "+income -expense. YY-MM then amounts. *k = repeat. Count every amount.",
        _sub_line(bundle),
    ]
    for cat in sorted(nested):
        lines.append(f"{cat}:")
        for month, vals in nested[cat].items():
            lines.append(f"{month[2:]} {_rle(vals)}")
    decode = (
        "Category-major ledger. Heading = category. Lines = YY-MM then signed dollars. "
        "*k repeats. n_transactions = count of amounts (*k counts as k). "
        "Spend of a category = -sum of its negatives. "
        "Month spend/income = sum across categories in that YY-MM. "
        "Last 3 month keys in calendar order. "
        "SUB is metadata (rows already listed); annual sub cost = sum(-v*12) for SUB v<0."
    )
    return _pack(
        "dsl_cat_month",
        "novel",
        "\n".join(lines),
        "Category-major monthly inverted index with RLE. Best task-complete DSL.",
        decode,
        False,
    )


@fn_codec(
    "dsl_yc1",
    "novel",
    "Drop year, cents, 1-char cat/account/ccy, keep spaces, monthly buckets.",
)
def dsl_yc1(bundle: Bundle) -> CodecResult:
    legend = [
        "V=cents/100. Yxx then MM. Rows: DD name cents cat [k|w] [$]",
        "default a=m ccy=e. k=credit w=savings $=usd",
        _legend_cats(),
        _sub_line(bundle, as_cents=True),
    ]

    def row(tx: Transaction) -> str:
        cat = CAT_CODE.get(tx.category or "", "?")
        return f"{tx.occurred_on[8:]} {tx.name} {_cents(tx.value)} {cat}{_sparse_suffix(tx)}"

    parts = legend + _year_then_month_rows(_months(bundle.transactions), row)
    decode = (
        "Monthly spaced ledger. Y25 then MM. Row: day name cents cat_code [account/ccy if not m/e]. "
        "Dollars=cents/100. C legend maps 1-char category. SUB already in rows; "
        "annual = sum(-v*12) for SUB v<0 (convert cents)."
    )
    return _pack(
        "dsl_yc1",
        "novel",
        "\n".join(parts),
        "Structural cousin of line_natural: year-dropped months, cents, 1-char tags, spaces kept.",
        decode,
        True,
    )
