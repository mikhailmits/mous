"""Isolated HTTP + CLI + headless UI e2e for mous."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
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
    notify,
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
    start_api,
    stop,
    wait_health,
    write_config,
)


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
    try:
        if not args.skip_swift:
            log("feature swift")
            swift.run(env)
        log(f"API on :{E2E_PORT}  config {directory}")
        api = start_api(env)
        wait_health(proc=api)
        log("feature civil_today")
        civil_today.run()
        log("feature http")
        http.run(env)
        log("feature fx")
        fx.run()
        log("feature hide_balance")
        hide_balance.run_http(directory)
        log("feature notify")
        notify.run_http(directory)
        log("feature cli")
        cli.run(env)
        if not args.no_ui:
            log("feature ui")
            seed.run(env, directory)
            log("feature parser_shapes")
            notes = ui.run(env, directory, force=args.force_ui)
            for note in notes:
                log(note)
        else:
            log("skip ui (--no-ui)")
        stop(api)
        api = None
        log("feature drop")
        drop.run(env, directory)
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
