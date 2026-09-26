"""(a) Space deletion, insertion, and sticky-amount experiments."""

from __future__ import annotations

import json

from experiments.tokenization.bundle import Bundle
from experiments.tokenization.codecs.base import fn_codec


def _rows(bundle: Bundle) -> list[dict]:
    return [
        {
            "d": tx.occurred_on,
            "n": tx.name,
            "v": tx.value,
            "ccy": tx.currency,
            "a": tx.account,
            "c": tx.category,
        }
        for tx in bundle.transactions
    ]


@fn_codec("json_pretty", "baseline", "Indented JSON. Wasteful control, not an optimization.")
def json_pretty(bundle: Bundle) -> str:
    return json.dumps(_rows(bundle), indent=2)


@fn_codec("json_compact", "baseline", "Minified JSON with default separators.")
def json_compact(bundle: Bundle) -> str:
    return json.dumps(_rows(bundle), separators=(",", ":"))


@fn_codec("line_natural", "spaces", "One human line: 2026-01-02 groceries -23.10 eur main food")
def line_natural(bundle: Bundle) -> str:
    lines = [
        f"{tx.occurred_on} {tx.name} {tx.value} {tx.currency} {tx.account} {tx.category or '-'}"
        for tx in bundle.transactions
    ]
    return "\n".join(lines)


@fn_codec(
    "sticky_amount_no_space",
    "spaces",
    "User example: before '-50eur hahah' after '-50eurhahah'. Amount glued to currency and name.",
)
def sticky_amount_no_space(bundle: Bundle) -> str:
    lines = []
    for tx in bundle.transactions:
        name = tx.name.replace(" ", "")
        lines.append(f"{tx.occurred_on}{tx.value}{tx.currency}{name}{tx.account}{tx.category or ''}")
    return "\n".join(lines)


@fn_codec(
    "split_amount_spaces",
    "spaces",
    "User example: before '-50eur heh' after '-50 eur heh'. Split sign/amount/currency/name.",
)
def split_amount_spaces(bundle: Bundle) -> str:
    lines = []
    for tx in bundle.transactions:
        sign = "-" if tx.value < 0 else "+"
        mag = f"{abs(tx.value):.2f}"
        lines.append(
            f"{tx.occurred_on} {sign} {mag} {tx.currency} {tx.name} {tx.account} {tx.category or '-'}"
        )
    return "\n".join(lines)


@fn_codec("double_spaces", "spaces", "Every separator is two spaces.")
def double_spaces(bundle: Bundle) -> str:
    lines = [
        f"{tx.occurred_on}  {tx.name}  {tx.value}  {tx.currency}  {tx.account}  {tx.category or '-'}"
        for tx in bundle.transactions
    ]
    return "\n".join(lines)


@fn_codec("no_spaces_at_all", "spaces", "Remove every ASCII space from the natural line format.")
def no_spaces_at_all(bundle: Bundle) -> str:
    return line_natural.encode(bundle).text.replace(" ", "")  # type: ignore[union-attr]


@fn_codec("newline_fields", "spaces", "Each field on its own line; blank line between records.")
def newline_fields(bundle: Bundle) -> str:
    chunks = []
    for tx in bundle.transactions:
        chunks.append(
            "\n".join(
                [
                    tx.occurred_on,
                    tx.name,
                    str(tx.value),
                    tx.currency,
                    tx.account,
                    tx.category or "-",
                    "",
                ]
            )
        )
    return "\n".join(chunks)
