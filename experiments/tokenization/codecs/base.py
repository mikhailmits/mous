"""Codec registry. Subagents add modules that call `register()` at import time."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Iterable, Protocol

from experiments.tokenization.bundle import Bundle


@dataclass
class CodecResult:
    name: str
    family: str
    text: str | None = None
    image_paths: list[str] = field(default_factory=list)
    decode_instructions: str = ""
    reversible: bool = True
    notes: str = ""
    extras: dict[str, Any] = field(default_factory=dict)

    @property
    def token_payload(self) -> str:
        return self.text or ""


class Codec(Protocol):
    name: str
    family: str

    def encode(self, bundle: Bundle) -> CodecResult: ...


_REGISTRY: dict[str, Codec] = {}


def register(codec: Codec) -> Codec:
    _REGISTRY[codec.name] = codec
    return codec


def get(name: str) -> Codec:
    return _REGISTRY[name]


def all_codecs() -> list[Codec]:
    return [codec for _, codec in sorted(_REGISTRY.items())]


def by_family(family: str) -> list[Codec]:
    return [codec for codec in all_codecs() if codec.family == family]


def load_all() -> None:
    import importlib
    import pkgutil

    from experiments.tokenization import codecs as pkg

    for module in pkgutil.iter_modules(pkg.__path__):
        if module.name.startswith("_"):
            continue
        importlib.import_module(f"experiments.tokenization.codecs.{module.name}")


def encode_all(bundle: Bundle, families: Iterable[str] | None = None) -> list[CodecResult]:
    load_all()
    wanted = set(families) if families else None
    out: list[CodecResult] = []
    for codec in all_codecs():
        if wanted is not None and codec.family not in wanted:
            continue
        out.append(codec.encode(bundle))
    return out


def fn_codec(name: str, family: str, notes: str = "", reversible: bool = True) -> Callable:
    def deco(func: Callable[[Bundle], str | CodecResult]) -> Codec:
        class _Fn:
            def __init__(self) -> None:
                self.name = name
                self.family = family

            def encode(self, bundle: Bundle) -> CodecResult:
                raw = func(bundle)
                if isinstance(raw, CodecResult):
                    return raw
                return CodecResult(
                    name=name,
                    family=family,
                    text=raw,
                    notes=notes,
                    reversible=reversible,
                    decode_instructions=notes,
                )

        codec = _Fn()
        register(codec)
        return codec

    return deco
