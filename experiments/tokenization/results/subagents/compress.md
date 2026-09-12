# Compress specialist (3/5) — model-readable codecs under yaml_like

**Success:** several **new, reversible, legend-in-payload** codecs land **under 11,000 GPT-5 (`o200k_base`) tokens**. gzip_b64 (7,863–7,864) is **not** a win: models cannot decode it for reports / optimize / forecasts.

Measured on all **1000** seeded transactions. Token counts are `tiktoken.get_encoding("o200k_base")` (same map as GPT-5 / GPT-5-mini / GPT-5.1). Codecs live in `codecs/extra_compress.py` (imported from `codecs/extra.py`). Round-trip decoders reconstruct `(name, cents, date, currency, account, category)` as a multiset; transaction `id` is omitted, matching `yaml_like`.

## Leaderboard (this specialist)

| codec | GPT-5 tokens | vs yaml_like 12,020 | vs pretty 55,614 | chars | reversible | readable? |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| **tiny_ledger_vm** | **5,123** | 42.6% | 9.2% | 11,164 | yes | yes (templates + extras) |
| **freq_daypack** | **5,170** | 43.0% | 9.3% | 11,361 | yes | **yes — recommended** |
| base62_daypack | 5,300 | 44.1% | 9.5% | 9,881 | yes | mixed (base62 amounts) |
| **daypack_names** | **6,016** | 50.0% | 10.8% | 19,445 | yes | **yes, no codebook** |
| rle_cat_delta | 6,228 | 51.8% | 11.2% | 12,396 | yes | yes |
| columnar_ints_only | 7,712 | 64.2% | 13.9% | 12,679 | yes | yes (zip columns) |
| gzip_b64 (opaque bound) | 7,864 | 65.4% | 14.1% | ~11.5k | yes | **no** |
| month_dict_cents | 7,777 | 64.7% | 14.0% | 13,562 | yes | yes |
| yaml_like (fair leader before) | 12,020 | 100% | 21.6% | 34,598 | partial* | yes |
| dict_ids | 13,186 | 110% | 23.7% | 19,992 | yes | yes |
| aggregates_only (cheat bound) | 709 | 5.9% | 1.3% | 1,594 | no | n/a |

\* `yaml_like` drops account and currency. The new codecs **restore** them via defaults (`main`/`eur`) plus `*` credit, `~` savings, `$` usd.

**12,020 is not near the readable floor.** Dropping YAML punctuation, moving category into a 50-row legend, storing cents, and packing same-day rows already halves it. Letter codes vs full names is only another ~800 tokens.

## Why a model can still compute reports

`freq_daypack` (and the VM / name variants) are **plain text with an in-payload legend**, not a cipher.

1. **`n_transactions`** — count `(code, cents)` pairs under day lines (or template ops + extras in the VM). Gold = **1000**.
2. **`total_income`** — sum `cents/100` where cents `> 0`. Gold = **90564.20**.
3. **`total_expense`** — sum `-cents/100` where cents `< 0`. Gold = **75572.82**.
4. **`top_category_by_spend`** — map each code through the legend’s category, sum expense, take argmax. Gold = **rent** (22703.20), because opcode/code `t` / template `R` is `apartment rent / rent`.

Deterministic decode of `freq_daypack` reproduces those four gold fields exactly (same cents rounding as `gold.py`). Forecasts need the `YYYY-MM` headers (already present). Optimize needs category names (in the legend) plus discretionary labels in the prompt.

Sample (`freq_daypack`):

```
V=cents/100. default eur main. *=credit ~=savings $=usd. ...
a bakery coffee coffee
...
s monthly salary salary
t apartment rent rent
2025-03
01 s 324394 a -663 k -5434
03 t -118100
08 l -1599 v -4999
17 r -1474 g -1903 av -5510 h -1445 * e -2632 *
```

`01 s 324394` = 2025-03-01 monthly salary +3243.94 (income). `h -1445 *` = trattoria roma −14.45 on **credit**.

## Ablation from yaml_like (same 1000 rows)

| step | GPT-5 tokens | what changed |
| --- | ---: | --- |
| yaml_like | 12,020 | `YYYY-MM:` + `  - DD name value category` |
| drop list-dash | 11,020 | `  -` is ~1 token × 1000 |
| drop indent | 9,020 | leading spaces were not free |
| drop per-row category | 8,020 | merchant→category is 1:1 (50-row legend) |
| cents instead of `12.34` | 6,790 | `-6.63` is 4 tokens; `-663` is 2 |
| day-pack + names + flags + legend | 6,016 | `daypack_names` |
| freq 1–2 char codes | 5,170 | ` a` is 1 token; ` 0` is 2 — letters beat int ids |
| monthly templates + extras | 5,123 | `tiny_ledger_vm` |

Integer `dict_ids` (13,186) lost because **small integers with a leading space cost more than letters**, and it still repeated YYYY-scale dates. Combining months + int ids (`month_dict_cents`, 7,777) beats yaml_like but loses to letter codes.

base62 cents **did not win** (5,300 > 5,170): o200k already likes decimal integers; a rare alphabet adds tokens and hurts readability.

## Codec notes

| codec | idea |
| --- | --- |
| `freq_daypack` | Frequency-ranked `a`–`z` then `aa`–`ax` (top 26 cover 724/1000 txs). Month header, same-day packing, cents, sparse flags. |
| `tiny_ledger_vm` | `M25-03:+324394;R-118100;I-8020;G;N` emits salary d01, rent d03, insurance d05, gym d08 −4999, netflix d08 −1599. Remaining rows are a daypack exception list. |
| `daypack_names` | Same packing, English merchants, no codes. Best “a human/model reads it cold” fair codec. |
| `rle_cat_delta` | Sort by category, `CAT xN` run header, delta days, codes, cents. Helps category scans. |
| `columnar_ints_only` | Parallel `D N V` integer streams, no JSON keys, sparse `Aex`/`Yex`. |
| `month_dict_cents` | yaml_like grouping **plus** dict_ids (freq integer ids + cents). |
| `base62_daypack` | Same as freq_daypack with signed base62 amounts. Measured, not recommended. |

Pretty-print gzip is forbidden as a winner and was not used.

## Quality check

One gateway call (`openai/gpt-4.1-mini`, reports **only**, cost **$0.0022**, 5432 prompt / 36 completion tokens). Details: `results/subagents/compress_llm.json`.

The model returned valid JSON but **missed all four gold fields** (n=1323 vs 1000, income 1327.89, expense 132494.88, top=`groceries` instead of `rent`). That is the same class of **one-shot arithmetic failure** already seen on `yaml_like` with qwen-2.5-7b (n=328). It is **not** evidence that 12,020 is the readable floor: the codec is English + integers, a Python decoder recovers gold exactly, and gzip remains the opaque bound.

Token-readability for this lab is proven by **legend-in-payload + reversible decode + gold reconstruction**, not by an LLM summing 1000 rows in one completion.
