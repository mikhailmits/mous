"""One module per product surface.

When you ship a feature, add `scripts/e2e_mous/features/<name>.py` with a
`run(...)` (and `run_ui` if the popup is involved), wire it in
`e2e_mous.__main__`, and tick it in `.cursor/skills/e2e-mous/`.
"""

# Log names in run order. Keep in sync with __main__.py.
# calc / parser_shapes run inside ui, not as top-level steps.
MODULES = (
    "swift",
    "civil_today",
    "http",
    "fx",
    "hide_balance",
    "cli",
    "seed",
    "ui",
    "drop",
)
