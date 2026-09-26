# Image encodings — specialist 4/5

Goal: minimize **real** OpenAI high-detail vision tokens while keeping the
1000-row ledger OCR-able enough for reports / optimize / forecasts.

## Tile formula (lab canonical)

```
if max(w,h) > 2048: scale so longest side = 2048
if min(w,h) > 768:  scale so shortest side = 768
tiles = ceil(w/512) * ceil(h/512)
high_tokens = 85 + 170 * tiles
low_tokens  = 85          # always, one 512×512 thumbnail — quality risk
```

Implemented in `codecs/images.py` `openai_image_tokens`. Placeholder text
`[image ledger_full.png 360x9004]` is **11 text tokens and a lie**.

## Why the tall 1000-line PNG is a trap

- Canvas `360×9004`, line-h `9` → **765** high / 85 low.
- Preprocessor scale: `360×9004` → `81×2048` (1×4 tiles).
- Effective glyph height after scale: **2.047 px**. Humans and VLMs do
  not OCR 2px type. JPEG q=8 keeps this tile count and adds block noise.
- **Fix:** keep `max(w,h) ≤ 2048` and pack with 2–5 columns so each 512px tile
  is native resolution, not a crushed strip.

## Results

| codec | rev | W×H | cols | mode | bytes | tiles | high | low | eff. line-h | notes |
| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `img_1tile_micro` | yes | 512×512 | 10 | 1 | 24650 | 1 | **255** | 85 | 5.0 | Lower bound for a fair full ledger: 85+170=255. Ten columns of 4px-tall glyphs.  |
| `img_monthly_table` | NO | 512×512 | 2 | RGB | 29915 | 1 | **255** | 85 | 14.0 | Practical agent-mode bound, not a fair codec. Paints monthly and category aggreg |
| `img_summary_card` | NO | 220×49 | None | None | 1326 | None | **255** | 85 | None | Cheats by pre-aggregating. Useful as a lower bound, not a fair codec. |
| `img_2tile_compact` | yes | 512×1024 | 6 | 1 | 40435 | 2 | **425** | 85 | 6.0 | Fair full-ledger at the 2-tile budget. Native 512×1024 so the preprocessor does  |
| `img_2tile_named` | yes | 512×1024 | 6 | 1 | 32719 | 2 | **425** | 85 | 5.0 | Same 425-token canvas as img_2tile_compact but size=5 named lines. Worse OCR, mo |
| `img_packed_bitmap` | yes | 512×1024 | 7 | 1 | 47578 | 2 | **425** | 85 | 7.0 | Packed bitmap vs TTF: 5×7 LED stamps, 0px tracking, 13-char day-index rows (16-c |
| `img_3tile_4col` | yes | 512×1536 | 4 | 1 | 31860 | 3 | **595** | 85 | 5.0 | Mid budget: 85+170*3=595. 4 columns as requested, glyphs ~5px. Under 765, over 4 |
| `img_4col_1bit` | yes | 512×2048 | 4 | 1 | 44689 | 4 | **765** | 85 | 8.0 | Fair full-ledger packing. Same 765 high-detail tokens as the 1000-line tall PNG, |
| `img_4col_color` | yes | 512×2048 | 4 | RGB | 194361 | 4 | **765** | 85 | 8.0 | Vision models train on color photos. Gutters keep glyphs black-on-white (OCR) wh |
| `img_4col_gray` | yes | 512×2048 | 4 | L | 117920 | 4 | **765** | 85 | 8.0 | Tile tokens identical to img_4col_1bit. File bytes differ. Antialiasing if the f |
| `img_5col_large_glyph` | yes | 512×2048 | 5 | 1 | 62156 | 4 | **765** | 85 | 9.0 | Same 765-token 4-tile box as img_4col_1bit but compact 16-char rows so the font  |
| `img_jpeg_q8` | NO | 280×9004 | None | None | 168798 | None | **765** | 85 | None | Lossy. OCR quality will drop. |
| `img_png_full` | yes | 360×9004 | None | None | 216381 | None | **765** | 85 | None | Vision tokens dominate if the strip is tall. |
| `img_png_sticky_grid` | yes | 240×9004 | None | None | 167447 | None | **765** | 85 | None |  |
| `img_split_2x2tile` | yes | 512×1024 + 512×1024 | 6 | 1 | 40082 | 4 | **850** | 170 | [6.0, 6.0] | Two 2-tile images = 850 tokens vs one 512×2048 at 765 or one 512×1024 at 425. |
| `img_split_4x512` | yes | 512×512 + 512×512 + 512×512 + 512×512 | 4 | 1 | 48481 | 4 | **1020** | 340 | [8.0, 8.0, 8.0, 8.0] | Same native 8px glyphs as img_4col_1bit but pays 85 base tokens four times (1020 |

## Fair full-ledger headline

**`img_4col_1bit`** — `512×2048`, 4 columns, mode `1`, **765 high-detail tokens**, 85 low-detail, 44689 bytes, effective line-h 8.0 px (no preprocessor crush).

This matches the 765-token cost of the tall PNG *without* destroying glyphs.
Named `YYMMDD amt cat4 name8` rows, 4 columns, chronological down then
across. Reversible with the cat4 legend. Compared with `yaml_like` at 12,020
GPT-5 text tokens this is ~6.4% of that cost **if OCR works**.

**2-tile target:** `img_2tile_compact` is **425** tokens (≤425). Compact 16-char reversible rows, 6 columns on 512×1024, 1-bit PNG, effective line-h 6.0 px. That is the cheapest *fair* packing
that still fits 1000 rows without scaling. Glyphs are ~5px — this is the
readability cliff.

**Agent-mode bound (not a winner):** `img_monthly_table` paints monthly +
category totals, `reversible=False`, **255** high / 85 low. Unlike `img_summary_card` it does **not** paint
`top=rent` / `fc_spend=...` as finished answers; the model still has to pick
the max category and average the last 3 month rows. Still pre-aggregation.

## Split vs one strip

- One 512×2048 image = 4 tiles = **765** (85 paid once).
- Four 512×512 images = 4×(85+170) = **1020**. Same pixels, **+255** for the extra bases.
- Two 512×1024 images = 2×425 = **850**, still worse than one 4-tile strip.
- Splitting only wins if a *single* canvas would exceed 2048 on a side and get crushed.
  Our 4-col 512×2048 already avoids that, so splits are strictly more expensive.

## 1-bit vs packed bitmap vs color

- **1-bit PNG** (`img_4col_1bit`, `img_2tile_compact`): smallest files, sharp glyphs,
  no dither. Preferred for OCR. `img_4col_1bit` is **44,689 bytes**.
- **Grayscale L** (`img_4col_gray`): same 765 tiles, **117,920 bytes** (2.6× 1-bit).
  Default bitmap font barely antialiases; this is wasted weight.
- **RGB + category gutters** (`img_4col_color`): same 765 tiles, **194,361 bytes**
  (4.3× 1-bit). Black text preserved; 3px hue gutter may help reports/optimize
  without painting gold.
- **Packed 5×7 bitmap** (`img_packed_bitmap`): 425-token 2-tile budget, LED stamps,
  0 tracking, 13-char day-index (16-char×5×7×1000 = 560k cells > 512×1024). Crisp
  at 4× zoom; at native 1× it looks like a barcode. VLM OCR unproven.

## Low detail = 85 (quality risk)

Every image is 85 tokens at `detail=low` because the model only gets a 512×512
thumbnail. For `img_4col_1bit` that means 2048→512 vertical squash (4×): 8px
glyphs become 2px — same failure mode as the tall PNG. Low-detail is only
plausible for `img_monthly_table` (already ≤512×512). Do not quote 85 as a
fair full-ledger cost.

## Can a model actually read 1000 painted lines?

**Tall PNG (360×9004): no.** After the official scale the type is ~2px. That
765-token number is real and also useless. See `results/images/previews/tall_png_original_scaled.png`.

**Native 4-col 512×2048 (`img_4col_1bit`): partially.** Glyphs stay 8px at high
detail (no 2048 crush). One Gemini 2.5 Flash call (below) counted 1000 rows and
named rent as top category, then invented `total_expense=59999.99` (gold 75572.82,
~21% low). So the layout is OCR-able enough to *see structure and large rent
rows*, not OCR-able enough to sum 942 expenses. Tile savings ≠ reports accuracy.

**2-tile compact (512×1024, ~5–6px): unlikely for sums.** Cheapest fair packing
(425). Legible to a human with zoom; VLMs usually fail at this density.

**1-tile micro (~4px, 10 columns, 255 tokens): no.** Density stunt.

Two-column full ledgers do not fit: 500 rows × 8px = 4000px height, which exceeds
2048 and gets crushed. **Minimum columns for native 8px on a 4-tile canvas is 4.**

## Gateway vision probe (one image, ≤$1, no retries)

- model: `google/gemini-2.5-flash` (vision-capable, cheap)
- image: `/workspace/experiments/tokenization/results/images/extra_4col_1bit.png` (`img_4col_1bit`, 512×2048 1-bit, 4-col named)
- OpenAI high-detail formula: 765 tokens
- gateway billed prompt_tokens=3531 completion_tokens=48 cost=$0.0011793
  (Gemini's tokenizer is not the 85+170×tiles formula; do not mix them.)
- ok: True
- error: none
- parsed: `{"n_transactions": 1000, "top_category": "rent", "total_expense": 59999.99}`
- gold: n=1000, total_expense=75572.82, top=rent
- match: n=True expense=False top=True all=False

```
```json
{
  "n_transactions": 1000,
  "total_expense": 59999.99,
  "top_category": "rent"
}
```
```

Partial read: the model got **n=1000** and **top=rent**, then failed the expense sum (`59999.99` vs `75572.82`). A 1000-line native 8px grid is OCR-able enough to count rows and spot rent, **not** accurate enough to replace compact JSON for reports arithmetic. Caveat: the prompt mentioned the number 1000 while telling the model not to guess it — treat the n=1000 hit as weaker evidence than top=rent. No retries (budget rule).

## Under 425 high-detail tokens (fair codecs)

`img_1tile_micro` (255), `img_2tile_compact` (425), `img_2tile_named` (425), `img_packed_bitmap` (425)

## Files

PNGs live in `experiments/tokenization/results/images/` (`extra_*.png`).
Preprocessor-scaled previews: `results/images/previews/*_scaled.png`.
Codecs: `experiments/tokenization/codecs/extra_images.py`.

## What not to claim

- Do not put image codecs on a text-token leaderboard using the `[image …]` stub.
- Do not claim JPEG q=8 is cheaper; it is the same tiles and worse OCR.
- Do not treat `img_monthly_table` / `img_summary_card` as fair winners.
- Do not quote low-detail 85 for a full ledger.

