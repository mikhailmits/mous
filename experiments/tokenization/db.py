"""Database bootstrap matching the API lifespan."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from oxyde import db

from mous.api.app import _databases, _ensure_schema
from mous.db.utils import ensure_defaults


@asynccontextmanager
async def database() -> AsyncIterator[None]:
    import mous.db.models  # noqa: F401

    await db.init(**_databases())
    await _ensure_schema()
    await ensure_defaults()
    try:
        yield
    finally:
        await db.close()
