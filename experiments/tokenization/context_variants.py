"""Prompt / context variants as codecs that wrap another encoding.

These do not change the ledger; they change how the agent is asked to read it.
They are scored in llm evals, not in the raw token leaderboard (same payload).
"""

from __future__ import annotations

CONTEXT_VARIANTS = [
    {
        "name": "legend_first",
        "instructions": "A one-line legend precedes every data block. Treat unknown keys as errors.",
    },
    {
        "name": "tool_get_transactions",
        "instructions": "The ledger is the body of tool `get_transactions`. Do not echo it.",
    },
    {
        "name": "two_pass",
        "instructions": "Pass 1: unique categories and month keys. Pass 2: sums only. Never list rows in the answer.",
    },
    {
        "name": "numeric_only_answer",
        "instructions": "Answer JSON must contain numbers and category ids from the legend, never prose.",
    },
]
