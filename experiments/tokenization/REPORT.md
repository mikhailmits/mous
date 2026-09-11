# Tokenization lab report

Status: **done**. Five specialists landed. Fair 1000-row OCR is measured and fails. No further fair encoding beats `tiny_ledger_vm` by >3% tokens while holding quality. Ship pre-aggregated tool views, not 1000 raw rows.

## Setup

- 1000 transactions on `127.0.0.1:8000` (live export matches gold).
- Gold: income **90564.20**, expense **75572.82**, net **14991.38**, top **rent** 22703.20, best cut **shopping**, next-month spend **2888.14** / income **4581.06** (mean of last 3 months: 2026-07, 2026-08, 2026-09).
- GPT-5* tokenizer: tiktoken **`o200k_base`**. Pretty JSON = **55,614** tokens. **119+ codecs** on the leaderboard.

## What to ship (diagram)

`input → agent + tools → reports / optimize / forecasts`

Tools must pre-aggregate. Small models cannot add 1000 amounts **or** 16 category totals. Put the answer fields in the tool payload.

| encoding | GPT-5 tokens | quality | role |
| --- | ---: | --- | --- |
| **`tool_copy`** | **196** | **1.00 Qwen** (exact) | **ship this to 7b-class models** |
| slim `tool_views` (live API, last-3) | 651 | 1.00 Qwen | same idea, extra tool dumps |
| `aggregates_only` | 709 | 0.83 Qwen | fatter JSON; `discretionary_share` misread as a percent |
| **`tool_rollup`** | **378** | **1.00 Gemini** / 0.4–0.0–1.0 Qwen | honest GROUP BY; Python reconstructs gold |
| `tool_rollup_ranked` | 378 | Qwen 0.6 / 0.5 / 0.5 | sorting helps argmax, not sums |
| **`img_monthly_table`** | **255 tiles** | **1.00 Gemini** | vision analog of tool views |
| `img_summary_card` | 255 tiles | reports 1.0, forecasts 0 | too cramped |
| fair 1000-row text (`tiny_ledger_vm`) | 5,123 | ~0 | Python-summable; models cannot add |
| fair 1000-row image (`img_4col_1bit`) | 765 tiles | 0.07 Gemini | n=1000 only; invented round money |
| gzip+base64 | 7,863 | 0.00 | unreadable |

**7b-class:** return the three task JSON blobs (`tool_copy`). Copy, do not re-sum.

**Gemini-class:** category + last-3 GROUP BYs (`tool_rollup`, 378 tokens) score 1.0 under the 5% numeric band. Expense was 75023.28 vs gold 75572.82 (0.73% low). For exact money, still prefer `tool_copy`.

Do **not** dump 19 months of spend. Qwen re-averages history and misses the last-3 forecast (2888 → 4072).

## Fair reversible line items (still ~5.1k, still ~0 quality)

Unchanged cluster: `tiny_ledger_vm` **5,123** / `group_cat_name_daynum` **5,125** / `freq_daypack` **5,170**. Half of `yaml_like` **12,020**. No new fair codec is both cheaper than 12,020 **and** closer to `aggregates_only` accuracy.

`dsl_cat_month` (5,230, not row-reversible) reconstructs gold in Python and got **0.4** reports on gpt-4.1-mini after `n=1000`. Compact DSL does not fix arithmetic.

### (a) Spaces

Keep ASCII spaces. YYMMDD + integer cents + group-by-category/merchant + omit default `eur`/`main`. Glue / delete / NBSP / `▁` **increase** o200k tokens (`sticky_amount_no_space` 17,534 vs `line_natural` 15,925).

### (b) Symbols

ASCII space wins. `|`, tab, `·`, unit-separator, SentencePiece `▁` all lose.

### (c) Languages

Translating labels only is weak; full-name CJK often worse. Structural win: `lang_ko_ideo_monthly` **7,240**, `lang_ideo_monthly` **7,273**, `lang_ja_ideo_monthly` **7,281**. Still behind the English grouped DSLs at ~5.1k. Monthly header + one 1-token glyph per category is the trick, not “write it in Chinese.”

### (d) Compression / crypto

Readable `tiny_ledger_vm` / `freq_daypack` beat gzip on tokens **and** stay ledgers. gzip+b64 **7,863** tokens, accuracy **0**. Hex / XOR are 40k+ and opaque.

