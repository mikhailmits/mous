"""Local token-count leaderboard across codecs × tokenizers."""

from __future__ import annotations

import json
from pathlib import Path

from experiments.tokenization.bundle import load_bundle
from experiments.tokenization.codecs.base import encode_all
from experiments.tokenization.paths import RESULTS
from experiments.tokenization.tokenizers import load_tokenizers


def run(families: list[str] | None = None) -> dict:
    bundle = load_bundle()
    tokenizers = load_tokenizers()
    print(f"tokenizers={len(tokenizers)} txs={len(bundle.transactions)}")
    encoded = encode_all(bundle, families=families)
    rows = []
    for result in encoded:
        payload = result.token_payload
        counts = {}
        for tok in tokenizers:
            try:
                counts[tok.name] = tok.encode_len(payload)
            except Exception as exc:
                counts[tok.name] = None
                print(f"count fail {result.name} {tok.name}: {exc}")
        gpt5 = counts.get("openai-gpt-5") or counts.get("openai-o200k_base") or 0
        row = {
            "codec": result.name,
            "family": result.family,
            "chars": len(payload),
            "bytes": len(payload.encode("utf-8")),
            "reversible": result.reversible,
            "notes": result.notes,
            "image_paths": result.image_paths,
            "extras": result.extras,
            "tokens": counts,
            "gpt5_tokens": gpt5,
        }
        rows.append(row)
        print(f"{result.name:28} family={result.family:10} chars={len(payload):7} gpt5={gpt5}")

    baseline = next((r for r in rows if r["codec"] == "json_pretty"), None)
    base_gpt5 = baseline["gpt5_tokens"] if baseline and baseline["gpt5_tokens"] else None
    for row in rows:
        if base_gpt5:
            row["gpt5_vs_pretty_pct"] = round(100.0 * row["gpt5_tokens"] / base_gpt5, 2)
        else:
            row["gpt5_vs_pretty_pct"] = None

    rows.sort(key=lambda r: (r["gpt5_tokens"] is None, r["gpt5_tokens"] or 10**12))
    payload = {
        "n_transactions": len(bundle.transactions),
        "n_codecs": len(rows),
        "tokenizers": [
            {"name": t.name, "vendor": t.vendor, "notes": t.notes} for t in tokenizers
        ],
        "rows": rows,
    }
    out = RESULTS / "token_counts.json"
    out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    _write_markdown(payload)
    print(f"wrote {out}")
    return payload


def _write_markdown(payload: dict) -> None:
    lines = [
        "# Token count leaderboard (GPT-5 / o200k_base)",
        "",
        f"Transactions: **{payload['n_transactions']}**. Lower is cheaper context.",
        "",
        "| rank | codec | family | GPT-5 tokens | vs pretty JSON | chars | reversible |",
        "| --- | --- | --- | ---: | ---: | ---: | --- |",
    ]
    for i, row in enumerate(payload["rows"], start=1):
        vs = f"{row['gpt5_vs_pretty_pct']}%" if row["gpt5_vs_pretty_pct"] is not None else "—"
        lines.append(
            f"| {i} | `{row['codec']}` | {row['family']} | {row['gpt5_tokens']} | {vs} | {row['chars']} | {row['reversible']} |"
        )
    lines += ["", "## Tokenizer inventory", ""]
    for tok in payload["tokenizers"]:
        lines.append(f"- `{tok['name']}` — {tok['vendor']}. {tok['notes']}")
    path = RESULTS / "leaderboard.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {path}")


if __name__ == "__main__":
    run()
