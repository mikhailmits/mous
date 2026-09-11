# Tokenization lab report

Status: tick 3. All five specialists have notes on disk. Live API → slim `tool_views` scores **1.0** on the three diagram tasks. Gemini OCR of the monthly table image also scores **1.0**. Loop stays armed: a 1000-line painted ledger has not been OCR-scored.

## Setup

- 1000 transactions on `127.0.0.1:8000` (live export still matches gold).
- Gold: income **90564.20**, expense **75572.82**, net **14991.38**, top **rent** 22703.20, best cut **shopping**, next-month spend **2888.14**.
- GPT-5* tokenizer: tiktoken **`o200k_base`**.

## What to ship (diagram)

`input → agent + tools → reports / optimize / forecasts`

Do **not** dump 19 months of spend into the prompt. Qwen then re-averages every month and misses the last-3 forecast (2888 → 4072). Restrict `get_spent` / `get_income` to **last3**. Slim `tool_views` is **651 GPT-5 tokens**, **1825 chars**, live-API Qwen accuracy **1.00** on all three tasks (`experiments/tokenization/agent_api.py`).

| encoding | GPT-5 tokens | quality | role |
| --- | ---: | --- | --- |
| **slim `tool_views` from live API** | **651** | **1.00** Qwen | **ship this** |
| `aggregates_only` | 709 | 0.83 | same idea, slightly fatter JSON |
| **`img_monthly_table` (vision)** | **255 tiles** | **1.00** Gemini 2.5 Flash | agent-mode image of monthly+category totals |
| `img_summary_card` | 255 tiles | reports 1.0, forecasts 0 | too cramped; paints gold but Gemini missed last-3 |
| gzip+base64 | 7,864 | 0.00 | unreadable |
| fair 1000-row text (`tiny_ledger_vm`) | 5,123 | ~0 | Python-summable, models cannot add |

## Fair reversible line items (still ~5.1k)

Unchanged cluster: `tiny_ledger_vm` 5,123 / `group_cat_name_daynum` 5,125 / `freq_daypack` 5,170. Half of `yaml_like` 12,020. **Not** a quality win for LLMs.

`dsl_cat_month` (5,230, not row-reversible) recovered gold in Python and got **0.4** reports on gpt-4.1-mini after stamping `n=1000` (n and top=rent correct; money totals still guessed). Compact DSL does not fix arithmetic.

### (a) Spaces

Keep ASCII spaces. YYMMDD + cents + group-by-category/merchant + omit default eur/main. Glue/delete/NBSP/`▁` lose.

### (b) Symbols

ASCII space wins.

### (c) Languages

After unique Hangul syllables: `lang_ko_ideo_monthly` **7,240**, `lang_ideo_monthly` **7,273**. Still behind the English grouped DSLs. Full-name CJK translation is not the win; monthly + one glyph per category is.

### (d) Compression

Readable `tiny_ledger_vm` / `freq_daypack` beat gzip on tokens and stay ledgers. gzip accuracy 0.

### (e) Images — now with a vision probe

Tall 1000-line PNG = 765 tiles and ~2px glyphs after scale: **do not use**.

Native packings (specialist 4): `img_1tile_micro` 255 (unreadable 4px/10-col), `img_2tile_compact` 425 (cliff), `img_4col_1bit` 765 with ~8px glyphs (maybe). Splitting images **raises** cost (four 512² = 1020).

**Gemini 2.5 Flash** on `img_monthly_table` (512², 2-col totals, 255 high-detail tokens): **reports 1.0, optimize 1.0, forecasts 1.0**. That is the vision analog of tool views — pre-aggregated, not a fair 1000-row OCR. `img_summary_card` failed forecasts. **No VLM was asked to sum 1000 painted line items.**

### (x) Novel / prompts

`n=` in the legend helps count, not sums. Compact eight-field prompt is <400 tokens; the ledger still dominates. Extra history in context **hurts** forecasts.

## Files

- Codecs: `codecs/extra_{spaces,compress,dsl,lang,images,tick}.py`
- Live agent: `agent_api.py` (HTTP tools → slim tool_views → model)
- Vision: `agent_vision.py`, `results/vision_eval.json`
- Specialist notes: `results/subagents/{spaces,compress,dsl,images}.md`

## Still open (loop continues)

- OCR of a fair 1000-row packing (`img_4col_1bit` / `img_2tile_compact`). Specialist write-up says “maybe / unlikely”; not measured.
- Do not mark a raw-row encoding as production-ready until a model can add it, or until tools add it.
