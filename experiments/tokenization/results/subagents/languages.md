# Languages specialist — full-ledger re-scripting

Measured with `tiktoken.get_encoding("o200k_base")` on the **1000-row** `corpus/bundle.json`.
No LLM gateway calls (spend $0).

**Controls:** `lang_de` (category-only German) = **16,137**. `yaml_like` = **12,020**.
**Success bar:** reversible multilingual codec **≤ 14,000** with an in-payload English gold legend.

**Winner:** `lang_ideo_monthly` = **7,273** GPT-5 tokens (45% of German, 61% of yaml_like).
Co-leader `lang_ko_ideo_monthly` = **7,240**. Roundtrip decode of all 1000 rows succeeds.

Codecs live in `experiments/tokenization/codecs/extra_lang.py`.

## Why category-only translation lost

`lang_zh` / `lang_ja` / `lang_ar` / `lang_emoji` lost to German because **merchant names stayed English** (`lidl`, `netflix`, `weekly groceries`, …). Category words are only ~1,450 of ~15,925 `line_natural` tokens. Names are ~2,090. **ISO dates are 6,000** and float amounts ~3,995. Translating labels without re-scripting dates/amounts cannot beat 14k.

Full ISO-line dictionaries (`lang_de_full` 16,712, `lang_zh_full` 19,735) **got worse**: the legend costs a few hundred tokens, and 2–4 character translations are not cheaper than English BPE pieces. Packing **dates + cents** is the actual win; script choice is the second-order effect.

## Token table (GPT-5 / o200k_base)

| codec | tokens | vs `lang_de` | vs `yaml_like` | layout | recoverable? |
| --- | ---: | ---: | ---: | --- | --- |
| **`lang_ko_ideo_monthly`** | **7,240** | −55% | −40% | YYMM + 1 Hangul + cents | **high** with legend |
| **`lang_ideo_monthly`** | **7,273** | −55% | −39% | YYMM + 1 CJK + cents | **high** (mnemonic + legend) |
| **`lang_ja_ideo_monthly`** | **7,281** | −55% | −39% | YYMM + 1 kanji/kana + cents | **high** with legend |
| `lang_ideo_monthly_hangulpack` | 7,603 | −53% | −37% | same + base-80 Hangul cents | **low** (arithmetic) |
| `lang_ideo_compact` | 8,210 | −49% | −32% | YYMMDD glued, no month header | **high** with legend |
| `lang_ideo_monthly_spaced` | 8,829 | −45% | −27% | spaces between fields | **high** (easiest for models) |
| `lang_zh_monthly` | 9,203 | −43% | −23% | real 2-char Chinese words | **high** even bilingual-only |
| `lang_pinyin_monthly` | 9,218 | −43% | −23% | Latin pinyin + cents | **medium** (collisions) |
| `lang_ko_monthly` | 9,958 | −38% | −17% | real Korean words | **high** bilingual |
| `lang_de_monthly` | 10,031 | −38% | −17% | real German words | **high** bilingual |
| `lang_ideo_monthly_cjkamt` | 10,481 | −35% | −13% | CJK digits instead of cents | **high**, but digits cost more |
| `lang_ja_monthly` | 10,996 | −32% | −9% | real Japanese words | **high** bilingual |
| `lang_ru_monthly` | 11,517 | −29% | −4% | real Russian words | **high** bilingual |
| `lang_hangul_pack` | 15,216 | −6% | +27% | ISO date, English names, packed V | amounts **low** |
| `lang_de` (old) | 16,137 | 0 | +34% | ISO, English names, DE cats | high |
| `lang_ru` (old) | 16,330 | +1% | +36% | ISO, English names, RU cats | high |
| `lang_hangul_digits` | 16,395 | +2% | +36% | ISO + 영일… digit amounts | **high** |
| `lang_de_full` | 16,712 | +4% | +39% | ISO + full DE names | high, longer compounds |
| `lang_ideo` | 16,980 | +5% | +41% | ISO + 1 CJK, float amounts | high |
| `lang_ar` (old) | 17,184 | +6% | +43% | ISO, English names | high |
| `lang_mixed_en_cjkamt` | 17,408 | +8% | +45% | English names, CJK amounts | mixed |
| `lang_ru_full` | 17,588 | +9% | +46% | ISO + full RU names | high |
| `lang_emoji` (old) | 17,606 | +9% | +46% | ISO, English names | medium |
| `lang_zh` (old) | 17,993 | +12% | +50% | ISO, partial ZH names | high |
| `lang_ja` (old) | 18,018 | +12% | +50% | ISO, English names | high |
| `lang_pinyin` | 18,121 | +12% | +51% | ISO + pinyin | medium |
| `lang_ko_full` | 18,909 | +17% | +57% | ISO + full KO names | high |
| `lang_zh_full` | 19,735 | +22% | +64% | ISO + 2-char ZH names | high |
| `lang_ja_full` | 20,873 | +29% | +74% | ISO + JA names/kana | high |

