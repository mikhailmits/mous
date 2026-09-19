"""API 'today' follows the local civil date, not UTC-only."""

from __future__ import annotations

from datetime import date

from e2e_mous.harness import expect


def run() -> None:
    from mous.api.time import utc_today

    expect(utc_today() == date.today(), "api today is the local civil date")
