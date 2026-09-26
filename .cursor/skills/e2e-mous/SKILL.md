---
name: e2e-mous
description: >-
  Tests the Mous macOS popup and local FastAPI end to end. The harness is
  scripts/e2e_mous (one module per feature) with scripts/e2e.py as the
  entrypoint: MousCoreCheck, isolated HTTP, FX, hide-balance,
  inline FX calculator, math in the input bar, starter categories, and a
  headless off-screen UI pass. Use when the user asks to test mous, run e2e,
  QA the app, verify every feature, or check the popup end to end. When
  adding a feature, add a module under scripts/e2e_mous/features/ and
  wire it in __main__.
---

# E2E mous

Test the app fully end to end every single feature.

This is a native borderless Swift popup talking to FastAPI on loopback. Do
not use browser tools. Never write the e2e database into
`~/Library/Application Support/mous/data.db`. The script fingerprints that
folder and fails if anything there changes.

The popup pass is **headless by default**: `MOUS_HEADLESS=1`, accessory
policy, window alpha 0 and parked off-screen, keys via `CGEventPostToPid`,
assertions via Accessibility + config/API. **No screenshots.** Do not quit
or `pkill` a Mous the user already has open. Do not steal focus from Cursor.
The user must not see the e2e popup.

## Run

From the repo root, with Command Line Tools on `PATH`:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  uv run python scripts/e2e.py
```

`scripts/e2e.py` is a shim. The suite lives in `scripts/e2e_mous/`. Same
entrypoint: Swift + isolated HTTP + CLI help + headless popup +
API-down exit 1 + isolated `mous drop`.

`--keep` leaves the temp config dir. The temp dir is also kept on `FAIL`.

`--no-ui` skips the popup pass (HTTP/CLI only). `--ui` / `--force-ui` are
no-ops kept for old command lines.

Stop if the run prints `FAIL`. Fix, re-run, then continue.

## Package

One Python module per product surface. Do **not** grow a single script.

```
scripts/e2e.py                         shim → e2e_mous.__main__
scripts/e2e_mous/harness.py            isolation, HTTP client, serve/stop
scripts/e2e_mous/ax.py                 pid keys, AX clicks (no screenshots)
scripts/e2e_mous/features/
  swift.py           MousCoreCheck
  civil_today.py     API today = local civil date
  http.py            OpenAPI + CRUD routers + mixed FX aggregates
  fx.py              stub quotes + GET amount follows default currency
  hide_balance.py    config + API stays numeric + Settings toggle / dots
  calc.py            math `45+34` and `10 eur to usd` Tab/Return, then post
  parser_shapes.py   popup `+ 10 hii` / `+10hii` income
  cli.py             help, summary is gone, API-down still rejects summary
  seed.py            dashboard books for the popup
  ui.py              headless popup (calls calc, parser_shapes, hide_balance)
  drop.py            isolated mous drop
```

### Adding a feature

1. Create `scripts/e2e_mous/features/<name>.py` with `run(...)`.
   If the popup is involved, also add `run_ui(pid, directory, notes)`.
2. Call it from `scripts/e2e_mous/__main__.py` (log `feature <name>`).
3. Append the name to `scripts/e2e_mous/features/__init__.py` `MODULES`.
4. Tick it below and in [features.md](features.md).

Ship the e2e in the same change as the product code.

## What must pass

Tick while you run. Details in [features.md](features.md).

```
- [x] MousCoreCheck (assist math/FX, lime theme, no report/notify)
- [x] Isolated API on :18765 (OpenAPI/docs, health, accounts, currencies,
      categories, transactions, subscriptions, last-account 409,
      last-default 409, conflict 409, missing 404, zero/validation 422,
      filters, good_id, balance by_currency). Starter eur/usd/uah and
      the eight categories already exist.
- [x] FX stub EUR/USD/UAH; GBP omitted; GET amount follows API default;
      ledger value stays native
- [x] hide_balance: default off; style stays scramble in config; Settings
      toggle writes hide_balance; API stays numeric. Dashboard dots are
      AX best-effort (WARN if the tree has no veil).
- [x] utc_today is the local civil date
- [x] `mous summary` is gone (non-zero). serve/drop --help. API down still
      rejects summary. Isolated mous drop (never drop docker, never prod)
- [x] UI: dashboard field + starter categories (no repeat-name coffee category)
- [x] UI: entry line commits (MOUS_DEMO_TYPE); invalid line reject
- [x] UI: math row `45+34` shows `= 79`; Return inserts and does not post
- [x] UI: FX calc `x {from} to {to}` Tab/Enter replaces the field; then post;
      unsigned Tab does not post until a signed Return
- [x] UI: parser_shapes `+ 10 hii` / `+10hii` income +10 default currency
- [x] UI: ⌘ keycaps; hover History / Most expensive (best-effort off-screen)
- [x] UI: ⌘M / ⌘X / ⌘F / Escape (tip titles are AX best-effort)
- [x] UI: ⌘O options (AX best-effort)
- [x] UI: ⌘S settings (theme Leaf…White, currency, Hide balance,
      Check for updates, Advanced host/port/db/dev) — temp config only
- [x] UI: home after USD display, restore EUR, theme back to Lime
- [x] Production ~/Library/Application Support/mous unchanged
- [x] Digest prints timings, currencies, categories, balance, config, UI notes
```

## Rules that bit us

- Isolate with `MOUS_CONFIG_DIR` + port **18765**. Production data stays put.
  `env_for` drops `MOUS_DATABASE_URL`. Fail if `:18765` is already bound.
- Target the e2e process **unix PID** (`whose unix id is`). Never
  `screencapture` (visible or `-l`); the panel stays alpha 0 off-screen.
- Another Mous may stay running; never `pkill -x Mous` as part of the
  harness. Keys must use the child pid.
- Settings buttons live under SwiftUI groups; AX clicks must search
  `entire contents` of every window, not `buttons of window 1`.
- Rebuild the Mous product on each popup pass so a stale `.build` binary
  is not what you drive.
- Do not set `MOUS_DEMO_TIP`. `MOUS_DEMO_TYPE` posts one demo line.
- Accessibility is required for AX clicks and `CGEventPostToPid`. If it is
  missing, the demo type still counts; say so in the report.
- `uv run mous serve` only exists when config `dev` is true (the script
  writes that).
- Never run `mous drop docker` or `mous dev` from the harness.

## Report

Lead with pass/fail, then the checklist, then anything unverified (no
Accessibility, other Mous left running, AX click WARNs). Do not claim the
UI pass if `--no-ui` was used.
