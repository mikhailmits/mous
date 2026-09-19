"""MousCoreCheck: parser, FX, dashboard, config, inbox, API client."""

from __future__ import annotations

import subprocess

from e2e_mous.harness import Failed, ROOT, SWIFT


def run(env: dict[str, str]) -> None:
    completed = subprocess.run(
        ["swift", "run", "--package-path", str(SWIFT), "MousCoreCheck"],
        cwd=ROOT,
        env=env,
        check=False,
    )
    if completed.returncode != 0:
        raise Failed("MousCoreCheck failed")
