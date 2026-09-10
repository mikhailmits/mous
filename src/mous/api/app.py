from __future__ import annotations

import os
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from oxyde import db

from mous.api.errors import install_error_handlers
from mous.api.routers import (
    accounts_router,
    categories_router,
    currencies_router,
    subscriptions_router,
    transactions_router,
)


def _project_root() -> Path:
    """Repo root, or the frozen bundle's extra-files directory."""
    override = os.environ.get("MOUS_PROJECT_ROOT")
    if override:
        return Path(override)
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            return Path(meipass)
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[3]


def _databases() -> dict[str, str]:
    override = os.environ.get("MOUS_DATABASE_URL")
    if override:
        return {"default": override}
    root = _project_root()
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    import oxyde_config

    return oxyde_config.DATABASES


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    import mous.db.models  # noqa: F401 — register tables

    await db.init(**_databases())
    await _ensure_schema()
    from mous.db.utils import ensure_defaults

    await ensure_defaults()
    yield
    await db.close()


async def _ensure_schema() -> None:
    """Apply pending migrations so bootstrap and the API have tables."""
    from oxyde.db import create_tables, get_connection
    from oxyde.migrations import apply_migrations

    migrations_dir = _project_root() / "migrations"
    if migrations_dir.is_dir() and any(migrations_dir.glob("[0-9]*.py")):
        await apply_migrations(migrations_dir=str(migrations_dir))
        return
    await create_tables(await get_connection())


def create_app() -> FastAPI:
    app = FastAPI(
        title="mous",
        description="Personal spending API. Transaction `value` is signed: >0 income, <0 expense.",
        lifespan=lifespan,
    )
    install_error_handlers(app)

    @app.get("/health", include_in_schema=False)
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(accounts_router)
    app.include_router(transactions_router)
    app.include_router(subscriptions_router)
    app.include_router(currencies_router)
    app.include_router(categories_router)
    return app


app = create_app()


def run(host: str = "127.0.0.1", port: int = 8000) -> None:
    import uvicorn

    uvicorn.run("mous.api.app:app", host=host, port=port, reload=False)
