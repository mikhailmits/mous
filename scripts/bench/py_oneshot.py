#!/usr/bin/env python3
"""A single HTTP request, used to measure per-invocation (cold-start) cost of
the Python baseline the same way `mou <cmd>` is measured for the Rust client."""

from __future__ import annotations

import sys
import urllib.request

BASE = "http://127.0.0.1:18999"


def main() -> None:
    op = sys.argv[1] if len(sys.argv) > 1 else "get"
    ident = sys.argv[2] if len(sys.argv) > 2 else "1"
    if op == "get":
        url = f"{BASE}/transactions/{ident}"
    elif op == "list":
        url = f"{BASE}/transactions"
    else:
        url = f"{BASE}/health"
    with urllib.request.urlopen(url, timeout=10) as resp:
        resp.read()


if __name__ == "__main__":
    main()
