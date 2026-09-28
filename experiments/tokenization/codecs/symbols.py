"""(b) Replace spaces with other symbols."""

from __future__ import annotations

from experiments.tokenization.bundle import Bundle
from experiments.tokenization.codecs.base import fn_codec
from experiments.tokenization.codecs.spaces import line_natural


def _swap(bundle: Bundle, old: str, new: str) -> str:
    return line_natural.encode(bundle).text.replace(old, new)  # type: ignore[union-attr]


@fn_codec("space_to_pipe", "symbols", "Spaces -> | which is often a single token.")
def space_to_pipe(bundle: Bundle) -> str:
    return _swap(bundle, " ", "|")


@fn_codec("space_to_tab", "symbols", "Spaces -> tab.")
def space_to_tab(bundle: Bundle) -> str:
    return _swap(bundle, " ", "\t")


@fn_codec("space_to_comma", "symbols", "Spaces -> comma (CSV-ish without quoting).")
def space_to_comma(bundle: Bundle) -> str:
    return _swap(bundle, " ", ",")


@fn_codec("space_to_unit_sep", "symbols", "Spaces -> ASCII unit separator 0x1f.")
def space_to_unit_sep(bundle: Bundle) -> str:
    return _swap(bundle, " ", "\x1f")


@fn_codec("space_to_middle_dot", "symbols", "Spaces -> · (U+00B7).")
def space_to_middle_dot(bundle: Bundle) -> str:
    return _swap(bundle, " ", "·")


@fn_codec("space_to_underscore", "symbols", "Spaces -> _")
def space_to_underscore(bundle: Bundle) -> str:
    return _swap(bundle, " ", "_")


@fn_codec("space_to_sentencepiece_block", "symbols", "Spaces -> ▁ (U+2581) used by SentencePiece.")
def space_to_sentencepiece_block(bundle: Bundle) -> str:
    return _swap(bundle, " ", "▁")


@fn_codec("space_to_slash", "symbols", "Spaces -> /")
def space_to_slash(bundle: Bundle) -> str:
    return _swap(bundle, " ", "/")
