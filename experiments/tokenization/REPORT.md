# Tokenization lab report

Status: tick 2. Specialists landed spaces / languages / compression / DSL / images. API still serving 1000 rows. Loop remains armed.

## Setup (unchanged)

- 1000 transactions, 5 subscriptions, 16 categories, 3 accounts on `127.0.0.1:8000`.
- Gold: income **90564.20**, expense **75572.82**, net **14991.38**, top spend **rent** 22703.20, best cut **shopping** 9175.33, next-month spend **2888.14**.
- GPT-5* tokenizer: tiktoken **`o200k_base`**. 111 codecs registered. 15 local tokenizers.

## What to ship for the diagram (quality + speed)

The agent is `input → tools → reports / optimize / forecasts`. Stuffing 1000 raw rows into a small/mid model **fails the tasks**. Putting **tool results** in context succeeds.

| encoding | GPT-5 tokens | Qwen accuracy | notes |
| --- | ---: | ---: | --- |
| **`tool_views`** | **967** | **1.00** (5/5 + 2/2 + 2/2) | recommended agent context: balances, monthly series, category spend, subs, forecast window, plus the exact JSON fields |
| `aggregates_only` | 709 | 0.83 | reports/forecasts perfect; optimize share was read as a percent before the prompt fix |
| `month_cat_sums` | 1,306 | 0.03–0.20 | SQL GROUP BY is still too much arithmetic for Qwen *and* Gemini 2.5 Flash |
| gzip+base64 | 7,864 | 0.00 | unreadable |
| 1000 raw rows (any packing) | 4k–12k | ≤0.23 | models guess “shopping” sometimes, cannot sum |

**Product rule:** use Mous API tools (`/spent`, `/balance`, category rollups) and send `tool_views` (~1k tokens). That is cheaper *and* exact. Compact line-item encodings are only for when the model must see merchants.

## Fair reversible line-item leaders (GPT-5 / o200k)

Old fair leader was `yaml_like` at **12,020** (21.6% of pretty JSON 55,614). New floor:

| codec | tokens | vs yaml_like | vs pretty | source |
| --- | ---: | ---: | ---: | --- |
| **`tiny_ledger_vm`** | **5,123** | 43% | 9.2% | compress specialist — monthly salary/rent/gym/netflix templates + extras |
| **`group_cat_name_daynum`** | **5,125** | 43% | 9.2% | spaces specialist — category→merchant groups, day-number + cents, spaces kept |
| `delta_days_by_name` | 5,145 | 43% | 9.3% | spaces |
| `freq_daypack` | 5,170 | 43% | 9.3% | compress — 1–2 char merchant codes |
| `lang_ideo_monthly` | 7,286 | 61% | 13.1% | languages — one ideograph per category, monthly buckets |
| `yaml_like` | 12,020 | 100% | 21.6% | previous fair leader |
| pretty JSON | 55,614 | 463% | 100% | wasteful control |

`group_cat_name_daynum` round-tripped all 1,000 rows (spaces specialist). `tiny_ledger_vm` / `freq_daypack` also reconstruct the multiset with a legend. **12,020 was not the readable floor** — grouping + cents + YYMMDD/day-numbers + omitted default `eur`/`main` halves it.

Qwen/Gemini still cannot *add* these compact ledgers. Token wins ≠ task wins unless tools pre-aggregate.

### (a) Spaces

Deleting or gluing spaces still **increases** GPT-5 tokens. New measured mechanics (spaces *kept*):

1. ISO date `2025-03-01` is **6** o200k pieces; `250301` is **2** (−4,000 on this corpus).
2. Float `-19.81` wastes a `.` token; integer cents save ~1.2 tokens/row.
3. Group by category then merchant so labels with a **leading space** (` groceries`) are one token and written once.
4. Drop default `eur`/`main` (991 + 901 rows).

NBSP / thin space / `|` / `▁` all lose. Short 3-letter category codes lose to the already-single-token English words after a space.

### (b) Symbols

Unchanged: ASCII space wins. NBSP/thin on an already-compressed payload jumped 10,695 → 16,984.

### (c) Languages

Category-only translation was a dead end. Full-name Chinese/Japanese/Korean **increased** tokens (`lang_zh_full` 19,735 vs `lang_zh` 17,993) because 2-char CJK + a bilingual legend is not free. The language win is **structural**, not translation: `lang_ideo_monthly` at **7,286** (one ideograph per category, monthly buckets). Hangul digit packing as a drop-in for Arabic numerals did not beat that.

### (d) Encryption / compression

Opaque gzip remains ~7.8k and accuracy 0. **Model-readable** compression (`tiny_ledger_vm`, `freq_daypack`) **beats gzip on tokens (5.1k) and stays a ledger**. Base62 amounts (`base62_daypack` 5,300) are a wash vs decimal codes and harder to read.

### (e) Images

Tall 1000-line PNG = **765** high-detail tiles. New packings:

| layout | vision tokens (high) | notes |
| --- | ---: | --- |
| `img_1tile_micro` | **255** | full ledger forced into one 512² tile — glyphs are microscopic |
| `img_2tile_compact` | 425 | two 512×1024 tiles |
| `img_monthly_table` | 255 | aggregates only, not fair |
| original tall PNG | 765 | unreadable tall strip |
| 4-way split | 1,020 | splitting *increases* tiles |

Low-detail is always 85 tokens and would be even less readable. **No vision model was asked to OCR 1000 painted lines this tick** — 255 tiles is a cost bound, not a quality win.

### (x) Novel / DSL / tools

- `tool_views` is the diagram codec: **967 tokens, accuracy 1.0**.
- `dsl_month_ids` 7,375 and `dsl_cron` 7,530 beat yaml_like with spaces kept.
- `cat_inverted` 4,058 drops merchant names (still reversible for amounts/timing) but Qwen accuracy 0.

## Gateway spend (this lab)

Rescored traces: **397k prompt + 6.5k completion** tokens across Qwen 2.5 7B and a Gemini 2.5 Flash probe. GPT-5 chat is not used as the bulk judge (hidden reasoning tokens). Tokenizer comparisons still use `o200k_base` for GPT-5*.

## Still open (loop continues)

- Image OCR quality at 255–425 vision tokens (image specialist file is in; no multimodal eval yet).
- Whether a *tool-using* loop (model calls `/spent` instead of reading `tool_views` pre-baked) matches 1.0 accuracy with even fewer prompt tokens.
- Language codecs were counted, not quality-scored.
- Do not declare a raw-row encoding “done” until a model can actually sum it, or until we accept that tools must sum.
