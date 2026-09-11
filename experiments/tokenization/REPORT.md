# Tokenization lab report

Status: first local pass complete. Gateway quality evals and specialist codecs still running.

## Setup (done)

- Seeded a deterministic **1000-transaction** ledger (`uv run python -m experiments.tokenization.seed`, seed=42).
- API is serving it at `127.0.0.1:8000`. Live export: 1000 tx, 5 subscriptions, 16 categories, 3 accounts.
- Gold labels for the diagram tasks:
  - reports: income **90564.20**, expense **75572.82**, net **14991.38**, top spend category **rent** (22703.20)
  - optimize: best discretionary cut **shopping** (9175.33 spend, 1835.07 at −20%)
  - forecasts: naive next-month spend **2888.14** (mean of last 3 months)
- 15 tokenizers loaded, including **GPT-5 / GPT-5-mini / GPT-5.1 → tiktoken `o200k_base`**, plus cl100k, Qwen2.5, Llama 3.2, Phi-3, DeepSeek-R1-Qwen, SmolLM2, mBERT, GPT-2.

## Token-count findings (GPT-5 / o200k_base)

Pretty JSON is the wasteful control: **55,614 tokens**.

| kind | codec | GPT-5 tokens | vs pretty | readable? |
| --- | --- | ---: | ---: | --- |
| cheat / pre-aggregate | `aggregates_only` | 709 | 1.3% | yes, but not a raw encoding |
| opaque compression | `gzip_b64` | 7,863 | 14.1% | no |
| **best fair text so far** | `yaml_like` | **12,020** | **21.6%** | yes |
| dictionary + cents + day ids | `dict_ids` | 13,186 | 23.7% | yes |
| CJK digit packing | `cjk_digits` | 13,542 | 24.4% | mixed |
| natural spaced lines | `line_natural` | 15,925 | 28.6% | yes |
| glue spaces (`-50eurhahah`) | `sticky_amount_no_space` | 17,534 | 31.5% | worse |
| strip all spaces | `no_spaces_at_all` | 17,207 | 30.9% | worse than keeping spaces |
| extra spaces (`-50 eur heh`) | `split_amount_spaces` | 16,925 | 30.4% | slightly worse than natural |
| replace spaces with `▁` | `space_to_sentencepiece_block` | 27,827 | 50.0% | worse |
| compact JSON | `json_compact` | 34,557 | 62.1% | yes |
| hex / xor | `hex`, `xor_hex` | 41k–52k | 75–94% | no |

### (a) Spaces

**Do not delete spaces on GPT-5.** Sticky glue and total space removal both *increased* tokens versus a normal spaced line. BPE already likes whitespace as a boundary; gluing `-50eurhahah` creates rare pieces. Splitting to `-50 eur heh` also cost extra tokens (sign, amount, and currency became separate pieces plus more spaces).

### (b) Symbol separators

Replacing spaces with `|`, tabs, commas, middle dots, unit separators, or SentencePiece `▁` all lost to ordinary spaces. Underscore was the least-bad substitute (19,207) and still worse than `line_natural`.

### (c) Languages

German (16,137) and Russian (16,330) beat Chinese/Japanese/Arabic/emoji on this corpus because **merchant names stayed English**. Category-only translation is not enough. Full CJK packing of numbers (`cjk_digits`, 13,542) helped more than translating labels.

### (d) Encryption / compression

gzip/base64 is token-cheap (7.8k) and model-opaque. Hex, base64, XOR, ROT13 all *inflate* tokens. SHA-256 rows are short and useless. Treat gzip as a size floor, not a candidate.

### (e) Images

Placeholder text is ~11 tokens; that is a lie. OpenAI high-detail tile estimate for the tall 1000-line PNG is **765 vision tokens** (~1.4% of pretty JSON). If OCR/vision can read the strip, images beat every fair text codec on cost. Quality is unproven and is the image specialist's job. JPEG q=8 is the same tile count with worse glyphs.

### (x) Novel

Monthly YAML grouping (`yaml_like`) currently beats integer dictionaries. Combining monthly groups + integer ids + cents + short names is the obvious next attack. `toon` and `finance_asm` did not beat a plain spaced line.

## Quality bar

A codec only “wins” if GPT-5-class tokens drop **and** reports/optimize/forecasts accuracy stays near the compact-JSON baseline. `aggregates_only` and summary images are bounds, not winners.

## Quality evals (Qwen 2.5 7B via the LLM gateway)

Task-aware rescoring (reports, optimize, forecasts checked separately; expense sign ignored):

| codec | GPT-5 tokens | mean accuracy | notes |
| --- | ---: | ---: | --- |
| `aggregates_only` | 709 | **0.83** | reports 5/5, forecasts 2/2; optimize missed share-as-percent |
| `yaml_like` | 12,020 | 0.17 | guessed shopping as the cut; could not sum 1000 rows |
| `dict_ids` | 13,186 | 0.17 | same |
| `line_natural` | 15,925 | 0.17 | same |
| `gzip_b64` | 7,864 | **0.00** | hallucinated a fake 100-row budget |

**Efficiency takeaway:** stuffing 1000 raw rows into a small model destroys the three diagram tasks. The diagram's **tools** arrow is the real win: pre-aggregate via the Mous API (`/spent`, `/balance`, category rollups) and send ~700 tokens. That is faster *and* more accurate. Compact raw encodings still matter when the agent must see line items.

GPT-5 / GPT-5-mini / GPT-5-nano were probed: they spend hidden reasoning tokens. Bulk judging used Qwen. Tokenizer comparisons still use tiktoken `o200k_base` for the whole GPT-5* family.

## Next

Five grok-4.6 xhigh specialists are adding space/language/compress/image/DSL codecs. A 12-minute loop will integrate their work, re-count tokens, and re-score quality.
