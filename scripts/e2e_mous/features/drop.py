"""Isolated `mous drop` of the temp database (never production, never docker)."""

from __future__ import annotations

from pathlib import Path

from e2e_mous.harness import PROD_DB, expect, isolated_database, mous_cli


def run(env: dict[str, str], directory: Path) -> None:
    db = isolated_database(directory)
    dropped = mous_cli(env, ["drop"])
    expect(dropped.returncode == 0, f"drop failed: {dropped.stderr}")
    expect(not db.is_file(), f"drop left {db}")
    expect(db != PROD_DB.resolve(), "drop targeted production")
