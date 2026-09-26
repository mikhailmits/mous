"""Multi-vendor tokenizers, including GPT-5* via tiktoken o200k_base."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from typing import Callable

from experiments.tokenization.paths import CACHE

os.environ.setdefault("HF_HOME", str(CACHE / "hf"))
os.environ.setdefault("TRANSFORMERS_CACHE", str(CACHE / "hf"))
os.environ.setdefault("TIKTOKEN_CACHE_DIR", str(CACHE / "tiktoken"))

HF_TOKENIZERS: list[tuple[str, str, str]] = [
    ("qwen2.5", "Qwen/Qwen2.5-0.5B", "Alibaba Qwen 2.5 (also used by many Qwen chat models)"),
    ("llama3.2", "unsloth/Llama-3.2-1B-Instruct", "Meta Llama 3.2 via Unsloth tokenizer files"),
    ("phi-3-mini", "microsoft/Phi-3-mini-4k-instruct", "Microsoft Phi-3"),
    ("deepseek-r1-qwen", "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B", "DeepSeek R1 distill (Qwen vocab)"),
    ("smollm2", "HuggingFaceTB/SmolLM2-135M", "HuggingFace SmolLM2"),
    ("mbert", "google-bert/bert-base-multilingual-cased", "mBERT WordPiece, contrast tokenizer"),
    ("gpt2", "openai-community/gpt2", "GPT-2 BPE (r50k-class)"),
]


@dataclass
class Tokenizer:
    name: str
    vendor: str
    notes: str
    encode_len: Callable[[str], int]


def _tiktoken(name: str, encoding_name: str, vendor: str, notes: str) -> Tokenizer | None:
    try:
        import tiktoken
    except ImportError:
        return None
    try:
        enc = tiktoken.get_encoding(encoding_name)
    except Exception:
        return None

    def count(text: str) -> int:
        return len(enc.encode(text, disallowed_special=()))

    return Tokenizer(name=name, vendor=vendor, notes=notes, encode_len=count)


def _tiktoken_model(name: str, model: str, vendor: str, notes: str) -> Tokenizer | None:
    try:
        import tiktoken
    except ImportError:
        return None
    try:
        enc = tiktoken.encoding_for_model(model)
        encoding_name = enc.name
    except KeyError:
        enc = tiktoken.get_encoding("o200k_base")
        encoding_name = "o200k_base (fallback)"

    def count(text: str) -> int:
        return len(enc.encode(text, disallowed_special=()))

    return Tokenizer(
        name=name,
        vendor=vendor,
        notes=f"{notes} encoding={encoding_name}",
        encode_len=count,
    )


def _hf(name: str, repo: str, notes: str) -> Tokenizer | None:
    try:
        from transformers import AutoTokenizer
    except ImportError:
        return None
    try:
        tok = AutoTokenizer.from_pretrained(repo, use_fast=True, trust_remote_code=True)
    except Exception as exc:
        print(f"skip hf tokenizer {name}: {exc}")
        return None

    def count(text: str) -> int:
        return len(tok.encode(text, add_special_tokens=False))

    return Tokenizer(name=name, vendor=repo, notes=notes, encode_len=count)


@lru_cache(maxsize=1)
def load_tokenizers() -> list[Tokenizer]:
    loaded: list[Tokenizer] = []
    specs = [
        _tiktoken_model(
            "openai-gpt-5",
            "gpt-5",
            "OpenAI",
            "GPT-5* family. tiktoken maps gpt-5 prefix to o200k_base.",
        ),
        _tiktoken_model(
            "openai-gpt-5-mini",
            "gpt-5-mini",
            "OpenAI",
            "GPT-5 mini. Same o200k_base prefix map as gpt-5*.",
        ),
        _tiktoken_model(
            "openai-gpt-5.1",
            "gpt-5.1",
            "OpenAI",
            "gpt-5.1 also matches the gpt-5 prefix → o200k_base.",
        ),
        _tiktoken(
            "openai-o200k_base",
            "o200k_base",
            "OpenAI",
            "Raw o200k_base used by GPT-4o, GPT-4.1, GPT-5*, o-series.",
        ),
        _tiktoken(
            "openai-cl100k_base",
            "cl100k_base",
            "OpenAI",
            "GPT-4 / GPT-3.5-turbo tokenizer.",
        ),
        _tiktoken(
            "openai-p50k_base",
            "p50k_base",
            "OpenAI",
            "Codex / davinci-002 era.",
        ),
        _tiktoken(
            "openai-r50k_base",
            "r50k_base",
            "OpenAI",
            "GPT-2 / GPT-3 base BPE.",
        ),
        _tiktoken(
            "openai-o200k_harmony",
            "o200k_harmony",
            "OpenAI",
            "Harmony chat tokens used by gpt-oss; related GPT-5-era lineage.",
        ),
    ]
    for tok in specs:
        if tok is not None:
            loaded.append(tok)
        else:
            print(f"skip tiktoken spec")

    for name, repo, notes in HF_TOKENIZERS:
        tok = _hf(name, repo, notes)
        if tok is not None:
            loaded.append(tok)
    return loaded


def count_all(text: str, tokenizers: list[Tokenizer] | None = None) -> dict[str, int]:
    tokenizers = tokenizers or load_tokenizers()
    return {tok.name: tok.encode_len(text) for tok in tokenizers}
