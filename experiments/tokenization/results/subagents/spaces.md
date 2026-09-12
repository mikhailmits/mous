# Spaces specialist — GPT-5 / o200k_base

Goal: beat `line_natural` (**15,925** tokens) with **new reversible** encodings that a human can still parse into transactions. Ordinary ASCII spaces are kept unless a measurement showed a win.

Counts are tiktoken `o200k_base` (GPT-5 / GPT-5-mini / GPT-5.1). Official run: `uv run python -m experiments.tokenization.run tokens --family spaces,symbols`. Codecs live in `experiments/tokenization/codecs/extra_spaces.py`.

## Winner

**`group_cat_name_daynum` = 5,125 GPT-5 tokens** (−10,800 vs `line_natural`, 32.2% of the natural line). Reversible (round-trip of all 1,000 rows matched gold fields). Human-readable with the one-line legend:

```
D=days since 2025-01-01 V=cents default ccy=eur account=main
 groceries
 bio company
86 -1981
```

means: category `groceries`, merchant `bio company`, date `2025-01-01 + 86d` = `2025-03-28`, value `-19.81`, currency `eur`, account `main`. Non-default `usd` / `credit` / `savings` are appended on that row.

A more “report-shaped” sibling, **`group_cat_name_yymmdd` (6,119)**, keeps calendar `YYMMDD` instead of day numbers. The flat, fully explicit sibling **`spaced_yymmdd_cents` (10,695)** keeps one spaced line per txn with every field written out.

All three are new, reversible, and under 15,000.

## Table (vs `line_natural` = 15,925)

| codec | gpt5 tokens | vs line_natural | reversible | why it won / lost |
| --- | ---: | ---: | --- | --- |
| `group_cat_name_daynum` | **5125** | **−10800** | yes | Category then merchant headers (leading space so BPE uses ` groceries` / ` bio company`); rows are `D cents` with ASCII spaces; default eur/main omitted. Largest fair win. |
| `delta_days_by_name` | 5145 | −10780 | yes | Merchant groups; first date is days since 2025-01-01, later rows are day deltas. Almost as cheap; slightly harder to scan than absolute day numbers. |
| `user_examples_plus_win` | 5184 | −10741 | yes | Sticky/split user strings prepended to the winning ledger. +59 tokens of demo overhead; still a full reversible encoding. |
| `group_cat_name_yymmdd` | 6119 | −9806 | yes | Same grouping, but `YYMMDD` (2 tokens) instead of day-number (usually 1). Best grouped form if you want dates that look like dates. |
| `group_by_name_yymmdd` | 6138 | −9787 | yes | Merchant groups with category on the header. Almost identical to cat→name; repeating the category word on every merchant costs a few tokens. |
| `group_by_category_spaced` | 7852 | −8073 | yes | Category written once; each row still has date+name+cents. Names still repeat inside the category (50 merchants, not 16 labels). |
| `group_by_month_spaced` | 7910 | −8015 | yes | `YYYY-MM:` then `DD name cents cat`. Same idea as `yaml_like` but cents + omitted eur/main and **keeps account/currency when they differ** (fair reversible). |
| `group_by_day_spaced` | 8457 | −7468 | yes | Date header once per distinct day (473 days). Helps, but there are many singleton days so headers do not amortize as well as 50 names / 16 cats. |
| `omit_default_eur_main` | 8820 | −7105 | yes | Flat `YYMMDD name cents cat`; `eur`/`main` dropped unless they differ. Saves ~1 token × ~900 default-account rows plus ~1 token × 991 eur rows. |
| `spaced_yymmdd_cents` | 10695 | −5230 | yes | **Additive win:** YYMMDD (−4,000) + cents (−1,230) on an otherwise natural spaced line. Most readable non-grouped encoding. |
| `spaced_short_codes` | 11044 | −4881 | yes | 1-letter accounts, 3-letter cats, 1-letter ccy **while keeping spaces**. **Lost to full words** (`spaced_yymmdd_cents` 10,695): ` main` / ` groceries` are already 1 token; the legend is extra cost. |
| `amount_first_spaced` | 11637 | −4288 | yes | Cents first. Loses the leading-space merge on the name (`bakery` splits to `bak`+`ery` at start-of-field after a number). Date-first is better. |
| `space_before_minus` | 11695 | −4230 | yes | Amount-first **plus** a leading space so BPE sees ` -50` not `-50`. Same token count as two-spaces; **lost to date-first**. ` -` vs `-` is a wash (both 1 token). |
| `two_spaces_date_amount` | 11695 | −4230 | yes | Two ASCII spaces only between YYMMDD and name. Extra space is almost always an extra token; BPE did not need a wider gap there. |
| `date_last_spaced` | 11912 | −4013 | yes | Name at start of line. Names without a leading space tokenize worse (` bakery coffee` = 2, `bakery coffee` = 3). |
| `spaced_yymmdd` | 11925 | −4000 | yes | **Only** ISO → YYMMDD. `2025-03-01` is 6 tokens (`202` `5` `-` `03` `-` `01`); `250301` is 2 (`250` `301`). Exactly −4 per row. |
| `spaced_cents` | 14695 | −1230 | yes | **Only** float → integer cents. Decimal point and fractional pieces go away (` -` `6` `.` `63` → ` -` `663`). |
| `line_natural` | 15925 | 0 | yes | Control: `2026-01-02 groceries -23.10 eur main food`. |
| `nbsp_field_sep` | 16984 | **+1059** | yes | Same payload as `spaced_yymmdd_cents` with U+00A0. **Lost.** NBSP is a rare token and kills the ` word` leading-space merges. |
| `thin_space_field_sep` | 16984 | **+1059** | yes | U+2009 thin space, same loss as NBSP. Do not replace ASCII spaces. |
| `split_amount_spaces` | 16925 | +1000 | yes | Prior finding: extra spaces around sign/amount/currency. Reconfirmed. |
| `no_spaces_at_all` | 17207 | +1282 | yes | Prior finding: deleting spaces **increases** GPT-5 tokens. Reconfirmed. |
| `sticky_amount_no_space` | 17534 | +1609 | yes | Prior finding: `-50eurhahah` glue **increases** tokens. Reconfirmed. |
| `space_to_underscore` | 19207 | +3282 | yes | Best of the “replace every space with a symbol” family; still worse than ASCII space. |
| `space_to_sentencepiece_block` | 27827 | +11902 | yes | Worst symbol swap (`▁`). Reconfirmed. |
| `user_examples_tiny` | 109 | n/a | **no** | Exactly the user before/after strings plus 3 real rows. Demo only — **not** a 1,000-row encoding. |

