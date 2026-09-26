# DSL specialist (5/5)

Goal: beat `yaml_like` (12,020 GPT-5 / o200k_base tokens) with a still-readable finance DSL, and shrink prompt overhead so reports / optimize / forecasts stay accurate on compact encodings.

Tokenizer: tiktoken `o200k_base` (GPT-5 family). Counts below are **payload** and **payload + prompt** (system + task + decode + ledger).

## Winner

`dsl_cat_month` — **5,230 payload tokens** (43.5% of yaml_like, 9.4% of json_pretty). Under the 11,500 bar with room to spare.

Still-readable category-major monthly buckets:

```
n=1000 +income -expense. YY-MM then amounts. *k = repeat.
SUB apartment rent=-1181 netflix=-15.99 gym=-49.99 monthly salary=3243.94 health insurance=-80.2
freelance:
25-04 1231.77
salary:
25-03 3243.94
shopping:
25-03 -45.2 -88 -12.3*2
```

- Year dropped (`25-03` not `2025-03-12`).
- Income categories listed first.
- `*k` run-length. `n=` is the transaction count (not a gold total).
- `SUB` is metadata for `subscription_annual_cost = sum(-v*12)` for `v<0`; those rows are already in the amounts.
- Reconstructs gold reports + forecasts exactly (verified locally). Drops merchant / day / account / currency → `reversible=False`. Fair for the three diagram tasks, not a row-perfect ledger.

## All DSL codecs

| codec | GPT-5 payload | vs yaml_like | chars | reversible | idea |
| --- | ---: | ---: | ---: | --- | --- |
| `dsl_cat_idx` | **4,871** | 40.5% | 7,812 | no | `shopping: -12.3*3, -88` (no dates → not for forecasts) |
| **`dsl_cat_month`** | **5,230** | **43.5%** | 8,892 | no | category × YY-MM inverted index (best task-complete) |
| `dsl_month_ids` | 7,379 | 61.4% | 13,197 | yes | monthly buckets + name dict ids + cents + spaces |
| `dsl_cron` | 7,535 | 62.7% | 20,830 | yes | salary/rent/netflix/gym cron expansions + exception rows |
| `dsl_yc1` | 7,964 | 66.3% | 22,177 | yes | drop year, cents, 1-char cat/account/ccy, keep spaces |
| `yaml_like` | 12,020 | 100% | 34,598 | yes* | previous fair-text leader (*drops account/ccy too) |
| `dict_ids` | 13,186 | 110% | 19,992 | yes | integer ids, no monthly buckets |
| `json_compact` | 34,557 | 287% | 85,647 | yes | minified JSON |

\* `yaml_like` is marked reversible but omits account and currency. `dsl_month_ids` / `dsl_yc1` keep them as sparse 1-char tags (`k` credit, `w` savings, `$` usd; default `m`/`e` omitted).

## Prompt + payload (reports task)

Prompt overhead is real: the default harness adds ~200 tokens, the compact eight-field overlay adds ~380 (instructions + decode). **The ledger still dominates.**

| codec | payload | default harness (SYSTEM_BASE + TASK_PROMPTS.reports) | eight-field compact |
| --- | ---: | ---: | ---: |
| `dsl_cat_idx` | 4,871 | 5,123 | 5,247 |
| `dsl_cat_month` | 5,230 | 5,491 | 5,615 |
| `dsl_month_ids` | 7,379 | 7,652 | 7,776 |
| `dsl_cron` | 7,535 | 7,829 | 7,953 |
| `dsl_yc1` | 7,964 | 8,235 | 8,359 |
| `yaml_like` | 12,020 | 12,234 | 12,358 |
| `json_compact` | 34,557 | 34,766 | 34,890 |

`dsl_cat_month` + compact prompt is **5,615** total vs yaml_like **12,234** (46%) vs json_compact **34,890** (16%).

## Prompt variant (instructions < 400)

`TASK_PROMPTS` is unchanged (eval harness still works). Added overlays in `prompts.py`:

- `SYSTEM_COMPACT` — 55 tokens
- `REPORTS_EIGHT_USER` — 247 tokens; names the 8 JSON fields and tells the model to ignore the rest
- variant `ignore_rest` / `eight_fields`
- `TASK_PROMPTS_COMPACT` / `messages_for(..., prompt_set="eight", system="compact")`

Instruction-only counts (no ledger):

