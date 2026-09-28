"""Multi-model gateway quality evals for reports / optimize / forecasts."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import httpx

from experiments.tokenization.bundle import load_bundle
from experiments.tokenization.codecs.base import encode_all, load_all
from experiments.tokenization.gold import load_gold, score_prediction
from experiments.tokenization.paths import LLM_RAW, RESULTS
from experiments.tokenization.prompts import SYSTEM_BASE, TASK_PROMPTS, wrap_payload

PREFERRED_MODELS = [
    "qwen/qwen-2.5-7b-instruct",
    "google/gemini-2.5-flash",
    "openai/gpt-4.1-mini",
    "openai/gpt-5-nano",
    "openai/gpt-5-mini",
]
# Full gpt-5 is a reasoning model (hidden reasoning tokens). Use it sparingly, never as the default bulk judge.
# Codecs to send to models. Keep this tight — $9 budget.
LLM_CODECS = [
    "json_pretty",
    "json_compact",
    "csv",
    "dict_ids",
    "sticky_amount_no_space",
    "split_amount_spaces",
    "lang_zh",
    "gzip_b64",
    "aggregates_only",
    "toon",
    "finance_asm",
]


def _load_dotenv() -> dict[str, str]:
    values: dict[str, str] = {}
    env_path = Path("/workspace/.env")
    if not env_path.exists():
        return values
    for line in env_path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, raw = line.split("=", 1)
        values[name.strip()] = raw.strip().strip('"')
    return values


def _key() -> str:
    env = _load_dotenv()
    for name in ("LLM_GATEWAY_API_KEY",):
        key = os.environ.get(name, "").strip() or env.get(name, "").strip()
        if key:
            return key
    raise RuntimeError("LLM_GATEWAY_API_KEY missing")


def _chat_url() -> str:
    env = _load_dotenv()
    base = os.environ.get("LLM_GATEWAY_URL", "").strip() or env.get("LLM_GATEWAY_URL", "").strip()
    if not base:
        raise RuntimeError("LLM_GATEWAY_URL missing")
    base = base.rstrip("/")
    if base.endswith("/chat/completions"):
        return base
    return base + "/chat/completions"


def _models_url() -> str:
    env = _load_dotenv()
    base = os.environ.get("LLM_GATEWAY_URL", "").strip() or env.get("LLM_GATEWAY_URL", "").strip()
    if not base:
        raise RuntimeError("LLM_GATEWAY_URL missing")
    base = base.rstrip("/")
    if base.endswith("/chat/completions"):
        base = base[: -len("/chat/completions")]
    return base.rstrip("/") + "/models"


def _extract_json(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        return {}
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return {}


def chat(model: str, messages: list[dict], max_tokens: int = 900, timeout: float = 90.0) -> dict:
    headers = {
        "Authorization": f"Bearer {_key()}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/mikhailmits/mous",
        "X-Title": "mous-tokenization-lab",
    }
    body = {
        "model": model,
        "messages": messages,
        "temperature": 0,
        "max_tokens": max_tokens,
    }
    with httpx.Client(timeout=timeout) as client:
        response = client.post(_chat_url(), headers=headers, json=body)
        response.raise_for_status()
        return response.json()


def merge_eval_rows(
    path: Path,
    new_results: list[dict],
    key_fields: tuple[str, ...] = ("model", "codec", "task"),
) -> list[dict]:
    existing: dict[tuple, dict] = {}
    if path.exists():
        try:
            old = json.loads(path.read_text(encoding="utf-8"))
            for row in old.get("results", []):
                existing[tuple(row.get(field) for field in key_fields)] = row
        except (json.JSONDecodeError, OSError):
            pass
    for row in new_results:
        existing[tuple(row.get(field) for field in key_fields)] = row
    return list(existing.values())


def pick_models(limit: int = 3) -> list[str]:
    headers = {"Authorization": f"Bearer {_key()}"}
    try:
        with httpx.Client(timeout=30.0) as client:
            data = client.get(_models_url(), headers=headers).json()
        ids = {item["id"] for item in data.get("data", [])}
    except Exception as exc:
        print(f"model list failed ({exc}); using preferred blindly")
        ids = set(PREFERRED_MODELS)
    chosen = [mid for mid in PREFERRED_MODELS if mid in ids or not ids]
    # unique preserve order
    seen = set()
    out = []
    for mid in chosen:
        if mid in seen:
            continue
        seen.add(mid)
        out.append(mid)
        if len(out) >= limit:
            break
    return out


def run(
    model_limit: int = 2,
    codec_names: list[str] | None = None,
    models: list[str] | None = None,
    merge: bool | None = None,
) -> dict:
    load_all()
    bundle = load_bundle()
    gold = load_gold()
    models = models or pick_models(limit=model_limit)
    names = codec_names or LLM_CODECS
    merge = codec_names is not None if merge is None else merge
    encoded = {item.name: item for item in encode_all(bundle, names=names)}
    results = []
    path = RESULTS / "llm_eval.json"
    for model in models:
        for name in names:
            result = encoded.get(name)
            if result is None:
                continue
            if not result.token_payload:
                continue
            for task, task_prompt in TASK_PROMPTS.items():
                messages = [
                    {"role": "system", "content": SYSTEM_BASE},
                    {
                        "role": "user",
                        "content": task_prompt
                        + "\n\n"
                        + wrap_payload(result.decode_instructions, result.token_payload),
                    },
                ]
                record = {
                    "model": model,
                    "codec": name,
                    "task": task,
                    "ok": False,
                }
                try:
                    raw = chat(model, messages)
                    content = raw["choices"][0]["message"]["content"] or ""
                    usage = raw.get("usage") or {}
                    parsed = _extract_json(content)
                    score = score_prediction(parsed, gold, task=task)
                    record.update(
                        {
                            "ok": True,
                            "accuracy": score["accuracy"],
                            "passed": score["passed"],
                            "total": score["total"],
                            "checks": score["checks"],
                            "usage": usage,
                            "preview": content[:500],
                        }
                    )
                    (LLM_RAW / f"{model.replace('/', '_')}__{name}__{task}.json").write_text(
                        json.dumps({"raw": raw, "parsed": parsed, "score": score}, indent=2)[:200_000],
                        encoding="utf-8",
                    )
                    print(
                        f"{model} {name} {task} acc={score['accuracy']} "
                        f"in={usage.get('prompt_tokens')} out={usage.get('completion_tokens')}"
                    )
                except Exception as exc:
                    record["error"] = str(exc)[:400]
                    print(f"FAIL {model} {name} {task}: {exc}")
                results.append(record)
                time.sleep(0.15)

    if merge:
        results = merge_eval_rows(path, results)
        names = sorted({row.get("codec") for row in results if row.get("codec")})
        models = sorted({row.get("model") for row in results if row.get("model")})
    summary = _summarize(results)
    payload = {"models": models, "codecs": names, "results": results, "summary": summary}
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"wrote {path}")
    return payload


def _summarize(results: list[dict]) -> dict:
    by_codec: dict[str, list[float]] = {}
    by_model: dict[str, list[float]] = {}
    prompt_tokens = 0
    completion_tokens = 0
    for row in results:
        if not row.get("ok"):
            continue
        by_codec.setdefault(row["codec"], []).append(row["accuracy"])
        by_model.setdefault(row["model"], []).append(row["accuracy"])
        usage = row.get("usage") or {}
        prompt_tokens += int(usage.get("prompt_tokens") or 0)
        completion_tokens += int(usage.get("completion_tokens") or 0)

    def avg(xs: list[float]) -> float:
        return round(sum(xs) / len(xs), 4) if xs else 0.0

    return {
        "by_codec_accuracy": {k: avg(v) for k, v in sorted(by_codec.items())},
        "by_model_accuracy": {k: avg(v) for k, v in sorted(by_model.items())},
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "n_ok": sum(1 for r in results if r.get("ok")),
        "n_fail": sum(1 for r in results if not r.get("ok")),
    }


if __name__ == "__main__":
    run()