## What actually moved the needle (spaces kept)

1. **Dates.** ISO-8601 is six o200k pieces because of the century split (`202`+`5`) and two dash tokens. `YYMMDD` is two pieces. This is a free −4,000 on this corpus.
2. **Cents.** The `.` in `-19.81` is a token, and the integer/fraction often split. Integer cents drop about −1.23 tokens/row on average.
3. **Grouping for BPE, not new separators.** 50 merchant names and 16 categories already have leading-space whole-word tokens (` coffee` is 1 token). Writing the label once is both shorter *and* more compressible. Putting a leading space on the **header** (` groceries`) is cheaper than starting the line with the bare word.
4. **Defaults.** 991× `eur` and 901× `main` are one token each. Omitting them with a legend is fair and reversible.

## What did not help (measured, not assumed)

- **Deleting spaces / sticky glue / extra amount spaces** — still worse than `line_natural`.
- **Replacing spaces** with `|`, tab, comma, `·`, `_`, `/`, unit-sep, `▁`, **NBSP, or thin space** — all lost. NBSP/thin on the *already compressed* `spaced_yymmdd_cents` payload jumped 10,695 → 16,984.
- **1-letter accounts / 3-letter cats while keeping spaces** — English category and account words are already single tokens after a space. Short codes do not save, and the legend costs.
- **Field reordering** (amount first, date last) — date-first is best because then the name is a leading-space word, not a start-of-line fragment.
- **Two spaces “only where BPE merges badly”** — the extra space was always an extra token on date/name and date/amount. No measured merge bug to patch with a second space.
- **Space-before-minus** (` -50` vs `-50`) — both forms are one sign token (` -` vs `-`). Leading space on an amount-first line added 1,000 tokens (one per row) vs the same fields without it.

## Reversibility

`group_cat_name_daynum` reconstructed all 1,000 transactions with zero field mismatches (`occurred_on`, `name`, `value` to 2 decimals, `currency`, `account`, `category`). Legend:

- `D` = integer days since `2025-01-01`
- `V` = integer cents (signed; negative = expense)
- missing ccy/account → `eur` / `main`
- section headers: ` <category>` then ` <merchant>` (leading ASCII space)

`spaced_yymmdd_cents` is trivially reversible: `YYMMDD name cents ccy account category`.

## Quality / readability

For reports (totals, top categories, monthly series), optimize (discretionary cuts), and forecasts (last-3-month means):

- Grouped encodings still list every txn amount and a recoverable date, so monthly series and category totals are computable.
- `group_cat_name_yymmdd` is the friendliest grouped form for a human writing a monthly report (no epoch arithmetic).
- `spaced_yymmdd_cents` is the friendliest flat form (one line = one txn, all fields explicit).

Optional gateway check (one model, reports task only, winning codec): `qwen/qwen-2.5-7b-instruct` scored **0/5** on gold reports. It counted ~108 rows (first category only), treated cents as whole currency units, and named a merchant as a category. That is a 7B aggregation failure, not evidence that the encoding is unparseable — the deterministic round-trip succeeded. No further gateway calls (budget). Raw: `results/subagents/spaces_llm.json`.

## Files

- Codecs: `experiments/tokenization/codecs/extra_spaces.py` (family `spaces` except NBSP/thin → `symbols`)
- This note: `experiments/tokenization/results/subagents/spaces.md`
- Family-only dump: `results/subagents/spaces_token_counts.json`
