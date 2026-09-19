"""Isolated HTTP + CLI + headless UI e2e for mous.

Run from the repo root:

    uv run python scripts/e2e.py
    uv run python -m e2e_mous

Never writes to ~/Library/Application Support/mous/data.db.
"""

from e2e_mous.harness import E2E_PORT, Failed, expect, log

__all__ = ["E2E_PORT", "Failed", "expect", "log"]
