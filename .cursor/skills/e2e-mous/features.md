# Feature matrix

Every surface the e2e pass is supposed to touch. Entry: `scripts/e2e.py`
(`scripts/e2e_mous` package). HTTP/CLI always run; unless `--no-ui`, a
**headless** popup pass (`MOUS_HEADLESS=1`): alpha 0, parked off-screen,
no screenshots. Isolation: `MOUS_CONFIG_DIR` + port **18765** + a temp
`data.db`. Production `~/Library/Application Support/mous/` is
fingerprinted and must not change.

Add a row here when you add `scripts/e2e_mous/features/<name>.py`.

## Swift (`features/swift.py` → MousCoreCheck)

Parser (signed amounts, optional space after the sign, glued notes,
currency suffixes, invalid states), dashboard snapshot, FX stub + EUR
pivot (`MoneyDisplay` / `FXBook`), left converted from per-currency
balance buckets (missing quotes omitted, not 1:1), repeat category name
matching, spend rank, config.json (incl. `hide_balance`,
`hide_balance_style` default scramble, theme `lime`),
input assist (`45+34`, `4 eur to uah`), update version compare, AppStore
splash/currency, loopback API client, `BalanceMask` veil `•`.

## HTTP (`features/http.py` on `127.0.0.1:18765`)

| Area | Checks |
| --- | --- |
| OpenAPI | `GET /openapi.json` lists every router path; `GET /docs` HTML |
| Health | `GET /health` → `{status: ok}` |
| Accounts | list, get by id, create, rename, delete extra, duplicate name → 409 `conflict`, last delete → 409 `last_account`, missing → 404, overlong name → 422, balance (`amount` in default + native `by_currency`), spent converted with range + default window |
| Currencies | default `eur`, get by id/symbol, create `usd`/`gbp`, dup → 409, patch default/name/symbol, clear last default → 409 `last_default`, delete default → 409 `last_default`, missing → 404 |
| Categories | create, get by name/id, rename, duplicate → 409 `conflict`, missing → 404, name >30 → 422 |
| Transactions | income `>0`, expense `<0`, omit account → main, zero → 422, missing fields → 422, `category_id` on create/patch, patch null clears tag, patch name/value/currency/date, patch zero → 422, list by day, `top_value`/`btm_value`, get, delete, missing → 404 |
| Subscriptions | embedded good + cron, get by id, patch cron + noop, list by account/`good_id`, create from existing `good_id`, missing fields/zero → 422, missing → 404, delete |

Values are signed. Ledger `value` stays in its own currency. GET rows also
include `amount` converted into the API default for EUR/USD/UAH; other
currencies are omitted (`amount` is null). Balance `amount` and spent
convert the same way. `by_currency` stays native.

## FX (`features/fx.py`)

Stub quotes: EUR→USD 1.1, EUR→UAH 40, EUR pivot; GBP omitted (not 1:1).
HTTP: POST a EUR row, switch API default to USD, GET `amount` converts
while `value` stays native, restore EUR. `GET /accounts/{id}/balance`
`amount` follows the default; `by_currency` stays native so leftover can
be converted into Settings currency (not a mixed 1:1 sum).

## Hide balance (`features/hide_balance.py`)

Config default `false`. If `hide_balance_style` exists, default
`scramble`. Python `load_config` round-trips. With `hide_balance` on, GET
transactions / balance / spent stay **numbers** (masking is UI-only).
Settings “Hide balance” writes the flag. The dashboard covers amounts
with steady `•` dots; hold the eye to peek. API masking is not a thing.
Toggle restores `false`. Style chips are gone.

## Parser shapes (`features/parser_shapes.py`)

Popup types `+ 10 hii` Return and `+10hii` Return (glued note). Both POST
income `+10` in the default currency with description `hii`. Spaces in the
field are kept (the harness does not assert a stripped line). Parser unit
cases live in MousCoreCheck.

## Civil today (`features/civil_today.py`)

`mous.api.time.utc_today()` equals `date.today()` (local civil date).

## CLI (`features/cli.py`)

| Command | Checks |
| --- | --- |
| `mous summary` | gone: non-zero, help does not mention it |
| API down | `summary` still non-zero; help still works |
| `mous serve --help` | `--host` / `--port` (does not bind a second server) |
| `mous drop --help` | mentions `docker` (**never** run `drop docker`) |
| `mous drop` | `features/drop.py` after the isolated path is verified; deletes temp `data.db` |

## Popup (`features/ui.py`, headless)

| Feature | How |
| --- | --- |
| Dashboard | Spent today, left, month, saved % (AX best-effort off-screen) |
| Quick entry | `MOUS_DEMO_TYPE=-4 coffee` Return commits |
| Math row | `45+34` shows `= 79`. Return inserts `79` and does not post |
| FX calculator | `-10 eur to usd` Tab → `-11usd`, then description Return posts native USD. Enter on a calc line converts and does not post (leftover/API unchanged until a second Return with a signed line). Unsigned `10 eur to usd` Tab → `11usd` does not post. `-3 coffee to go` stays a description. |
| Parser shapes | `+ 10 hii` and `+10hii` Return → income +10 default currency, description `hii`. Do not assert a stripped field. |
| Starter categories | groceries, eating out, transport, rent, salary, health, fun, other |
| Invalid line | Type `xyz` Return (shake / reject) |
| ⌘ keycaps | Hold ⌘ (`flagsChanged` to the child pid) |
| Hover tips | Spend hotspot → History; Saved → Most expensive. Best-effort off-screen. |
| History / expensive | ⌘M, ⌘X, ⌘F, Escape. Tip titles are AX best-effort. |
| Options | ⌘O, Escape |
| Settings | ⌘S: Leaf/Pale/Lime/Mint/Sea/Clay/White, EUR/USD/UAH, Hide balance, Check for updates, Advanced host/port/db/dev. Temp config only. |
| Display currency | Home after USD, then restore EUR. Theme back to Lime. |
| Isolation | Advanced `database_path` stays in the temp dir; prod fingerprint unchanged |
| Visibility | Alpha 0 + origin off-screen; no `screencapture` |
| Digest | Timings, currencies, categories, balance, config, UI notes |

FX quotes: the popup installs `FXBook.stub` (EUR→USD 1.1, EUR→UAH 40,
EUR pivot). The API uses the same stub. Settings currency recomputes spent /
left / history / most expensive by converting each good and
each `by_currency` bucket. Unquoted pairs are omitted, not shown as 1:1.
Ledger `value` stays native; GET `amount` and spent are in the default
currency.
`mous drop docker` and `mous dev` are not executed (destructive / second popup).
