"""mous summary periods, invalid period, serve/drop help, API-down exit."""

from __future__ import annotations

from e2e_mous.harness import expect, mous_cli


def run(env: dict[str, str]) -> None:
    periods = (
        ["week"],
        ["month"],
        ["14", "days"],
        ["2", "weeks"],
        ["1", "year"],
        ["1", "day"],
        [],
    )
    for period in periods:
        good = mous_cli(env, ["summary", *period])
        label = " ".join(period) or "default"
        expect(good.returncode == 0, f"summary {label} failed: {good.stderr}")
        expect(good.stdout.startswith("summary\n"), f"summary {label} layout: {good.stdout[:80]!r}")
        for key in ("currency =", "n =", "in =", "out =", "saved =", "top =", "runway ="):
            expect(key in good.stdout, f"summary {label} missing {key}")
    bad = mous_cli(env, ["summary", "fortnightly-ish"])
    expect(bad.returncode == 2, f"invalid period should be 2, got {bad.returncode}")
    help_text = mous_cli(env, ["--help"]).stdout + mous_cli(env, ["--help"]).stderr
    expect("summary" in help_text, "cli help missing summary")
    serve_help = mous_cli(env, ["serve", "--help"]).stdout
    expect("--host" in serve_help and "--port" in serve_help, "serve help")
    drop_help = mous_cli(env, ["drop", "--help"]).stdout + mous_cli(env, ["drop", "--help"]).stderr
    expect("docker" in drop_help, "drop help lists docker (not executed)")


def run_api_down(env: dict[str, str]) -> None:
    down = mous_cli(env, ["summary", "week"])
    expect(down.returncode == 1, f"summary with API down should be 1, got {down.returncode}")