Thirteen reversible multilingual codecs beat **both** German-label encoding **and** `yaml_like`, and they keep currency/account (yaml_like dropped both). Default `eur`/`main` are omitted; `$` / `储` / `贷` flags restore the 9 USD and 99 non-main rows.

## What o200k actually likes

| encoding | tokens / typical amount | note |
| --- | --- | --- |
| ASCII signed cents (`-118100`) | **2.77 avg** | best number encoding found |
| 2× 1-token CJK packed | 2.00 | needs a 2,515-char alphabet (~2.5k legend tokens) — net loss |
| 3× Hangul base-80 (`HANGUL_80`) | 3.00 | alphabet in legend is cheap (~80); still slightly worse than cents |
| CJK digits `負三二四三點九四` | ~4.9 | 1 token/char, **loses** to ASCII |
| Hangul digits `음일이삼…` | ~4.9 | same |
| Fullwidth digits | worse | extra token/char |
| Rare CJK / Hangul (uniform codepoints) | 2–3 / char | **do not pack into rare glyphs** |

Common finance hanzi (`租购食餐交薪订娱医水电旅咖保教礼`) are **1 token**. Uniform-sampled CJK URO is ~1.6 tokens/char. The ideograph table is restricted to measured 1-token glyphs.

ISO `2025-03-01` = 6 tokens; `250301` = 2; monthly header `2503` (2) + day `01` (1) ≈ **1.04 tokens/row** for the date.

## Layout that actually wins

```
Header=YYMM. Row=DD N V C [flags]. V=signed cents. Default eur/主. $=usd 储=savings 贷=credit.
N 利=lidl 奈=netflix 工=monthly salary …     (50 merchants)
C 租=rent 菜=groceries 购=shopping 咖=coffee … (16 gold categories)
A 主=main 储=savings 贷=credit
2503
01工324394薪
01包-663咖
03房-118100租
260911巴-39289旅贷
```

`lang_ideo_monthly` splits as **legend 351 + body 6,921 = 7,273**.
A local decoder (`decode_compact_monthly`) reconstructs date, merchant, cents, currency, account, and gold category for all 1000 rows (`roundtrip_compact_monthly` is True). Same for ZH/DE/RU/KO/JA/pinyin monthly variants.

## Recoverability (human / model)

All compact codecs **embed the legend in the payload**. Gold English categories are `rent, groceries, restaurants, transport, salary, freelance, subscriptions, entertainment, healthcare, utilities, shopping, travel, coffee, insurance, education, gifts`.

| scheme | human without legend | human with legend | model with legend |
| --- | --- | --- | --- |
| 1-char mnemonic CJK (`租` rent, `咖` coffee, `奈` netflix, `利` lidl) | **medium** — many guesses work; `零`=weekend gig and `闪`=bolt need the map | **high** | **high** |
| 1-char Hangul (`월` rent, `커` coffee, `봉` salary) | low–medium | **high** | **high** |
| 1-char Japanese (`租` `咖` `ネ`) | medium | **high** | **high** |
| Real ZH words (`房租` `周菜` `奈飞` `工资`) | **high** if bilingual | **high** | **high** |
| Real DE / RU / KO / JA words | **high** if bilingual | **high** | **high** |
| Pinyin (`zu` `shi` `can` `naifei`) | **medium** — `can`/`li`/`yu` collide with English | **high** | **medium-high** |
| CJK / Hangul **digit substitution** | **high** (零=0, 일=1) | **high** | **high** |
| Hangul **base-80 packing** of cents | **none** | formula is in the payload; need arithmetic | **uncertain** — reversible but easy to fumble |
| Mixed English names + CJK amounts | names **high**, amounts **high** | high | high; still loses on ISO dates |

