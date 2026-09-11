# Token count leaderboard (GPT-5 / o200k_base)

Transactions: **1000**. Lower is cheaper context.

| rank | codec | family | GPT-5 tokens | vs pretty JSON | chars | reversible |
| --- | --- | --- | ---: | ---: | ---: | --- |
| 1 | `img_summary_card` | images | 255 | 0.46% | 91 | False |
| 2 | `aggregates_only` | novel | 709 | 1.27% | 1594 | False |
| 3 | `img_jpeg_q8` | images | 765 | 1.38% | 30 | False |
| 4 | `img_png_full` | images | 765 | 1.38% | 32 | True |
| 5 | `img_png_sticky_grid` | images | 765 | 1.38% | 34 | True |
| 6 | `gzip_b64` | crypto | 7864 | 14.14% | 11552 | True |
| 7 | `zlib_b85` | crypto | 8077 | 14.52% | 10813 | True |
| 8 | `json_gzip_b64` | crypto | 8518 | 15.32% | 12432 | True |
| 9 | `sha256_rows` | crypto | 10363 | 18.63% | 16999 | False |
| 10 | `yaml_like` | novel | 12020 | 21.61% | 34598 | True |
| 11 | `dict_ids` | novel | 13186 | 23.71% | 19992 | True |
| 12 | `cjk_digits` | novel | 13542 | 24.35% | 17098 | True |
| 13 | `delta_dates` | novel | 14398 | 25.89% | 37777 | True |
| 14 | `line_natural` | spaces | 15925 | 28.63% | 47645 | True |
| 15 | `finance_asm` | novel | 15931 | 28.65% | 39503 | True |
| 16 | `lang_de` | languages | 16137 | 29.02% | 46936 | True |
| 17 | `lang_ru` | languages | 16330 | 29.36% | 46135 | True |
| 18 | `columnar` | novel | 16400 | 29.49% | 51780 | True |
| 19 | `split_amount_spaces` | spaces | 16925 | 30.43% | 48800 | True |
| 20 | `toon` | novel | 16984 | 30.54% | 34429 | True |
| 21 | `lang_ar` | languages | 17184 | 30.9% | 43447 | True |
| 22 | `no_spaces_at_all` | spaces | 17207 | 30.94% | 42032 | True |
| 23 | `sticky_amount_no_space` | spaces | 17534 | 31.53% | 42032 | True |
| 24 | `lang_emoji` | languages | 17606 | 31.66% | 39947 | True |
| 25 | `lang_zh` | languages | 17993 | 32.35% | 39030 | True |
| 26 | `lang_ja` | languages | 18018 | 32.4% | 41438 | True |
| 27 | `abbrev_vowels` | novel | 18146 | 32.63% | 36852 | True |
| 28 | `space_to_underscore` | symbols | 19207 | 34.54% | 47645 | True |
| 29 | `space_to_slash` | symbols | 19807 | 35.62% | 47645 | True |
| 30 | `tsv` | novel | 20291 | 36.49% | 47645 | True |
| 31 | `csv` | novel | 20388 | 36.66% | 47682 | True |
| 32 | `space_to_tab` | symbols | 20855 | 37.5% | 47645 | True |
| 33 | `double_spaces` | spaces | 20925 | 37.63% | 52645 | True |
| 34 | `space_to_comma` | symbols | 21029 | 37.81% | 47645 | True |
| 35 | `space_to_pipe` | symbols | 21272 | 38.25% | 47645 | True |
| 36 | `newline_fields` | spaces | 21539 | 38.73% | 48645 | True |
| 37 | `rot13_names` | crypto | 21901 | 39.38% | 47645 | True |
| 38 | `space_to_middle_dot` | symbols | 22168 | 39.86% | 47645 | True |
| 39 | `space_to_unit_sep` | symbols | 22214 | 39.94% | 47645 | True |
| 40 | `space_to_sentencepiece_block` | symbols | 27827 | 50.04% | 47645 | True |
| 41 | `json_compact` | baseline | 34557 | 62.14% | 85647 | True |
| 42 | `b64` | crypto | 40308 | 72.48% | 63528 | True |
| 43 | `hex` | crypto | 41473 | 74.57% | 95290 | True |
| 44 | `xor_hex` | crypto | 52522 | 94.44% | 95290 | True |
| 45 | `json_pretty` | baseline | 55614 | 100.0% | 127648 | True |

## Tokenizer inventory

- `openai-gpt-5` — OpenAI. GPT-5* family. tiktoken maps gpt-5 prefix to o200k_base. encoding=o200k_base
- `openai-gpt-5-mini` — OpenAI. GPT-5 mini. Same o200k_base prefix map as gpt-5*. encoding=o200k_base
- `openai-gpt-5.1` — OpenAI. gpt-5.1 also matches the gpt-5 prefix → o200k_base. encoding=o200k_base
- `openai-o200k_base` — OpenAI. Raw o200k_base used by GPT-4o, GPT-4.1, GPT-5*, o-series.
- `openai-cl100k_base` — OpenAI. GPT-4 / GPT-3.5-turbo tokenizer.
- `openai-p50k_base` — OpenAI. Codex / davinci-002 era.
- `openai-r50k_base` — OpenAI. GPT-2 / GPT-3 base BPE.
- `openai-o200k_harmony` — OpenAI. Harmony chat tokens used by gpt-oss; related GPT-5-era lineage.
- `qwen2.5` — Qwen/Qwen2.5-0.5B. Alibaba Qwen 2.5 (also used by many Qwen chat models)
- `llama3.2` — unsloth/Llama-3.2-1B-Instruct. Meta Llama 3.2 via Unsloth tokenizer files
- `phi-3-mini` — microsoft/Phi-3-mini-4k-instruct. Microsoft Phi-3
- `deepseek-r1-qwen` — deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B. DeepSeek R1 distill (Qwen vocab)
- `smollm2` — HuggingFaceTB/SmolLM2-135M. HuggingFace SmolLM2
- `mbert` — google-bert/bert-base-multilingual-cased. mBERT WordPiece, contrast tokenizer
- `gpt2` — openai-community/gpt2. GPT-2 BPE (r50k-class)
