from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = Path(__file__).resolve().parent
CORPUS = PKG / "corpus"
RESULTS = PKG / "results"
CACHE = PKG / ".cache"
CODECS_DIR = PKG / "codecs"
IMAGES = RESULTS / "images"
LLM_RAW = RESULTS / "llm_raw"

for _path in (CORPUS, RESULTS, CACHE, IMAGES, LLM_RAW):
    _path.mkdir(parents=True, exist_ok=True)
