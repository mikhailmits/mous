# Token count leaderboard (GPT-5 / o200k_base)

Transactions: **1000**. Lower is cheaper context.

| rank | codec | family | GPT-5 tokens | vs pretty JSON | chars | reversible |
| --- | --- | --- | ---: | ---: | ---: | --- |
| 1 | `user_examples_tiny` | spaces | 109 | 0.2% | 323 | False |
| 2 | `img_summary_card` | images | 255 | 0.46% | 91 | False |
| 3 | `aggregates_only` | novel | 709 | 1.27% | 1594 | False |
| 4 | `img_jpeg_q8` | images | 765 | 1.38% | 30 | False |
| 5 | `img_png_full` | images | 765 | 1.38% | 32 | True |
| 6 | `img_png_sticky_grid` | images | 765 | 1.38% | 34 | True |
| 7 | `tool_views` | tools | 967 | 1.74% | 2392 | False |
| 8 | `month_cat_sums` | tools | 1306 | 2.35% | 4941 | False |
| 9 | `cat_inverted` | novel | 4058 | 7.3% | 8013 | True |
| 10 | `dsl_cat_idx` | novel | 4875 | 8.77% | 7824 | False |
| 11 | `tiny_ledger_vm` | novel | 5123 | 9.21% | 11164 | True |
| 12 | `group_cat_name_daynum` | spaces | 5125 | 9.22% | 11506 | True |
| 13 | `delta_days_by_name` | spaces | 5145 | 9.25% | 10633 | True |
| 14 | `freq_daypack` | novel | 5170 | 9.3% | 11361 | True |
| 15 | `user_examples_plus_win` | spaces | 5184 | 9.32% | 11677 | True |
| 16 | `dsl_cat_month` | novel | 5230 | 9.4% | 8905 | False |
| 17 | `base62_daypack` | novel | 5300 | 9.53% | 9881 | True |
| 18 | `daypack_names` | novel | 6016 | 10.82% | 19445 | True |
| 19 | `group_cat_name_yymmdd` | spaces | 6119 | 11.0% | 14558 | True |
| 20 | `group_by_name_yymmdd` | spaces | 6138 | 11.04% | 14895 | True |
| 21 | `rle_cat_delta` | novel | 6228 | 11.2% | 12396 | True |
| 22 | `task_rows` | novel | 6949 | 12.5% | 17340 | True |
| 23 | `lang_ideo_monthly` | languages | 7286 | 13.1% | 11226 | True |
| 24 | `dsl_month_ids` | novel | 7375 | 13.26% | 13190 | True |
| 25 | `lang_ko_ideo_monthly` | languages | 7467 | 13.43% | 11205 | True |
| 26 | `dsl_cron` | novel | 7530 | 13.54% | 20816 | True |
| 27 | `lang_ideo_monthly_hangulpack` | languages | 7616 | 13.69% | 9321 | True |
| 28 | `lang_ja_ideo_monthly` | languages | 7671 | 13.79% | 11200 | True |
| 29 | `columnar_ints_only` | novel | 7712 | 13.87% | 12679 | True |
| 30 | `month_dict_cents` | novel | 7777 | 13.98% | 13562 | True |
| 31 | `group_by_category_spaced` | spaces | 7852 | 14.12% | 24470 | True |
| 32 | `gzip_b64` | crypto | 7864 | 14.14% | 11552 | True |
| 33 | `group_by_month_spaced` | spaces | 7910 | 14.22% | 30462 | True |
| 34 | `dsl_yc1` | novel | 7960 | 14.31% | 22170 | True |
| 35 | `zlib_b85` | crypto | 8077 | 14.52% | 10813 | True |
| 36 | `lang_ideo_compact` | languages | 8219 | 14.78% | 15107 | True |
| 37 | `month_ids` | novel | 8249 | 14.83% | 19734 | True |
| 38 | `group_by_day_spaced` | spaces | 8457 | 15.21% | 30642 | True |
| 39 | `json_gzip_b64` | crypto | 8517 | 15.31% | 12432 | True |
| 40 | `omit_default_eur_main` | spaces | 8820 | 15.86% | 34323 | True |
| 41 | `lang_zh_monthly` | languages | 9290 | 16.7% | 13804 | True |
| 42 | `sha256_rows` | crypto | 10363 | 18.63% | 16999 | False |
| 43 | `lang_ideo_monthly_cjkamt` | languages | 10494 | 18.87% | 12271 | True |
| 44 | `spaced_yymmdd_cents` | spaces | 10695 | 19.23% | 42742 | True |
| 45 | `spaced_short_codes` | spaces | 11044 | 19.86% | 31784 | True |
| 46 | `amount_first_spaced` | spaces | 11637 | 20.92% | 42742 | True |
| 47 | `space_before_minus` | spaces | 11695 | 21.03% | 43742 | True |
| 48 | `two_spaces_date_amount` | spaces | 11695 | 21.03% | 43742 | True |
| 49 | `date_last_spaced` | spaces | 11912 | 21.42% | 42742 | True |
| 50 | `spaced_yymmdd` | spaces | 11925 | 21.44% | 43645 | True |
| 51 | `yaml_like` | novel | 12020 | 21.61% | 34598 | True |
| 52 | `dict_ids` | novel | 13186 | 23.71% | 19992 | True |
| 53 | `cjk_digits` | novel | 13542 | 24.35% | 17098 | True |
| 54 | `delta_dates` | novel | 14398 | 25.89% | 37777 | True |
| 55 | `spaced_cents` | spaces | 14695 | 26.42% | 46742 | True |
| 56 | `lang_hangul_pack` | languages | 15216 | 27.36% | 29148 | True |
| 57 | `line_natural` | spaces | 15925 | 28.63% | 47645 | True |
| 58 | `finance_asm` | novel | 15931 | 28.65% | 39503 | True |
| 59 | `lang_de` | languages | 16137 | 29.02% | 46936 | True |
| 60 | `lang_ru` | languages | 16330 | 29.36% | 46135 | True |
| 61 | `columnar` | novel | 16400 | 29.49% | 51780 | True |
| 62 | `lang_de_full` | languages | 16712 | 30.05% | 47730 | True |
| 63 | `split_amount_spaces` | spaces | 16925 | 30.43% | 48800 | True |
| 64 | `lang_ideo` | languages | 16980 | 30.53% | 28845 | True |
| 65 | `nbsp_field_sep` | symbols | 16984 | 30.54% | 42742 | True |
| 66 | `thin_space_field_sep` | symbols | 16984 | 30.54% | 42742 | True |
| 67 | `toon` | novel | 16984 | 30.54% | 34429 | True |
| 68 | `lang_ar` | languages | 17184 | 30.9% | 43447 | True |
| 69 | `no_spaces_at_all` | spaces | 17207 | 30.94% | 42032 | True |
| 70 | `lang_mixed_en_cjkamt` | languages | 17408 | 31.3% | 32060 | True |
| 71 | `sticky_amount_no_space` | spaces | 17534 | 31.53% | 42032 | True |
| 72 | `lang_ru_full` | languages | 17588 | 31.63% | 48515 | True |
| 73 | `lang_emoji` | languages | 17606 | 31.66% | 39947 | True |
| 74 | `lang_zh` | languages | 17993 | 32.35% | 39030 | True |
| 75 | `lang_ja` | languages | 18018 | 32.4% | 41438 | True |
| 76 | `lang_pinyin` | languages | 18121 | 32.58% | 38513 | True |
| 77 | `abbrev_vowels` | novel | 18146 | 32.63% | 36852 | True |
| 78 | `lang_hangul_digits` | languages | 18321 | 32.94% | 32062 | True |
| 79 | `lang_ko_full` | languages | 18909 | 34.0% | 32692 | True |
| 80 | `space_to_underscore` | symbols | 19207 | 34.54% | 47645 | True |
| 81 | `lang_zh_full` | languages | 19735 | 35.49% | 32340 | True |
| 82 | `space_to_slash` | symbols | 19807 | 35.62% | 47645 | True |
| 83 | `tsv` | novel | 20291 | 36.49% | 47645 | True |
| 84 | `csv` | novel | 20388 | 36.66% | 47682 | True |
| 85 | `space_to_tab` | symbols | 20855 | 37.5% | 47645 | True |
| 86 | `lang_ja_full` | languages | 20873 | 37.53% | 34225 | True |
| 87 | `double_spaces` | spaces | 20925 | 37.63% | 52645 | True |
| 88 | `space_to_comma` | symbols | 21029 | 37.81% | 47645 | True |
| 89 | `space_to_pipe` | symbols | 21272 | 38.25% | 47645 | True |
| 90 | `newline_fields` | spaces | 21539 | 38.73% | 48645 | True |
| 91 | `rot13_names` | crypto | 21901 | 39.38% | 47645 | True |
| 92 | `space_to_middle_dot` | symbols | 22168 | 39.86% | 47645 | True |
| 93 | `space_to_unit_sep` | symbols | 22214 | 39.94% | 47645 | True |
| 94 | `space_to_sentencepiece_block` | symbols | 27827 | 50.04% | 47645 | True |
| 95 | `json_compact` | baseline | 34557 | 62.14% | 85647 | True |
| 96 | `b64` | crypto | 40308 | 72.48% | 63528 | True |
| 97 | `hex` | crypto | 41473 | 74.57% | 95290 | True |
| 98 | `xor_hex` | crypto | 52522 | 94.44% | 95290 | True |
| 99 | `json_pretty` | baseline | 55614 | 100.0% | 127648 | True |

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