**Recommended quality/token tradeoff**

1. **`lang_ideo_monthly` (7,273)** — primary success codec. Mnemonic CJK + full English legend. Strictly reversible.
2. **`lang_ideo_monthly_spaced` (8,829)** — same maps, spaces between fields; better for model parsing if glued digits worry you.
3. **`lang_zh_monthly` (9,203)** — real Chinese words, still well under yaml_like; best “a bilingual human can read it cold” option.

Do **not** ship `lang_*_full` ISO-line translations or mixed CJK-digit amounts as token winners. They answer the “did we translate every merchant?” question and lose.

## In-payload legend (from `lang_ideo_monthly`)

Category map (complete):

```
C 租=rent 菜=groceries 餐=restaurants 车=transport 薪=salary 兼=freelance
  订=subscriptions 娱=entertainment 医=healthcare 电=utilities 购=shopping
  旅=travel 咖=coffee 保=insurance 教=education 礼=gifts
```

Account / currency flags:

```
A 主=main 储=savings 贷=credit
Default eur/主. $=usd.
```

Merchant map (complete, 50):

```
N 宿=airbnb weekend 奥=aldi 亚=amazon order 房=apartment rent 包=bakery coffee
  生=bio company 寿=birthday gift 书=books 闪=bolt ride 堡=burger joint
  轨=bvg ticket 影=cinema 演=concert 顾=consulting fee 牙=dentist
  设=design invoice 力=electricity 浓=espresso 白=flat white 巴=flixbus
  花=flowers 油=fuel 码=github pro 诊=gp visit 健=gym 险=health insurance
  云=icloud+ 宜=ikea 网=internet 语=language class 利=lidl 航=lufthansa
  媒=media markt 工=monthly salary 博=museum 奈=netflix 课=online course
  药=pharmacy 面=ramen bar 雷=rewe 声=spotify 游=steam game 鲜=sushi place
  意=trattoria roma 优=uber ride 水=water bill 婚=wedding gift 零=weekend gig
  周=weekly groceries 扎=zara
```

Hangul pack alphabet (only needed for `lang_ideo_monthly_hangulpack` / `lang_hangul_pack`):

```
V = 3 Hangul syllables, base 80, of (cents + 121390)
H = 가각간갈감갑값강같개객거건걸검겁것게겠겨격견결겼경계고곡곤골곳공과관광괴교구국군굴궁권귀규균그극근글금급기긴길김까깔깨꺼께껴꽃꾸꿈끄끌끔끝끼낌나난날남납났내낸낼
```

That packing is reversible and cheaper than CJK digits, but **ASCII cents still win** and stay human-readable.

## Density by script (same monthly+cents skeleton)

Once dates are YYMM/DD and values are signed cents, script density on this corpus is:

| labels | tokens | notes |
| --- | ---: | --- |
| 1-token Hangul syllables | 7,240 | cheapest; less mnemonic than hanzi |
| 1-token CJK ideographs | 7,273 | best recoverability/token |
| 1-token kanji/kana | 7,281 | almost identical |
| 2-char Chinese words | 9,203 | no codes, still ≪ yaml_like |
| Pinyin | 9,218 | Latin; collision risk |
| Korean words | 9,958 | 2–3 syllables each |
| German words | 10,031 | compounds (`Wohnungsmiete`) hurt |
| Japanese words | 10,996 | kana brands are long |
| Russian words | 11,517 | Cyrillic BPE is weaker here |

German **can** beat yaml_like (10,031 vs 12,020) if you also pack dates/amounts. Category-only German at 16,137 was never a script win; it was “leave the expensive fields in English ISO format.”

## Files

- `experiments/tokenization/codecs/extra_lang.py` — dictionaries, codecs, `decode_compact_monthly`, `roundtrip_compact_monthly`
- This note — `experiments/tokenization/results/subagents/languages.md`
