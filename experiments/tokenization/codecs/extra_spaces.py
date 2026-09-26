"""Keep ordinary ASCII spaces; win tokens by shortening fields and grouping repeats.

Hard finding this module respects: on GPT-5 / o200k_base, deleting spaces or
replacing them with | tab comma · _ / ▁ / unit-sep *increases* tokens. Sticky
glue (`-50eurhahah`) and extra spaces around amounts also lose. New codecs
keep spaces unless a measurement shows a win.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date

from experiments.tokenization.bundle import Bundle, Transaction
from experiments.tokenization.codecs.base import fn_codec

EPOCH = date(2025, 1, 1)

CAT3 = {
    "rent": "rnt",
    "groceries": "gro",
    "restaurants": "rst",
    "transport": "trn",
    "salary": "sal",
    "freelance": "frl",
    "subscriptions": "sub",
    "entertainment": "ent",
    "healthcare": "hlt",
    "utilities": "utl",
    "shopping": "shp",
    "travel": "trv",
    "coffee": "cof",
    "insurance": "ins",
    "education": "edu",
    "gifts": "gft",
}
ACC1 = {"main": "m", "credit": "c", "savings": "s"}

USER_EXAMPLES = """user-examples (tiny sample, not the ledger):
before: -50eur hahah
after-sticky: -50eurhahah
before: -50eur heh
after-split: -50 eur heh
keep-spaces: -50 eur hahah
"""


def _cents(value: float) -> int:
    return int(round(value * 100))


def _yymmdd(tx: Transaction) -> str:
    return tx.occurred_on.replace("-", "")[2:]


def _daynum(tx: Transaction) -> int:
    return (date.fromisoformat(tx.occurred_on) - EPOCH).days


def _cat(tx: Transaction) -> str:
    return tx.category or "-"


def _extras(tx: Transaction, *, letter_account: bool = False) -> list[str]:
    """Non-default currency/account. Default is eur + main."""
    out: list[str] = []
    if tx.currency != "eur":
        out.append(tx.currency)
    if tx.account != "main":
        out.append(ACC1[tx.account] if letter_account else tx.account)
    return out


def _join(parts: list[str]) -> str:
    return "\n".join(parts)


def _group_cat_name(bundle: Bundle, date_mode: str) -> str:
    tree: dict[str, dict[str, list[Transaction]]] = defaultdict(lambda: defaultdict(list))
    for tx in bundle.transactions:
        tree[_cat(tx)][tx.name].append(tx)
    if date_mode == "daynum":
        legend = "D=days since 2025-01-01 V=cents default ccy=eur account=main"
    else:
        legend = "dates=YYMMDD V=cents default ccy=eur account=main"
    parts = [legend]
    for cat, names in sorted(tree.items(), key=lambda item: -sum(len(v) for v in item[1].values())):
        parts.append(f" {cat}")
        for name, rows in sorted(names.items(), key=lambda item: -len(item[1])):
            parts.append(f" {name}")
            for tx in rows:
                if date_mode == "daynum":
                    d = str(_daynum(tx))
                else:
                    d = _yymmdd(tx)
                bits = [d, str(_cents(tx.value)), *_extras(tx)]
                parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "spaced_yymmdd",
    "spaces",
    "Keep spaces and all fields; only compress ISO dates to YYMMDD.",
)
def spaced_yymmdd(bundle: Bundle) -> str:
    return _join(
        [
            f"{_yymmdd(tx)} {tx.name} {tx.value} {tx.currency} {tx.account} {_cat(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "spaced_cents",
    "spaces",
    "Keep spaces and ISO dates; amounts as integer cents.",
)
def spaced_cents(bundle: Bundle) -> str:
    return _join(
        [
            f"{tx.occurred_on} {tx.name} {_cents(tx.value)} {tx.currency} {tx.account} {_cat(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "spaced_yymmdd_cents",
    "spaces",
    "Keep spaces; YYMMDD dates + integer cents; full account/category words. Readable flat win.",
)
def spaced_yymmdd_cents(bundle: Bundle) -> str:
    return _join(
        [
            f"{_yymmdd(tx)} {tx.name} {_cents(tx.value)} {tx.currency} {tx.account} {_cat(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "spaced_short_codes",
    "spaces",
    "Keep spaces; YYMMDD + cents + 1-letter account + 3-letter category + 1-letter ccy. Legend included.",
)
def spaced_short_codes(bundle: Bundle) -> str:
    legend = (
        "A=m main,c credit,s savings Y=e eur,u usd dates=YYMMDD V=cents "
        "C=" + ",".join(f"{code}={name}" for name, code in CAT3.items())
    )
    rows = [
        f"{_yymmdd(tx)} {tx.name} {_cents(tx.value)} {tx.currency[0]} {ACC1[tx.account]} {CAT3.get(_cat(tx), 'x')}"
        for tx in bundle.transactions
    ]
    return _join([legend, *rows])


@fn_codec(
    "amount_first_spaced",
    "spaces",
    "Field reorder: cents, YYMMDD, name, ccy, account, category. Spaces kept.",
)
def amount_first_spaced(bundle: Bundle) -> str:
    return _join(
        [
            f"{_cents(tx.value)} {_yymmdd(tx)} {tx.name} {tx.currency} {tx.account} {_cat(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "date_last_spaced",
    "spaces",
    "Field reorder: name first, YYMMDD last. Hurts BPE because names lose the leading-space merge.",
)
def date_last_spaced(bundle: Bundle) -> str:
    return _join(
        [
            f"{tx.name} {_cents(tx.value)} {tx.currency} {tx.account} {_cat(tx)} {_yymmdd(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "omit_default_eur_main",
    "spaces",
    "Flat lines: YYMMDD name cents category; list ccy/account only when not eur/main.",
)
def omit_default_eur_main(bundle: Bundle) -> str:
    parts = ["dates=YYMMDD V=cents default ccy=eur account=main"]
    for tx in bundle.transactions:
        bits = [_yymmdd(tx), tx.name, str(_cents(tx.value)), _cat(tx), *_extras(tx)]
        parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "group_by_category_spaced",
    "spaces",
    "Group by category so the label is written once; rows keep spaces (YYMMDD name cents).",
)
def group_by_category_spaced(bundle: Bundle) -> str:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[_cat(tx)].append(tx)
    parts = ["dates=YYMMDD V=cents default ccy=eur account=main"]
    for cat, rows in sorted(grouped.items(), key=lambda item: -len(item[1])):
        parts.append(f" {cat}")
        for tx in rows:
            bits = [_yymmdd(tx), tx.name, str(_cents(tx.value)), *_extras(tx)]
            parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "group_by_day_spaced",
    "spaces",
    "Group by day (YYMMDD header) so the date is written once; rows keep spaces.",
)
def group_by_day_spaced(bundle: Bundle) -> str:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[tx.occurred_on].append(tx)
    parts = ["V=cents default ccy=eur account=main dates=YYMMDD headers"]
    for day, rows in grouped.items():
        parts.append(_yymmdd(rows[0]))
        for tx in rows:
            bits = [tx.name, str(_cents(tx.value)), _cat(tx), *_extras(tx)]
            parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "group_by_month_spaced",
    "spaces",
    "Group by YYYY-MM; rows are DD name cents category. Reversible, spaces kept.",
)
def group_by_month_spaced(bundle: Bundle) -> str:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[tx.occurred_on[:7]].append(tx)
    parts = ["V=cents default ccy=eur account=main"]
    for month, rows in grouped.items():
        parts.append(month)
        for tx in rows:
            bits = [tx.occurred_on[8:], tx.name, str(_cents(tx.value)), _cat(tx), *_extras(tx)]
            parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "group_by_name_yymmdd",
    "spaces",
    "Group by merchant name (50 unique); category on the header; YYMMDD cents rows.",
)
def group_by_name_yymmdd(bundle: Bundle) -> str:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[tx.name].append(tx)
    parts = ["dates=YYMMDD V=cents default ccy=eur account=main"]
    for name, rows in sorted(grouped.items(), key=lambda item: -len(item[1])):
        parts.append(f" {name} {rows[0].category}")
        for tx in rows:
            bits = [_yymmdd(tx), str(_cents(tx.value)), *_extras(tx)]
            parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "group_cat_name_yymmdd",
    "spaces",
    "Category then merchant groups; YYMMDD + cents; default eur/main. Human-readable grouped win.",
)
def group_cat_name_yymmdd(bundle: Bundle) -> str:
    return _group_cat_name(bundle, "yymmdd")


@fn_codec(
    "group_cat_name_daynum",
    "spaces",
    "Category then merchant groups; D=days since 2025-01-01; V=cents; default eur/main. Token winner.",
)
def group_cat_name_daynum(bundle: Bundle) -> str:
    return _group_cat_name(bundle, "daynum")


@fn_codec(
    "delta_days_by_name",
    "spaces",
    "Merchant groups; first date is days since 2025-01-01, later rows are day deltas; cents.",
)
def delta_days_by_name(bundle: Bundle) -> str:
    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[tx.name].append(tx)
    parts = ["D0=days since 2025-01-01 then day deltas; V=cents default eur/main"]
    for name, rows in sorted(grouped.items(), key=lambda item: -len(item[1])):
        rows = sorted(rows, key=lambda tx: (tx.occurred_on, tx.id))
        parts.append(f" {name} {rows[0].category}")
        prev: int | None = None
        for tx in rows:
            d = _daynum(tx)
            delta = d if prev is None else d - prev
            prev = d
            bits = [str(delta), str(_cents(tx.value)), *_extras(tx)]
            parts.append(" ".join(bits))
    return _join(parts)


@fn_codec(
    "space_before_minus",
    "spaces",
    "Amount-first with a leading space so BPE sees ' -50' rather than start-of-line '-50'.",
)
def space_before_minus(bundle: Bundle) -> str:
    return _join(
        [
            f" {_cents(tx.value)} {_yymmdd(tx)} {tx.name} {tx.currency} {tx.account} {_cat(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "two_spaces_date_amount",
    "spaces",
    "YYMMDD + cents + full words, but two ASCII spaces only between date and name (BPE boundary probe).",
)
def two_spaces_date_amount(bundle: Bundle) -> str:
    return _join(
        [
            f"{_yymmdd(tx)}  {tx.name} {_cents(tx.value)} {tx.currency} {tx.account} {_cat(tx)}"
            for tx in bundle.transactions
        ]
    )


@fn_codec(
    "nbsp_field_sep",
    "symbols",
    "Same payload as spaced_yymmdd_cents but ASCII spaces replaced by NBSP U+00A0.",
)
def nbsp_field_sep(bundle: Bundle) -> str:
    text = spaced_yymmdd_cents.encode(bundle).text or ""
    return text.replace(" ", "\u00a0")


@fn_codec(
    "thin_space_field_sep",
    "symbols",
    "Same payload as spaced_yymmdd_cents but ASCII spaces replaced by thin space U+2009.",
)
def thin_space_field_sep(bundle: Bundle) -> str:
    text = spaced_yymmdd_cents.encode(bundle).text or ""
    return text.replace(" ", "\u2009")


@fn_codec(
    "user_examples_tiny",
    "spaces",
    "Exactly the sticky/split user examples plus three real ledger rows. Demo only, not a full encoding.",
    reversible=False,
)
def user_examples_tiny(bundle: Bundle) -> str:
    sample = bundle.transactions[:3]
    rows = [
        f"{tx.occurred_on} {tx.name} {tx.value} {tx.currency} {tx.account} {_cat(tx)}"
        for tx in sample
    ]
    return USER_EXAMPLES + "tiny-ledger:\n" + _join(rows)


@fn_codec(
    "user_examples_plus_win",
    "spaces",
    "User sticky/split examples, then the winning group_cat_name_daynum ledger.",
)
def user_examples_plus_win(bundle: Bundle) -> str:
    return USER_EXAMPLES + "ledger:\n" + _group_cat_name(bundle, "daynum")
