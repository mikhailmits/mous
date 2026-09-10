from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_MACOS_PACKAGE = _REPO_ROOT / "macos" / "Mous"
_CLT_DEVELOPER_DIR = Path("/Library/Developer/CommandLineTools")
_XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")


def main() -> None:
    parser = argparse.ArgumentParser(prog="mous")
    sub = parser.add_subparsers(dest="command")
    serve = sub.add_parser("serve", help="Run the HTTP API")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8000)
    sub.add_parser("dev", help="Build and run the macOS popup (debug)")
    args = parser.parse_args()
    if args.command == "serve":
        from mous.api.app import run

        run(host=args.host, port=args.port)
        return
    if args.command == "dev":
        run_macos_dev()
        return
    parser.print_help()


def run_macos_dev() -> None:
    """Build and run the macOS popup against the local API (debug)."""
    if not _MACOS_PACKAGE.is_dir():
        print(f"missing Swift package at {_MACOS_PACKAGE}", file=sys.stderr)
        raise SystemExit(1)
    swift = shutil.which("swift")
    if swift is None:
        print("swift is not on PATH", file=sys.stderr)
        raise SystemExit(1)
    env = os.environ.copy()
    if "DEVELOPER_DIR" not in env and _CLT_DEVELOPER_DIR.is_dir() and not _XCODE_DEVELOPER_DIR.is_dir():
        env["DEVELOPER_DIR"] = str(_CLT_DEVELOPER_DIR)
    raise SystemExit(
        subprocess.call(
            [
                swift,
                "run",
                "--package-path",
                str(_MACOS_PACKAGE),
                "--configuration",
                "debug",
                "Mous",
            ],
            env=env,
        )
    )
