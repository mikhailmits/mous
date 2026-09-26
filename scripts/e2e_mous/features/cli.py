"""serve/drop help for the dev CLI (the summary command was removed)."""

from __future__ import annotations

from e2e_mous.harness import expect, mous_cli


def run(env: dict[str, str]) -> None:
    serve_help = mous_cli(env, ["serve", "--help"]).stdout
    expect("--host" in serve_help and "--port" in serve_help, "serve help")
    drop_help = mous_cli(env, ["drop", "--help"]).stdout + mous_cli(env, ["drop", "--help"]).stderr
    expect("docker" in drop_help, "drop help lists docker (not executed)")
