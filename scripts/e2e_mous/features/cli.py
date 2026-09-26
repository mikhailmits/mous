"""CLI help and a check that `summary` is no longer a command."""

from __future__ import annotations

from e2e_mous.harness import expect, mous_cli


def run(env: dict[str, str]) -> None:
    help_out = mous_cli(env, ["--help"])
    help_text = help_out.stdout + help_out.stderr
    expect(help_out.returncode == 0, f"help failed: {help_out.stderr}")
    expect("summary" not in help_text.lower(), "summary command should be gone")
    serve_help = mous_cli(env, ["serve", "--help"]).stdout
    expect("--host" in serve_help and "--port" in serve_help, "serve help")
    drop_help = mous_cli(env, ["drop", "--help"]).stdout + mous_cli(env, ["drop", "--help"]).stderr
    expect("docker" in drop_help, "drop help lists docker (not executed)")
    gone = mous_cli(env, ["summary", "week"])
    expect(gone.returncode != 0, f"summary should not run, got {gone.returncode}")


def run_api_down(env: dict[str, str]) -> None:
    down = mous_cli(env, ["summary", "week"])
    expect(down.returncode != 0, f"summary with API down should fail, got {down.returncode}")
    help_out = mous_cli(env, ["--help"])
    expect(help_out.returncode == 0, "help still works with the API down")
