"""Vision-model evals for painted ledgers (OpenAI-compatible image_url)."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
from pathlib import Path

from experiments.tokenization.bundle import load_bundle
from experiments.tokenization.codecs.base import encode_all, load_all
from experiments.tokenization.evaluate_llm import chat, merge_eval_rows, _summarize
from experiments.tokenization.gold import load_gold, score_prediction
from experiments.tokenization.paths import LLM_RAW, RESULTS
from experiments.tokenization.prompts import SYSTEM_BASE, TASK_PROMPTS

VISION_CODECS = ["img_monthly_table", "img_summary_card"]
FAIR_OCR_CODECS = ["img_4col_1bit", "img_2tile_compact"]
VISION_MODEL = "google/gemini-2.5-flash"


def _data_url(path: str) -> str:
    mime = mimetypes.guess_type(path)[0] or "image/png"
    blob = Path(path).read_bytes()
    return f"data:{mime};base64,{base64.b64encode(blob).decode('ascii')}"


def run(
    model: str = VISION_MODEL,
    codec_names: list[str] | None = None,
    merge: bool = True,
) -> dict:
    load_all()
    bundle = load_bundle()
    gold = load_gold()
    names = codec_names or VISION_CODECS
    encoded = {item.name: item for item in encode_all(bundle) if item.name in names}
    results = []
    path = RESULTS / "vision_eval.json"
    for name in names:
        result = encoded.get(name)
        if result is None or not result.image_paths:
            print(f"skip {name}: missing image")
            continue
        image_url = _data_url(result.image_paths[0])
        for task, task_prompt in TASK_PROMPTS.items():
            text = (
                f"{task_prompt}\n\nDECODE:\n{result.decode_instructions}\n"
                "Read the image. Do not invent rows that are not painted."
            )
            messages = [
                {"role": "system", "content": SYSTEM_BASE},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": text},
                        {"type": "image_url", "image_url": {"url": image_url}},
                    ],
                },
            ]
            record = {"model": model, "codec": name, "task": task, "ok": False}
            try:
                raw = chat(model, messages, max_tokens=900, timeout=180.0)
                content = raw["choices"][0]["message"]["content"] or ""
                from experiments.tokenization.evaluate_llm import _extract_json

                parsed = _extract_json(content)
                score = score_prediction(parsed, gold, task=task)
                usage = raw.get("usage") or {}
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
                (LLM_RAW / f"vision_{model.replace('/', '_')}__{name}__{task}.json").write_text(
                    json.dumps({"parsed": parsed, "score": score, "usage": usage}, indent=2)[:100_000],
                    encoding="utf-8",
                )
                print(
                    f"VISION {model} {name} {task} acc={score['accuracy']} "
                    f"in={usage.get('prompt_tokens')} cost={usage.get('cost')}"
                )
            except Exception as exc:
                record["error"] = str(exc)[:400]
                print(f"VISION FAIL {model} {name} {task}: {exc}")
            results.append(record)
    if merge:
        results = merge_eval_rows(path, results)
        names = sorted({row.get("codec") for row in results if row.get("codec")})
    payload = {
        "model": model,
        "codecs": names,
        "results": results,
        "summary": _summarize(results),
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"wrote {path}")
    return payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--codecs", default="")
    parser.add_argument("--fair-ocr", action="store_true")
    args = parser.parse_args()
    names = args.codecs.split(",") if args.codecs else None
    if args.fair_ocr:
        names = FAIR_OCR_CODECS
    run(codec_names=names)
