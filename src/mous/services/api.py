"""Read-only HTTP client for the local mous API."""

from __future__ import annotations

import json
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from mous.config.utils import api_host, api_port

_TIMEOUT = 3.0


class APIUnavailable(Exception):
    """The local API did not answer."""


def api_base() -> str:
    return f"http://{api_host()}:{api_port()}"


def get_json(path: str, params: dict[str, Any] | None = None) -> Any:
    query = ""
    if params:
        filtered = {key: value for key, value in params.items() if value is not None}
        if filtered:
            query = "?" + urlencode(filtered)
    url = f"{api_base()}{path}{query}"
    request = Request(url, method="GET")
    try:
        with urlopen(request, timeout=_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        raise APIUnavailable(f"mous API error {exc.code} at {url}") from exc
    except (URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        raise APIUnavailable(
            f"mous API is not running at {api_base()} (open Mous, then retry)"
        ) from exc


def items(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict) and isinstance(payload.get("items"), list):
        return [row for row in payload["items"] if isinstance(row, dict)]
    return []
