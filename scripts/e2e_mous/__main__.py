"""Isolated HTTP + CLI + headless UI e2e for mous."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from e2e_mous.features import (  # noqa: E402
    civil_today,
    cli,
    drop,
    fx,
    hide_balance,
    http,
    seed,
    swift,
    ui,
)
from e2e_mous.harness import (  # noqa: E402
    E2E_PORT,
    Failed,
    assert_prod_untouched,
    env_for,
    expect,
    isolated_database,
    log,
    prod_fingerprint,
    read_config,
    request,
    start_api,
    stop,
    wait_health,
    write_config,
)


def _run(name: str, fn, timings: list[tuple[str, float]]) -> None:
    log(f"feature {name}")
    started = time.perf_counter()
    fn()
    timings.append((name, time.perf_counter() - started))


def _digest(directory: Path, timings: list[tuple[str, float]], notes: list[str]) -> None:
    log("--- result ---")
    total = sum(seconds for _, seconds in timings)
    log(f"passed in {total:.1f}s")
    for name, seconds in timings:
        log(f"  {name:<16} {seconds:.2f}s")
    try:
        cfg = read_config(directory)
        currencies = request("GET", "/currencies") or {}
        categories = request("GET", "/categories") or {}
        accounts = request("GET", "/accounts") or {}
        currency_items = currencies.get("items") if isinstance(currencies, dict) else None
        category_items = categories.get("items") if isinstance(categories, dict) else None
        account_items = accounts.get("items") if isinstance(accounts, dict) else None
        main = next(
            (row for row in (account_items or []) if isinstance(row, dict) and row.get("name") == "main"),
            None,
        )
        balance = None
        if isinstance(main, dict) and main.get("id") is not None:
            balance = request("GET", f"/accounts/{main['id']}/balance")
        symbols = ", ".join(
            str(row.get("symbol") or "") for row in (currency_items or []) if isinstance(row, dict)
        )
        names = ", ".join(
            str(row.get("name") or "") for row in (category_items or []) if isinstance(row, dict)
        )
        log(f"currencies: {symbols}")
        log(f"categories: {names}")
        if isinstance(balance, dict):
            log(f"balance: {balance.get('amount')} {balance.get('currency')}")
            parts = balance.get("by_currency") or []
            if isinstance(parts, list) and parts:
                native = ", ".join(
                    f"{part.get('currency_id')}={part.get('amount')}"
                    for part in parts
                    if isinstance(part, dict)
                )
                log(f"balance by currency id: {native}")
        log(
            "config: "
            f"theme={cfg.get('theme')} currency={cfg.get('currency')} "
            f"hide_balance={cfg.get('hide_balance')}"
        )
    except Exception as exc:
        log(f"digest partial: {exc}")
    if notes:
        log("ui: " + "; ".join(notes))


def main() -> int:
    parser = argparse.ArgumentParser(description="Isolated mous e2e")
    parser.add_argument(
        "--no-ui",
        action="store_true",
        help="Skip the headless popup pass (HTTP/CLI only)",
    )
    parser.add_argument(
        "--ui",
        action="store_true",
        help="Deprecated; the popup pass is the default",
    )
    parser.add_argument(
        "--force-ui",
        action="store_true",
        help="Deprecated; another Mous may stay open",
    )
    parser.add_argument("--skip-swift", action="store_true", help="Skip MousCoreCheck")
    parser.add_argument("--keep", action="store_true", help="Keep the temp config dir")
    args = parser.parse_args()

    before_prod = prod_fingerprint()
    directory = Path(tempfile.mkdtemp(prefix="mous-e2e-"))
    write_config(directory)
    env = env_for(directory)
    os.environ["MOUS_CONFIG_DIR"] = env["MOUS_CONFIG_DIR"]
    os.environ["MOUS_API_HOST"] = env["MOUS_API_HOST"]
    os.environ["MOUS_API_PORT"] = env["MOUS_API_PORT"]
    os.environ.pop("MOUS_DATABASE_URL", None)
    expect(env["MOUS_CONFIG_DIR"] == str(directory), "MOUS_CONFIG_DIR")
    isolated_database(directory)
    api = None
    code = 0
    timings: list[tuple[str, float]] = []
    notes: list[str] = []
    try:
        if not args.skip_swift:
            _run("swift", lambda: swift.run(env), timings)
        log(f"API on :{E2E_PORT}  config {directory}")
        api = start_api(env)
        wait_health(proc=api)
        _run("civil_today", civil_today.run, timings)
        _run("http", lambda: http.run(env), timings)
        _run("fx", fx.run, timings)
        _run("hide_balance", lambda: hide_balance.run_http(directory), timings)
        _run("cli", lambda: cli.run(env), timings)
        if not args.no_ui:
            _run("seed", lambda: seed.run(env, directory), timings)

            def _ui() -> None:
                notes.extend(ui.run(env, directory, force=args.force_ui))

            _run("ui", _ui, timings)
        else:
            log("skip ui (--no-ui)")
        _digest(directory, timings, notes)
        log("feature cli_api_down")
        started = time.perf_counter()
        stop(api)
        api = None
        cli.run_api_down(env)
        timings.append(("cli_api_down", time.perf_counter() - started))
        _run("drop", lambda: drop.run(env, directory), timings)
        log("ok")
    except Failed as exc:
        log(f"FAIL {exc}")
        code = 1
    finally:
        stop(api)
        try:
            assert_prod_untouched(before_prod)
        except Failed as exc:
            log(f"FAIL {exc}")
            code = 1
        if args.keep or code != 0:
            log(f"kept {directory}")
        else:
            shutil.rmtree(directory, ignore_errors=True)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
