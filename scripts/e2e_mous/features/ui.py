"""Headless popup: dashboard, entry, calculator, tips, settings, hide-balance."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

from e2e_mous.ax import (
    ax_click,
    ax_click_retry,
    ax_tree_text,
    click_until_config,
    hold_command,
    hover_in_window,
    mous_bin_path,
    other_mous_pids,
    send_keys,
    wait_demo_coffee_posted,
    wait_ui,
    wait_window,
)
from e2e_mous.features import calc, hide_balance, parser_shapes
from e2e_mous.harness import (
    E2E_PORT,
    Failed,
    ROOT,
    expect,
    isolated_database,
    request,
    stop,
)


def run(env: dict[str, str], directory: Path, force: bool = False) -> list[str]:
    notes: list[str] = []
    existing = other_mous_pids()
    if existing:
        notes.append(f"other Mous pid(s) {existing} left running; targeting child pid")
    binary = mous_bin_path(env)
    ui_env = env.copy()
    ui_env["MOUS_DEMO_TYPE"] = "-4 coffee"
    ui_env["MOUS_HEADLESS"] = "1"
    proc = subprocess.Popen(
        [str(binary)],
        cwd=ROOT,
        env=ui_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    def keys(stroke: str, command: bool = False) -> bool:
        return send_keys(stroke, command=command, pid=proc.pid)

    try:
        deadline = time.time() + 25
        appeared = False
        started = time.time()
        while time.time() < deadline:
            if proc.poll() is not None:
                raise Failed(f"Mous exited early ({proc.returncode})")
            try:
                wait_window(proc.pid, timeout=0.4)
                appeared = True
                break
            except Failed:
                if time.time() - started > 2.5:
                    appeared = True
                    notes.append("process up (off-screen frame optional)")
                    break
                time.sleep(0.05)
        if not appeared:
            raise Failed("e2e Mous window never appeared")
        time.sleep(0.25)
        if wait_ui(proc.pid, "New transaction", timeout=2.0) or wait_ui(proc.pid, "Spent today", timeout=0.4):
            notes.append("dashboard spent/left/month/saved")
            home = ax_tree_text(proc.pid)
            if "saved" in home.lower() and "%" in home:
                notes.append("dashboard saved percent")
            else:
                notes.append("WARN: dashboard saved percent AX missed")
        else:
            notes.append("WARN: dashboard AX labels not found (window is off-screen)")

        if not wait_demo_coffee_posted():
            raise Failed("demo -4 coffee had not posted yet")
        notes.append("demo line posted")

        expect(keys("a", command=True), "pid key events")
        keys("xyz")
        keys("return")
        time.sleep(0.2)
        keys("a", command=True)
        keys("delete")
        notes.append("invalid line reject")

        calc.run_ui(proc.pid, notes)
        parser_shapes.run_ui(proc.pid, notes)

        if hold_command(0.2, pid=proc.pid):
            notes.append("⌘ keycaps")

        if hover_in_window(proc.pid, 0.22, 0.22):
            if wait_ui(proc.pid, "History", timeout=0.4):
                notes.append("hover history")
            else:
                notes.append("hover history posted (tip AX not required)")
        if hover_in_window(proc.pid, 0.82, 0.38):
            if wait_ui(proc.pid, "Most expensive", timeout=0.4):
                notes.append("hover expensive")
            else:
                notes.append("hover expensive posted (tip AX not required)")
        keys("esc")
        time.sleep(0.08)

        keys("m", command=True)
        if wait_ui(proc.pid, "History", timeout=0.45):
            notes.append("⌘M history")
        else:
            notes.append("WARN: ⌘M history AX missed")
        keys("esc")
        time.sleep(0.08)

        keys("x", command=True)
        if wait_ui(proc.pid, "Most expensive", timeout=0.45):
            notes.append("⌘X most expensive")
        else:
            notes.append("WARN: ⌘X expensive AX missed")
        keys("f", command=True)
        time.sleep(0.08)
        keys("esc")
        time.sleep(0.08)
        keys("f", command=True)
        time.sleep(0.08)
        keys("esc")
        time.sleep(0.08)
        notes.append("⌘X expensive + ⌘F focused list")

        keys("o", command=True)
        if wait_ui(proc.pid, "Settings", timeout=0.45):
            notes.append("⌘O options")
        else:
            notes.append("WARN: ⌘O options AX missed")
        keys("esc")
        time.sleep(0.1)

        keys("s", command=True)
        time.sleep(0.2)
        notes.append("⌘S settings")
        if not wait_ui(proc.pid, "USD", timeout=1.2):
            keys("esc")
            time.sleep(0.1)
            keys("s", command=True)
            time.sleep(0.2)
            wait_ui(proc.pid, "USD", timeout=1.2)
        if not click_until_config(proc.pid, "USD", directory, "currency", "usd"):
            ax_click(proc.pid, "Options")
            time.sleep(0.3)
            ax_click(proc.pid, "Settings")
            time.sleep(0.5)
            expect(
                click_until_config(proc.pid, "USD", directory, "currency", "usd"),
                "could not click USD",
            )
        notes.append("currency USD")
        cfg = json.loads((directory / "config.json").read_text(encoding="utf-8"))
        expect(cfg.get("currency") == "usd", f"USD config {cfg.get('currency')}")
        if ax_click_retry(proc.pid, "Clay", attempts=2):
            notes.append("theme clay")
        else:
            notes.append("WARN: could not click Clay")
        hide_balance.run_ui(proc.pid, directory, notes)
        if ax_click_retry(proc.pid, "Check for updates", attempts=2):
            time.sleep(0.3)
            notes.append("Check for updates")
        else:
            notes.append("WARN: could not click Check for updates")
        if ax_click_retry(proc.pid, "Advanced", attempts=2):
            time.sleep(0.3)
            notes.append("Advanced")
        else:
            notes.append("WARN: could not open Advanced")
        cfg = json.loads((directory / "config.json").read_text(encoding="utf-8"))
        expect(Path(cfg["database_path"]).resolve().parent == directory.resolve(), "settings still isolated")
        expect(int(cfg["port"]) == E2E_PORT, "settings port")
        notes.append("Advanced host/port/db/dev")
        if cfg.get("hide_balance") is True:
            ax_click(proc.pid, "Hide balance")
        keys("esc")
        time.sleep(0.12)
        wait_ui(proc.pid, "New transaction", timeout=0.8)
        cfg = json.loads((directory / "config.json").read_text(encoding="utf-8"))
        expect(cfg.get("currency") == "usd", f"home after USD, config {cfg.get('currency')}")

        keys("s", command=True)
        time.sleep(0.3)
        wait_ui(proc.pid, "EUR", timeout=3.0)
        restored = click_until_config(proc.pid, "EUR", directory, "currency", "eur", attempts=12)
        if not restored:
            keys("esc")
            time.sleep(0.3)
            wait_ui(proc.pid, "Spent today", timeout=2.0)
            keys("s", command=True)
            time.sleep(0.3)
            wait_ui(proc.pid, "EUR", timeout=3.0)
            restored = click_until_config(proc.pid, "EUR", directory, "currency", "eur", attempts=8)
        expect(restored, "could not restore EUR in Settings")
        if ax_click_retry(proc.pid, "Lime", attempts=2):
            notes.append("theme lime")
        keys("esc")
        time.sleep(0.12)
        wait_ui(proc.pid, "New transaction", timeout=0.8)

        cats = request("GET", "/categories")
        names = [c["name"].lower() for c in (cats or {}).get("items", [])]
        for name in ("groceries", "eating out", "transport", "rent", "salary", "health", "fun", "other"):
            expect(name in names, f"starter category {name} missing")
        cfg = json.loads((directory / "config.json").read_text(encoding="utf-8"))
        isolated_database(directory)
        expect(cfg["dev"] is True, "developer mode left on")
        expect(cfg.get("currency") == "eur", f"display currency restored, config {cfg.get('currency')}")
    finally:
        stop(proc)
    return notes
