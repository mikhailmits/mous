"""Subagent drop-in codecs. Import-safe even if empty.

Add @fn_codec functions here or in extra_*.py files that `load_all` can import.
"""

from __future__ import annotations

# Subagents should register codecs via experiments.tokenization.codecs.base.fn_codec
# load_all() also imports extra_*.py; this import is a stable hook for the spaces specialist.
from experiments.tokenization.codecs import extra_spaces as _extra_spaces  # noqa: F401
from experiments.tokenization.codecs import extra_dsl as _extra_dsl  # noqa: F401
from experiments.tokenization.codecs import extra_images as _extra_images  # noqa: F401
from experiments.tokenization.codecs import extra_compress as _extra_compress  # noqa: F401
from experiments.tokenization.codecs import extra_lang as _extra_lang  # noqa: F401
from experiments.tokenization.codecs import extra_tick as _extra_tick  # noqa: F401
