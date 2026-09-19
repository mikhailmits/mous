#!/usr/bin/env python3
"""Shim: isolated HTTP + CLI + headless UI e2e for mous.

Never touches ~/Library/Application Support/mous/data.db.
Run from the repo root: uv run python scripts/e2e.py
The popup is driven off-screen (alpha 0, no screenshots, no focus steal).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from e2e_mous.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
