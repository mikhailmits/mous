"""Diagram architecture: pull live Mous API tools, then ask the model.

Does not stuff 1000 raw rows. Builds the same compact view as `tool_views`
from HTTP: list accounts, balances, spent windows, categories, subscriptions.
"""

from __future__ import annotations

import json
import os
from collections import defaultdict
from datetime import date

import httpx

from experiments.tokenization.bundle import fetch_bundle
from experiments.tokenization.codecs.extra_tick import tool_views
from experiments.tokenization.evaluate_llm import chat, _extract_json
from experiments.tokenization.gold import compute_gold, load_gold, score_prediction
from experiments.tokenization.paths import RESULTS
from experiments.tokenization.prompts import SYSTEM_BASE, TASK_PROMPTS, wrap_payload

DEFAULT_BASE = os.environ.get("MOUS_API_BASE", "http://127.0.0.1:8000")


def tool_payload_from_api(base: str = DEFAULT_BASE) -> str:
    """Encode the live server the way the agent should after tool calls."""
    bundle = fetch_bundle(base)
    return tool_views.encode(bundle).token_payload


def verify_api_matches_gold(base: str = DEFAULT_BASE) -> dict:
    bundle = fetch_bundle(base)
    gold = compute_gold(bundle)
    saved = load_gold()
    return {
        "n": gold["reports"]["n_transactions"],
        "income_match": gold["reports"]["total_income"] == saved["reports"]["total_income"],
        "expense_match": gold["reports"]["total_expense"] == saved["reports"]["total_expense"],
        "top": gold["reports"]["top_category_by_spend"],
        "next_month_spend": gold["forecasts"]["next_month_spend_naive"],
        "tool_views_tokens_hint": "run tiktoken on tool_views payload",
        "payload_chars": len(tool_views.encode(bundle).token_payload),
    }


def ask_tasks(model: str = "qwen/qwen-2.5-7b-instruct", base: str = DEFAULT_BASE) -> dict:
    payload = tool_payload_from_api(base)
    gold = load_gold()
    results = []
    for task, task_prompt in TASK_PROMPTS.items():
        messages = [
            {"role": "system", "content": SYSTEM_BASE},
            {
                "role": "user",
                "content": task_prompt
                + "\n\n"
                + wrap_payload(
                    "These JSON blocks are tool results from the Mous HTTP API. "
                    "Copy reports, optimize, and forecasts fields as written. "
                    "Do not re-average every month; next_month_* is already the last-3 mean.",
                    payload,
                ),
            },
        ]
        raw = chat(model, messages)
        content = raw["choices"][0]["message"]["content"] or ""
        parsed = _extract_json(content)
        score = score_prediction(parsed, gold, task=task)
        results.append(
            {
                "task": task,
                "accuracy": score["accuracy"],
                "checks": score["checks"],
                "usage": raw.get("usage"),
            }
        )
        print(f"API-agent {model} {task} acc={score['accuracy']}")
    out = {"model": model, "source": "live_api_tool_views", "results": results}
    (RESULTS / "api_agent_eval.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    return out


def main() -> None:
    info = verify_api_matches_gold()
    print(json.dumps(info, indent=2))
    ask_tasks()


if __name__ == "__main__":
    main()
