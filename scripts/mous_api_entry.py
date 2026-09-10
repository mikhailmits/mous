"""Entry for the frozen macOS helper. Host/port come from the Swift launcher."""

from __future__ import annotations

import os

from mous.api.app import run


def main() -> None:
    host = os.environ.get("MOUS_API_HOST", "127.0.0.1")
    port = int(os.environ.get("MOUS_API_PORT", "8000"))
    run(host=host, port=port)


if __name__ == "__main__":
    main()
