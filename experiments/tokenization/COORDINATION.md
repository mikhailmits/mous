# Tokenization lab coordination

This folder is the shared workbench for the finance-agent tokenization experiment.

## Agent diagram tasks (the quality bar)

Input ledger → agent (+ tools) →

1. **reports** — totals, top categories, monthly series
2. **what and how to optimize** — discretionary cuts, subscriptions
3. **forecasts** — naive next-month income/spend from last 3 months

Gold labels live in `corpus/gold.json`. An encoding is a success only if GPT-5-class token count drops **and** task accuracy stays close to the json_pretty baseline.

## Shared artifacts

| path | owner | meaning |
| --- | --- | --- |
| `corpus/bundle.json` | parent | 1000 live API transactions |
| `corpus/gold.json` | parent | deterministic answers |
| `codecs/*.py` | everyone | reversible/lossy encoders |
| `results/token_counts.json` | parent | local tokenizer leaderboard |
| `results/llm_eval.json` | parent | multi-model gateway quality |
| `results/subagents/` | subagents | notes, extra codecs, ideas |
| `REPORT.md` | parent | rolling report |

## Codec contract

Use `fn_codec(name, family, notes)` from `codecs/base.py`. Families: `baseline`, `spaces`, `symbols`, `languages`, `crypto`, `images`, `novel`.

```python
from experiments.tokenization.codecs.base import fn_codec
from experiments.tokenization.bundle import Bundle

@fn_codec("my_idea", "novel", "one-line why")
def my_idea(bundle: Bundle) -> str:
    return "..."
```

Put new codecs in `codecs/extra.py` or `codecs/extra_<you>.py` and import them from `codecs/extra.py`.

## Rules

- Never print or commit API keys. Load `LLM_GATEWAY_API_KEY` from `/workspace/.env`.
- Do not spend more than ~$1.50 per subagent on the LLM gateway. Prefer local tiktoken counts.
- Do not delete other people's codecs.
- Fair codecs must be reconstructable (or clearly marked `reversible=False`).
- `aggregates_only` / summary images are cheats — useful bounds, not winners.
