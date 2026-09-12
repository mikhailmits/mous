# What we learned (plain English)

We built a fake bank account with **1000 purchases and paychecks**. Then we asked an AI three questions:

1. **Reports:** How much came in, how much went out, what’s left, and what category ate the most money?
2. **Optimize:** If you cut one optional habit, which one saves the most? (Shopping.)
3. **Forecast:** Roughly, what will next month look like? (Average of the last 3 months.)

The real answers (from the database, not the AI):

- In: **€90,564.20**
- Out: **€75,572.82**
- Left over: **€14,991.38**
- Biggest spend category: **rent** (€22,703.20)
- Best place to cut: **shopping**
- Next month (naive guess): spend **€2,888.14**, income **€4,581.06**

## Words in this report, once

- **Token** = a bite-sized piece of text the AI is billed for. More tokens = more money and a longer prompt. We counted with the same system ChatGPT-5 uses.
- **“Way of writing the ledger”** = we rewrote the same 1000 rows many times (shorter dates, no spaces, Chinese labels, a zip file, a screenshot, …) to see which writing is cheapest.
- **Qwen** = a small, cheap AI. **Gemini** = a stronger (and vision-capable) AI.
- **Score 1.00** = it got every check right. **0** = it got them all wrong.

## The whole experiment in one sentence

**Don’t send the AI 1000 raw bank rows. Have the app add the numbers first, then send the tiny summary. A small AI copies that summary perfectly. It cannot add 1000 amounts, and it cannot even add 16 category totals.**

Normal pretty JSON of all 1000 rows costs **55,614 tokens**. The tiny summary (`tool_copy`) costs **196 tokens** and Qwen scored **100%**.

## What to actually ship

Mous already has an API. The agent should call tools like “spend by category” and “last 3 months,” then hand the model a short answer sheet:

```
n = 1000
in = 90564.20
out = 75572.82
top = rent
cut = shopping
next month spend ≈ 2888.14
```

That answer sheet is **`tool_copy`**. Qwen copied it with **zero errors**.

If you also dump *every* past month into the prompt, the small AI averages the wrong months and forecasts **€4,072** instead of **€2,888**. Only send the **last 3 months**.

## Scoreboard

| What we sent the AI | How big? | Did the AI get the money right? |
| --- | --- | --- |
| **Short answer sheet** (`tool_copy`) | **196** tokens | **Yes — 100%** (Qwen copied it) |
| Same idea, extra API junk included (`tool_views`) | 651 tokens | Yes — 100% |
| Category totals + last 3 months, AI must still add (`tool_rollup`) | 378 tokens | Gemini: yes (expense off by 0.7%). Qwen: **no**, it can’t add 16 numbers |
| Picture of a monthly/category **table** | 255 image-units | Gemini: **100%** |
| All 1000 rows, written as compact as we could | ~5,123 tokens | **No.** Python can add them. The AI cannot. |
| All 1000 rows **drawn as a picture** | 765 image-units | **No.** Gemini sees “1000 rows” and invents round numbers. |
| Zipped + encoded as gibberish (`gzip`) | 7,863 tokens | **No.** 0%. The AI can’t read it. |

So: **cheap and correct = send the summary. Cheap and wrong = zip file or a screenshot of 1000 lines. Expensive and still wrong = pretty JSON of every row.**

## Weird tricks we tried (and what happened)

We tried every compression idea people usually suggest.

**Taking out spaces.** Makes GPT-5 *more* expensive, not less. The model likes normal spaces. Short dates (`250301` instead of `2025-03-01`) and amounts in cents (`-118100`) *do* help.

**Replacing spaces with `|` or fancy dots.** Worse than a normal space.

**Writing it in Chinese / Korean / Japanese.** Translating the word “groceries” barely matters. Dates and numbers eat most of the budget. The best language trick (one cheap character per category, grouped by month) still costs **~7,240 tokens** — better than 12,000, worse than the 5,100-token English packing, and the AI still can’t add.

**Zip / encrypt.** Fewer *bytes*, but the AI sees alphabet soup. Score: 0.

**Turn the ledger into a picture.** A tall 1000-line screenshot looks cheap on paper (same cost as a packed grid) but the letters get crushed to ~2 pixels. A carefully packed 4-column grid keeps letters ~8 pixels tall. Gemini can *see* there are 1000 rows and that rent is big. It **cannot** add 942 expenses from the pixels. A picture of the **already-summed table** works (100%). A picture of all 1000 lines does not.

**A custom shorthand for finance.** We got the 1000 rows down to ~5,100 tokens. A Python script can decode it and match the real totals. The AI still guesses.

## Who can do the math?

| Who | Can do | Cannot do |
| --- | --- | --- |
| The app / database | Add 1000 rows, group by category, average last 3 months | — |
| Small AI (Qwen) | Copy a summary; average **3** numbers | Add 16 category totals; read 1000 rows from text or a picture |
| Stronger AI (Gemini) | Copy a summary; pick the biggest category; average 3 months; almost add 16 totals | Read 1000 rows off a picture |

## Bottom line

Build this:

**bank data → app adds it up → AI writes the three answers**

Not this:

**bank data → paste 1000 rows (or a screenshot of them) into the AI → hope it adds**

The lab is finished. 120 ways of writing the ledger later, none of the “keep all 1000 rows” versions beat “let the app add first” on both cost *and* correctness.
