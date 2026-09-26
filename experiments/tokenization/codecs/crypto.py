"""(d) Encryption / encoding layers. Most destroy LLM readability; still counted."""

from __future__ import annotations

import base64
import gzip
import hashlib
import zlib

from experiments.tokenization.bundle import Bundle
from experiments.tokenization.codecs.base import fn_codec
from experiments.tokenization.codecs.spaces import line_natural, json_compact


def _plain(bundle: Bundle) -> str:
    return line_natural.encode(bundle).text or ""


@fn_codec("b64", "crypto", "Base64 of the natural ledger. Usually expands tokens.", reversible=True)
def b64(bundle: Bundle) -> str:
    return base64.b64encode(_plain(bundle).encode()).decode()


@fn_codec("hex", "crypto", "Hex of the natural ledger. Very expensive.", reversible=True)
def hex_codec(bundle: Bundle) -> str:
    return _plain(bundle).encode().hex()


@fn_codec("gzip_b64", "crypto", "gzip then base64. Fewer bytes, often more tokens.", reversible=True)
def gzip_b64(bundle: Bundle) -> str:
    return base64.b64encode(gzip.compress(_plain(bundle).encode(), compresslevel=9)).decode()


@fn_codec("zlib_b85", "crypto", "zlib then ascii85.", reversible=True)
def zlib_b85(bundle: Bundle) -> str:
    return base64.b85encode(zlib.compress(_plain(bundle).encode(), 9)).decode()


@fn_codec("rot13_names", "crypto", "ROT13 on names/categories only; numbers stay intact.", reversible=True)
def rot13_names(bundle: Bundle) -> str:
    def rot13(text: str) -> str:
        out = []
        for ch in text:
            if "a" <= ch <= "z":
                out.append(chr((ord(ch) - 97 + 13) % 26 + 97))
            elif "A" <= ch <= "Z":
                out.append(chr((ord(ch) - 65 + 13) % 26 + 65))
            else:
                out.append(ch)
        return "".join(out)

    lines = [
        f"{tx.occurred_on} {rot13(tx.name)} {tx.value} {tx.currency} {tx.account} {rot13(tx.category or '-')}"
        for tx in bundle.transactions
    ]
    return "\n".join(lines)


@fn_codec("xor_hex", "crypto", "XOR with repeating key then hex. Opaque to models.", reversible=True)
def xor_hex(bundle: Bundle) -> str:
    key = b"mous-token-lab"
    data = _plain(bundle).encode()
    xored = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
    return xored.hex()


@fn_codec(
    "sha256_rows",
    "crypto",
    "Irreversible row hashes. Token-cheap, task-useless. Control for quality floor.",
    reversible=False,
)
def sha256_rows(bundle: Bundle) -> str:
    lines = []
    for tx in bundle.transactions:
        payload = f"{tx.occurred_on}|{tx.name}|{tx.value}|{tx.currency}|{tx.account}|{tx.category}"
        lines.append(hashlib.sha256(payload.encode()).hexdigest()[:16])
    return "\n".join(lines)


@fn_codec("json_gzip_b64", "crypto", "Minified JSON gzip+base64.")
def json_gzip_b64(bundle: Bundle) -> str:
    raw = json_compact.encode(bundle).text or ""
    return base64.b64encode(gzip.compress(raw.encode(), 9)).decode()
