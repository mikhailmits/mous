"""Subagent drop-in codecs. Import-safe even if empty.

Add @fn_codec functions here or in extra_*.py files that `load_all` can import.
"""

from __future__ import annotations

# Subagents should register codecs via experiments.tokenization.codecs.base.fn_codec
# Example:
# from experiments.tokenization.codecs.base import fn_codec
# from experiments.tokenization.bundle import Bundle
# @fn_codec("my_codec", "novel", "what it does")
# def my_codec(bundle: Bundle) -> str:
#     return "..."
