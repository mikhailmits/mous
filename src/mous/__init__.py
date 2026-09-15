from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from mous.config.utils import (
    api_host,
    api_port,
    database_path,
    ensure_config,
    is_dev_environment,
    source_repo_root,
)

_DEV_DB_SIDECARS = ("-journal", "-wal", "-shm")
_CLT_DEVELOPER_DIR = Path("/Library/Developer/CommandLineTools")
_XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")


def main() -> None:
    ensure_config()
    if is_dev_environment():
        DevCLI.start()
        return
    if len(sys.argv) <= 1 and not sys.stdin.isatty():
        from mous.api.app import run

        run(host=api_host(), port=api_port())
        return
    PublicCLI.start()


def run_macos_dev() -> None:
    DevCLI().run_dev()


def _remove_sqlite(db: Path) -> list[Path]:
    removed: list[Path] = []
    for path in (db, *(db.parent / f"{db.name}{suffix}" for suffix in _DEV_DB_SIDECARS)):
        if path.is_file():
            path.unlink()
            removed.append(path)
    return removed


class PublicCLI:
    """Shipped .app CLI: read-only wrappers around the local API."""

    @classmethod
    def start(cls) -> None:
        cls().run()

    def add_commands(self, sub: argparse._SubParsersAction) -> None:
        summary = sub.add_parser(
            "summary",
            help="Period report: n, in, out, saved, top, runway",
        )
        summary.add_argument(
            "period",
            nargs="*",
            metavar="PERIOD",
            help="How far back (default: config report_period). Examples: month, 1 day, 2 weeks, 1 year",
        )

    def handle(self, args: argparse.Namespace) -> bool:
        if args.command == "summary":
            from mous.services.api import APIUnavailable
            from mous.services.summary import PeriodParseError

            period = " ".join(args.period) if args.period else None
            try:
                self.summary(period)
            except PeriodParseError as exc:
                print(exc, file=sys.stderr)
                raise SystemExit(2) from exc
            except APIUnavailable as exc:
                print(exc, file=sys.stderr)
                raise SystemExit(1) from exc
            return True
        return False

    def run(self) -> None:
        parser = argparse.ArgumentParser(
            prog="mous",
            description="This is a simple wrapper around API that covers basic read only operations",
        )
        sub = parser.add_subparsers(dest="command")
        self.add_commands(sub)
        args = parser.parse_args()
        if self.handle(args):
            return
        parser.print_help()

    def summary(self, period: str | None = None) -> None:
        from mous.services.summary import build_summary, format_summary

        print(format_summary(build_summary(period)), end="")


class DevCLI(PublicCLI):
    """Repo checkout: public CLI plus serve, macOS debug popup, drop local/docker DBs."""

    @classmethod
    def start(cls) -> None:
        cls().run()

    def __init__(self) -> None:
        root = source_repo_root()
        if root is None:
            print("not a mous source checkout", file=sys.stderr)
            raise SystemExit(1)
        self.repo_root = root
        self.macos_package = root / "macos" / "Mous"
        self.compose_file = root / "docker-compose.yml"

    def run(self) -> None:
        parser = argparse.ArgumentParser(prog="mous")
        sub = parser.add_subparsers(dest="command")
        self.add_commands(sub)
        serve = sub.add_parser("serve", help="Run the HTTP API")
        serve.add_argument("--host", default=api_host())
        serve.add_argument("--port", type=int, default=api_port())
        sub.add_parser("dev", help="Build and run the macOS popup (debug)")
        drop = sub.add_parser("drop", help="Delete a database")
        drop_sub = drop.add_subparsers(dest="target")
        drop_sub.add_parser("docker", help="Reset the Compose SQLite volume and restart the API")
        args = parser.parse_args()
        if args.command == "serve":
            self.serve(args.host, args.port)
            return
        if args.command == "dev":
            self.run_dev()
            return
        if args.command == "drop":
            if args.target == "docker":
                self.drop_docker()
            else:
                self.drop_local()
            return
        if self.handle(args):
            return
        parser.print_help()

    def serve(self, host: str, port: int) -> None:
        from mous.api.app import run

        run(host=host, port=port)

    def drop_local(self) -> None:
        db = database_path()
        removed = _remove_sqlite(db)
        if removed:
            for path in removed:
                print(f"removed {path}")
            return
        print(f"no database at {db}")

    def drop_docker(self) -> None:
        if shutil.which("docker") is None:
            print("docker is not on PATH", file=sys.stderr)
            raise SystemExit(1)
        if not self.compose_file.is_file():
            print(f"missing {self.compose_file}", file=sys.stderr)
            raise SystemExit(1)
        if self._docker_compose("down", "-v") != 0:
            raise SystemExit(1)
        raise SystemExit(self._docker_compose("up", "-d"))

    def _docker_compose(self, *args: str) -> int:
        cmd = ["docker", "compose", "-f", str(self.compose_file), *args]
        return subprocess.call(cmd, cwd=self.repo_root)

    def run_dev(self) -> None:
        """Build and run the macOS popup against the local API (debug)."""
        if not self.macos_package.is_dir():
            print(f"missing Swift package at {self.macos_package}", file=sys.stderr)
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
                    str(self.macos_package),
                    "--configuration",
                    "debug",
                    "Mous",
                ],
                env=env,
            )
        )


if __name__ == "__main__":
    main()