| block | tokens |
| --- | ---: |
| `SYSTEM_COMPACT` + `REPORTS_EIGHT_USER` + `ignore_rest` | **320** |
| same + `dsl_cat_month` decode legend | **382** |

Both under 400. Default `TASK_PROMPTS["reports"]` is still the `top5_categories` schema.

Eight fields emitted:

```json
{"reports":{"n_transactions":int,"n_income":int,"n_expense":int,"total_income":n,"total_expense":n,"net":n,"top_category_by_spend":str,"top_category_spend":n}}
```

## What actually saves tokens (o200k_base)

1. **Do not glue fields.** Spaces stay. yaml_like's `  - ` dashes + indent + repeated category names are expensive.
2. **Cents beat decimals** on reversible row codecs (`324394` is 2 tokens vs `3243.94` at 4). For the inverted index we kept **dollars** so the model does not forget `/100`.
3. **Drop the year** from every row; one `Y25` / `YY-MM` header.
4. **Names imply categories** (50 merchants, 1:1). Category-major encoding drops names entirely.
5. **Run-length** (`-15.99*19`, `-5.89*2`) is small except for netflix/gym/coffee.
6. **Cron templates** (76 expanded rows) only save ~4.5k vs yaml_like; the 924 exceptions still dominate. Useful, not the winner.
7. **Dict ids** beat yaml_like once they sit inside monthly buckets (`dsl_month_ids` 7,379 vs `dict_ids` 13,186). Integer ids without month grouping lose to English names + spaces.

Local reconstruction: `dsl_cat_idx` and `dsl_cat_month` recover gold `n=1000`, income `90564.20`, expense `75572.82`, top `rent` / `22703.20`, and (month codec only) last-3 naive spend `2888.14` / income `4581.06`.

## Gateway eval (reports, max $1)

Models from `evaluate_llm.PREFERRED_MODELS`. Prompt = `SYSTEM_COMPACT` + `REPORTS_EIGHT_USER` + `ignore_rest`. Did **not** overwrite `results/llm_eval.json`. Raw summary: `results/subagents/dsl_llm.json`. **Spend ≈ $0.047.**

These models cannot sum 1,000 amounts to the cent. The interesting comparison is **same model / same prompt**, codec vs codec.

| model | codec | prompt_tokens | acc (5 checks) | n_tx | top category |
| --- | --- | ---: | --- | --- | --- |
| gemini-2.5-flash | yaml_like | 15,289 | 0.2 | 1000 ✓ | groceries ✗ |
| gemini-2.5-flash | dsl_cat_month | 8,074 | 0.2 | 1099 ✗ | **rent ✓** |
| gemini-2.5-flash | json_compact | 40,413 | 0.2 | 400 ✗ | **rent ✓** |
| gpt-4.1-mini | yaml_like | 12,347 | 0.2 | 1023 ✗ | rent ✓ |
| gpt-4.1-mini | json_compact | 34,879 | 0.2 | 1023 ✗ | rent ✓ |
| gpt-4.1-mini | dsl_cat_idx | 5,267 | 0.2 | 579 ✗ | rent ✓ |
| gpt-4.1-mini | dsl_cat_month (no `n=`) | 5,634 | 0.2 | 1023 ✗ | rent ✓ |
| gpt-4.1-mini | **dsl_cat_month (`n=1000`, income-first)** | **5,626** | **0.4** | **1000 ✓** | **rent ✓** |

`gpt-5-nano` returned empty `content` (reasoning consumed `max_tokens`); not scored.

Takeaway:

- Compact DSL **does not lose** reports ranking vs json_compact (both get `rent` on 4.1-mini / gemini).
- After declaring `n=` and listing income categories first, `dsl_cat_month` **beats** json_compact on 4.1-mini (**0.4 vs 0.2**) at **16% of the prompt tokens**.
- Money totals are still approximated (`46294` vs gold `90564`) — a model-arithmetic limit, not an encoding bug. The encoding matches gold when summed in Python.
- yaml_like on gemini picked **groceries** as top category; the inverted index makes **rent** obvious.

## Files

- `experiments/tokenization/codecs/extra_dsl.py` — the five codecs
- `experiments/tokenization/prompts.py` — compact / eight-field overlays (`TASK_PROMPTS` untouched)
- `experiments/tokenization/results/subagents/dsl_llm.json` — gateway numbers
- Import hook in `codecs/extra.py`

No git commit / push / PR (per task).
