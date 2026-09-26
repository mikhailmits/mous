#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the mous backend (FastAPI + SQLite).
# Safe to run repeatedly and against cached/snapshotted state.
set -euo pipefail

UV_VERSION="0.12.3"

# 1. Ensure the uv package manager is available (pinned to the repo's version).
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
fi
export PATH="${HOME}/.local/bin:${PATH}"

# 2. Install Python dependencies exactly as locked.
uv sync --frozen

# 3. Initialise the local mous config so the documented dev CLI
#    (`mous serve`, `mous summary`, `mous drop`) is enabled. This also
#    creates the config directory that holds the SQLite database, which the
#    API server needs before it can open the database file.
uv run python - <<'PY'
from mous.config.utils import config_path, ensure_config, load_config, save_config

cfg = ensure_config()
if not cfg.get("dev"):
    cfg["dev"] = True
    save_config(cfg)
print(f"mous config ready at {config_path()} (dev={load_config()['dev']})")
PY