### (e) Images — fair 1000-row OCR is now measured

Tile formula: `85 + 170 * ceil(w/512)*ceil(h/512)` after the 2048/768 rescale. Do **not** quote `[image …]` text stubs.

Tall 360×9004 PNG = 765 tiles and ~2px glyphs after scale: **do not use**.

Native packings (specialist 4):

| codec | tiles | high tokens | glyph | Gemini 3-task acc |
| --- | ---: | ---: | --- | --- |
| `img_1tile_micro` | 1 | 255 | ~4px / 10-col | not scored (unreadable) |
| `img_2tile_compact` | 2 | **425** | ~6px / 6-col | **0.4 / 0.5 / 0.0** |
| `img_4col_1bit` | 4 | **765** | ~8px / 4-col | **0.2 / 0.0 / 0.0** |
| `img_monthly_table` | 1 | **255** | pre-aggregated | **1.0 / 1.0 / 1.0** |
| `img_summary_card` | 1 | 255 | gold card | reports 1.0, forecasts 0 |
| four 512² splits | 4×1 | **1020** | same 8px | not scored (strictly more tokens) |

**Official task eval (Gemini 2.5 Flash):**

- `img_4col_1bit`: n=1000 only (and the prompt mentions 1000). Expense invented as 32027.90, top=`groc`, forecasts −1000 / 3200. Native 8px is **not** enough to sum 942 expenses.
- `img_2tile_compact`: n=1000 + guessed `top=rent` / `best_cut=shopping` with fake round amounts (income 100000, disc_share 200). Category names are in the legend; the arithmetic is not OCR.

Specialist one-shot probe on the same 4-col PNG: n=1000, top=rent, expense **59999.99** vs 75572.82. Same conclusion: structure is visible, sums are not.

Low-detail (85 tokens) squashes 2048→512 and repeats the tall-PNG failure. Splitting images pays the 85-token base per image and **loses**.

### (x) Novel / prompts / context engineering

- `n=` in the legend helps count, not sums.
- Compact eight-field prompt is <400 tokens; the ledger still dominates.
- Extra history in context **hurts** forecasts.
- Sorting GROUP-BY maps high-to-low (`tool_rollup_ranked`) lets Qwen copy the first key (rent, shopping) but it still summed ~half the categories (37778 vs 75572). **Argmax ≠ addition.**
- Qwen 7b **can** average three monthly numbers (`tool_rollup` forecasts 1.0) and **cannot** reliably sum ~16 category totals or 1000 rows.

## Architecture finding

Python on `tool_rollup` reconstructs every gold task field. The failure is the model, not the encoding.

| who | what they can do | what they cannot do |
| --- | --- | --- |
| Python / tools | sum 1000 rows, GROUP BY, last-3 mean | — |
| Qwen 2.5 7b | copy JSON; mean of 3 numbers | sum 16 categories; OCR 1000 rows |
| Gemini 2.5 Flash | copy JSON; argmax + mean of 3; ~0.7% sum of 16 | OCR 1000 painted rows |

So the agent should call `list_categories` / `get_spent(last3)` / `get_income(last3)` / `list_subscriptions` **and** have the tool layer emit the reports/optimize/forecasts objects. Do not stuff `list_transactions` (1000 rows) into a small model.

## Files

- Codecs: `codecs/extra_{spaces,compress,dsl,lang,images,tick}.py`
- Live agent: `agent_api.py` (HTTP tools → slim tool_views → model)
- Vision: `agent_vision.py --fair-ocr`, `results/vision_eval.json`
- Specialist notes: `results/subagents/{spaces,compress,dsl,images,languages}.md`
- Leaderboard: `results/leaderboard.md` (120 codecs)

## Why the loop stops

- Specialists finished (notes on disk).
- Families (a)–(e) and (x) are measured, including fair 1000-row OCR.
- No new **fair reversible** codec is both >3% cheaper than the 5.1k cluster **and** closer to tool-view accuracy.
- Production recommendation is stable: **tools pre-aggregate; 7b copies `tool_copy` (196); Gemini may compute from `tool_rollup` (378) or OCR `img_monthly_table` (255); never send 1000 raw rows.**
