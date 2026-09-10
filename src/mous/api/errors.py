from _oxyde_core import DatabaseError
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from oxyde.exceptions import IntegrityError, NotFoundError

from mous.db.utils.errors import LastAccountError


def _error(status: int, error: str, detail: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": error, "detail": detail})


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(NotFoundError)
    async def not_found(_request: Request, exc: NotFoundError) -> JSONResponse:
        return _error(404, "not_found", str(exc) or "not found")

    @app.exception_handler(LastAccountError)
    async def last_account(_request: Request, exc: LastAccountError) -> JSONResponse:
        return _error(409, "last_account", str(exc))

    @app.exception_handler(IntegrityError)
    async def integrity(_request: Request, exc: IntegrityError) -> JSONResponse:
        return _error(409, "conflict", str(exc) or "constraint violated")

    @app.exception_handler(DatabaseError)
    async def database(_request: Request, exc: DatabaseError) -> JSONResponse:
        detail = str(exc) or "database error"
        lowered = detail.lower()
        if "constraint" in lowered or "foreign key" in lowered or "unique" in lowered:
            return _error(409, "conflict", detail)
        return _error(500, "database_error", detail)

    @app.exception_handler(RequestValidationError)
    async def validation(_request: Request, exc: RequestValidationError) -> JSONResponse:
        parts = []
        for err in exc.errors():
            loc = ".".join(str(part) for part in err.get("loc", ()) if part != "body")
            msg = err.get("msg", "invalid")
            parts.append(f"{loc}: {msg}" if loc else msg)
        return _error(422, "validation_error", "; ".join(parts) or "invalid request")
