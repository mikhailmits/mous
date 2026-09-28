"""CLI for the tokenization lab."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
if str(ROOT / "src") not in sys.path:
    sys.path.insert(0, str(ROOT / "src"))


def cmd_seed(args: argparse.Namespace) -> None:
    from experiments.tokenization.seed import seed
    import asyncio

    n = asyncio.run(seed(force=args.force))
    print(f"good_count={n}")


def cmd_export(_: argparse.Namespace) -> None:
    from experiments.tokenization.bundle import fetch_bundle, save_bundle
    from experiments.tokenization.gold import compute_gold, save_gold

    base = os.environ.get("MOUS_API_BASE", "http://127.0.0.1:8000")
    bundle = fetch_bundle(base)
    save_bundle(bundle)
    save_gold(compute_gold(bundle))
    print(json.dumps({"transactions": len(bundle.transactions), "subscriptions": len(bundle.subscriptions)}))


def cmd_tokens(args: argparse.Namespace) -> None:
    from experiments.tokenization.evaluate_tokens import run

    families = args.family.split(",") if args.family else None
    run(families=families)


def cmd_llm(args: argparse.Namespace) -> None:
    from experiments.tokenization.evaluate_llm import run

    codecs = args.codecs.split(",") if args.codecs else None
    run(model_limit=args.models, codec_names=codecs)


def cmd_serve(args: argparse.Namespace) -> None:
    from mous.api.app import run

    run(host=args.host, port=args.port)


def main() -> None:
    parser = argparse.ArgumentParser(prog="tokenization-lab")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_seed = sub.add_parser("seed")
    p_seed.add_argument("--force", action="store_true")
    p_seed.set_defaults(func=cmd_seed)
    p_export = sub.add_parser("export")
    p_export.set_defaults(func=cmd_export)
    p_tokens = sub.add_parser("tokens")
    p_tokens.add_argument("--family", default="")
    p_tokens.set_defaults(func=cmd_tokens)
    p_llm = sub.add_parser("llm")
    p_llm.add_argument("--models", type=int, default=2)
    p_llm.add_argument("--codecs", default="")
    p_llm.set_defaults(func=cmd_llm)
    p_serve = sub.add_parser("serve")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8000)
    p_serve.set_defaults(func=cmd_serve)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
