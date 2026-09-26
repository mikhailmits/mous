"""Accessibility, pid key events, and Mous binary helpers for headless UI e2e."""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

from e2e_mous.harness import Failed, ROOT, SWIFT, expect, log, request


def mous_bin_path(env: dict[str, str]) -> Path:
    subprocess.run(
        ["swift", "build", "--package-path", str(SWIFT), "--product", "Mous"],
        cwd=ROOT,
        env=env,
        check=True,
    )
    show = subprocess.run(
        ["swift", "build", "--package-path", str(SWIFT), "--show-bin-path", "--product", "Mous"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    path = Path(show.stdout.strip()) / "Mous"
    expect(path.is_file(), f"missing Mous binary at {path}")
    return path


def other_mous_pids() -> list[int]:
    completed = subprocess.run(["pgrep", "-x", "Mous"], capture_output=True, text=True, check=False)
    return [int(line) for line in completed.stdout.split() if line.strip().isdigit()]


def osa(script: str, *args: str, timeout: float = 8) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["osascript", "-", *args],
            input=script,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        log("WARN: osascript timed out")
        return subprocess.CompletedProcess(["osascript", "-", *args], 1, "", "timeout")


def mous_frames(pid: int) -> list[tuple[int, int, int, int]]:
    script = """
    on run argv
      set thePid to item 1 of argv as integer
      tell application "System Events"
        if not (exists (first process whose unix id is thePid)) then return ""
        tell (first process whose unix id is thePid)
          set chunks to {}
          repeat with w in windows
            try
              set p to position of w
              set s to size of w
              set end of chunks to ((item 1 of p as integer as text) & "," & (item 2 of p as integer as text) & "," & (item 1 of s as integer as text) & "," & (item 2 of s as integer as text))
            end try
          end repeat
          set AppleScript's text item delimiters to "|"
          return chunks as text
        end tell
      end tell
    end run
    """
    completed = osa(script, str(pid))
    raw = (completed.stdout or "").strip()
    frames: list[tuple[int, int, int, int]] = []
    if not raw:
        return frames
    for chunk in raw.split("|"):
        if "," not in chunk:
            continue
        try:
            x, y, w, h = (int(float(part)) for part in chunk.split(","))
        except ValueError:
            continue
        if w < 80 or h < 80:
            continue
        frames.append((x, y, w, h))
    return frames


def mous_frame(pid: int) -> tuple[int, int, int, int] | None:
    frames = mous_frames(pid)
    if not frames:
        return None
    x0 = min(f[0] for f in frames)
    y0 = min(f[1] for f in frames)
    x1 = max(f[0] + f[2] for f in frames)
    y1 = max(f[1] + f[3] for f in frames)
    return x0, y0, x1 - x0, y1 - y0



def wait_window(pid: int, timeout: float = 8.0) -> None:
    """Wait until System Events sees the e2e process window. Does not steal focus."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if mous_frame(pid) is not None:
            return
        time.sleep(0.15)
    raise Failed("e2e Mous window never appeared")



KEY_CODES = {
    "a": 0,
    "s": 1,
    "d": 2,
    "f": 3,
    "h": 4,
    "g": 5,
    "z": 6,
    "x": 7,
    "c": 8,
    "v": 9,
    "b": 11,
    "q": 12,
    "w": 13,
    "e": 14,
    "r": 15,
    "y": 16,
    "t": 17,
    "1": 18,
    "2": 19,
    "3": 20,
    "4": 21,
    "6": 22,
    "5": 23,
    "9": 25,
    "7": 26,
    "-": 27,
    "8": 28,
    "0": 29,
    "+": 69,  # keypad plus; headless ingest matches keyCode 69
    "o": 31,
    "u": 32,
    "i": 34,
    "p": 35,
    "l": 37,
    "j": 38,
    "k": 40,
    ".": 47,
    "tab": 48,
    " ": 49,
    "n": 45,
    "m": 46,
    "esc": 53,
    "return": 36,
    "delete": 51,
    "command": 55,
}
COMMAND_FLAG = 1 << 20  # kCGEventFlagMaskCommand
SHIFT_FLAG = 1 << 17  # kCGEventFlagMaskShift


def pid_flags(pid: int, command: bool) -> bool:
    """Post flagsChanged to pid (command hold for keycaps)."""
    flags = COMMAND_FLAG if command else 0
    script = """
    function run(argv) {
      ObjC.import('CoreGraphics');
      ObjC.import('ApplicationServices');
      if (!$.AXIsProcessTrusted()) return 'no-ax';
      var pid = Number(argv[0]);
      var flags = Number(argv[1]);
      var ev = $.CGEventCreateKeyboardEvent(null, 55, flags !== 0);
      $.CGEventSetType(ev, 12);
      $.CGEventSetFlags(ev, flags);
      $.CGEventPostToPid(pid, ev);
      return 'ok';
    }
    """
    completed = subprocess.run(
        ["osascript", "-l", "JavaScript", "-", str(pid), str(flags)],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode == 0 and "ok" in (completed.stdout or "")


def pid_mouse(pid: int, x: float, y_from_top: float) -> bool:
    """Mouse-moved to pid in CGWindowList coordinates (origin top-left)."""
    script = """
    function run(argv) {
      ObjC.import('CoreGraphics');
      ObjC.import('AppKit');
      var pid = Number(argv[0]);
      var x = Number(argv[1]);
      var yFromTop = Number(argv[2]);
      var h = $.NSScreen.mainScreen.frame.size.height;
      var ev = $.CGEventCreateMouseEvent(
        null, $.kCGEventMouseMoved, $.CGPointMake(x, h - yFromTop), 0
      );
      $.CGEventPostToPid(pid, ev);
      return 'ok';
    }
    """
    completed = subprocess.run(
        ["osascript", "-l", "JavaScript", "-", str(pid), str(x), str(y_from_top)],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode == 0 and "ok" in (completed.stdout or "")


def pid_key(pid: int, stroke: str, command: bool = False, phase: str = "both") -> bool:
    """Post a key event to the e2e pid without making it frontmost."""
    code = KEY_CODES.get(stroke)
    if code is None:
        if len(stroke) == 1 and stroke.isalpha():
            code = KEY_CODES.get(stroke.lower())
        if code is None:
            return False
    flags = COMMAND_FLAG if command else 0
    # Plus is shift-equals. Keypad plus (69) often never arrives as a character.
    if stroke == "+" and not command:
        code = 24
        flags |= SHIFT_FLAG
    script = """
    function run(argv) {
      ObjC.import('CoreGraphics');
      ObjC.import('ApplicationServices');
      if (!$.AXIsProcessTrusted()) return 'no-ax';
      var pid = Number(argv[0]);
      var code = Number(argv[1]);
      var flags = Number(argv[2]);
      var phase = argv[3];
      function post(down) {
        var ev = $.CGEventCreateKeyboardEvent(null, code, down);
        $.CGEventSetFlags(ev, flags);
        $.CGEventPostToPid(pid, ev);
      }
      if (phase === 'down' || phase === 'both') post(true);
      if (phase === 'up' || phase === 'both') post(false);
      return 'ok';
    }
    """
    completed = subprocess.run(
        ["osascript", "-l", "JavaScript", "-", str(pid), str(code), str(flags), phase],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode == 0 and "ok" in (completed.stdout or "")


def pid_type(pid: int, stroke: str) -> bool:
    """Post a string of keys in one process so the popup pass stays fast."""
    codes: list[str] = []
    flags: list[str] = []
    for char in stroke:
        code = KEY_CODES.get(char)
        flag = 0
        if char == "+":
            code = 24
            flag = SHIFT_FLAG
        if code is None:
            return False
        codes.append(str(code))
        flags.append(str(flag))
    script = """
    function run(argv) {
      ObjC.import('CoreGraphics');
      ObjC.import('Foundation');
      ObjC.import('ApplicationServices');
      if (!$.AXIsProcessTrusted()) return 'no-ax';
      var pid = Number(argv[0]);
      var codes = argv[1].split(',');
      var flags = argv[2].split(',');
      for (var i = 0; i < codes.length; i++) {
        var code = Number(codes[i]);
        var flag = Number(flags[i]);
        var down = $.CGEventCreateKeyboardEvent(null, code, true);
        $.CGEventSetFlags(down, flag);
        $.CGEventPostToPid(pid, down);
        var up = $.CGEventCreateKeyboardEvent(null, code, false);
        $.CGEventSetFlags(up, flag);
        $.CGEventPostToPid(pid, up);
        $.NSThread.sleepForTimeInterval(0.016);
      }
      return 'ok';
    }
    """
    completed = subprocess.run(
        ["osascript", "-l", "JavaScript", "-", str(pid), ",".join(codes), ",".join(flags)],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode == 0 and "ok" in (completed.stdout or "")


def send_keys(stroke: str, command: bool = False, pid: int | None = None) -> bool:
    if pid is not None:
        if command:
            pid_flags(pid, True)
            time.sleep(0.02)
        try:
            if len(stroke) > 1 and stroke not in KEY_CODES:
                return pid_type(pid, stroke)
            return pid_key(pid, stroke, command=command)
        finally:
            if command:
                pid_flags(pid, False)
    if stroke == "esc":
        src = "tell application \"System Events\" to key code 53"
    elif stroke == "return":
        src = "tell application \"System Events\" to key code 36"
    elif stroke == "delete":
        src = "tell application \"System Events\" to key code 51"
    elif command:
        src = f'tell application "System Events" to keystroke "{stroke}" using command down'
    else:
        src = f'tell application "System Events" to keystroke "{stroke}"'
    completed = subprocess.run(["osascript", "-e", src], capture_output=True, text=True, check=False)
    return completed.returncode == 0 and not completed.stderr


def front_keys(pid: int, stroke: str, command: bool = False) -> bool:
    """Type into the e2e pid. Does not steal focus."""
    wait_window(pid, timeout=2.0)
    return send_keys(stroke, command=command, pid=pid)


def hold_command(seconds: float, pid: int | None = None) -> bool:
    if pid is not None:
        if not pid_flags(pid, True):
            return False
        time.sleep(seconds)
        return pid_flags(pid, False)
    down = subprocess.run(
        ["osascript", "-e", 'tell application "System Events" to key down command'],
        capture_output=True,
        text=True,
        check=False,
    )
    time.sleep(seconds)
    up = subprocess.run(
        ["osascript", "-e", 'tell application "System Events" to key up command'],
        capture_output=True,
        text=True,
        check=False,
    )
    return down.returncode == 0 and up.returncode == 0 and not down.stderr and not up.stderr


def activate_mous(pid: int) -> None:
    src = (
        "tell application \"System Events\" to set frontmost of "
        f"(first process whose unix id is {pid}) to true"
    )
    subprocess.run(["osascript", "-e", src], capture_output=True, check=False)


def ax_button_names(pid: int) -> str:
    script = """
    on run argv
      set thePid to item 1 of argv as integer
      tell application "System Events"
        if not (exists (first process whose unix id is thePid)) then return ""
        tell (first process whose unix id is thePid)
          set names to {}
          repeat with w in windows
            try
              repeat with b in (every UI element of entire contents of w)
                try
                  set hay to ""
                  try
                    set hay to hay & (name of b as text)
                  end try
                  try
                    set hay to hay & "/" & (value of attribute "AXIdentifier" of b as text)
                  end try
                  if hay is not "" and hay is not "/" then set end of names to hay
                end try
              end repeat
            end try
          end repeat
          set AppleScript's text item delimiters to ", "
          return names as text
        end tell
      end tell
    end run
    """
    completed = osa(script, str(pid))
    return (completed.stdout or "").strip()


def ax_tree_text(pid: int) -> str:
    """Concatenated AX name/title/description/identifier/value for glyph checks."""
    script = """
    on run argv
      set thePid to item 1 of argv as integer
      tell application "System Events"
        if not (exists (first process whose unix id is thePid)) then return ""
        tell (first process whose unix id is thePid)
          set chunks to {}
          repeat with w in windows
            try
              repeat with ui in (entire contents of w as list)
                try
                  set hay to ""
                  try
                    set hay to hay & (name of ui as text) & " "
                  end try
                  try
                    set hay to hay & (value of attribute "AXTitle" of ui as text) & " "
                  end try
                  try
                    set hay to hay & (value of attribute "AXDescription" of ui as text) & " "
                  end try
                  try
                    set hay to hay & (value of attribute "AXIdentifier" of ui as text) & " "
                  end try
                  try
                    set hay to hay & (value of ui as text) & " "
                  end try
                  if hay is not "" then set end of chunks to hay
                end try
              end repeat
            end try
          end repeat
          set AppleScript's text item delimiters to " | "
          return chunks as text
        end tell
      end tell
    end run
    """
    completed = osa(script, str(pid))
    return (completed.stdout or "").strip()


def ax_click(pid: int, needle: str) -> bool:
    """Press a nested control matching needle on name, title, identifier, or help."""
    return _ax_press(pid, needle, checkboxes_first=False)


def ax_click_toggle(pid: int, needle: str) -> bool:
    """Press a checkbox/switch matching needle (Settings toggles)."""
    return _ax_press(pid, needle, checkboxes_first=True)


def _ax_press_identifier(pid: int, needle: str) -> bool:
    """Fast path: identifier or button name, no full-tree attribute scrape."""
    script = """
    on run argv
      set thePid to item 1 of argv as integer
      set theNeedle to item 2 of argv
      tell application "System Events"
        if not (exists (first process whose unix id is thePid)) then return "no"
        tell (first process whose unix id is thePid)
          repeat with w in windows
            try
              tell w
                try
                  set target to (first UI element of entire contents whose value of attribute "AXIdentifier" is theNeedle)
                  try
                    perform action "AXPress" of target
                    return "ok"
                  end try
                  click target
                  return "ok"
                end try
                try
                  click (first button whose name is theNeedle)
                  return "ok"
                end try
              end tell
            end try
          end repeat
        end tell
      end tell
      return "missing"
    end run
    """
    completed = osa(script, str(pid), needle, timeout=6)
    return (completed.stdout or "").strip() == "ok"


def _ax_press(pid: int, needle: str, *, checkboxes_first: bool) -> bool:
    if not checkboxes_first and _ax_press_identifier(pid, needle):
        return True
    script = """
    on run argv
      set thePid to item 1 of argv as integer
      set theNeedle to item 2 of argv
      set onlyBox to (item 3 of argv is "checkbox")
      tell application "System Events"
        if not (exists (first process whose unix id is thePid)) then return "no-process"
        tell (first process whose unix id is thePid)
          if (count of windows) is 0 then return "missing"
          set winCount to count of windows
          repeat with wi from winCount to 1 by -1
            tell window wi
              try
                set elems to entire contents as list
                repeat with passNum from 1 to 2
                  repeat with ui in elems
                    try
                      set r to ""
                      try
                        set r to (role of ui as text)
                      end try
                      if onlyBox then
                        if r is not "checkbox" and r is not "check box" then
                          error "skip"
                        end if
                      end if
                      if passNum is 1 then
                        try
                          set ident to (value of attribute "AXIdentifier" of ui as text)
                          if ident is theNeedle then
                            try
                              perform action "AXPress" of ui
                              return "ok"
                            end try
                            try
                              click ui
                              return "ok"
                            end try
                          end if
                        end try
                      else
                        set hay to ""
                        try
                          set hay to hay & (name of ui as text) & " "
                        end try
                        try
                          set hay to hay & (value of attribute "AXTitle" of ui as text) & " "
                        end try
                        try
                          set hay to hay & (value of attribute "AXDescription" of ui as text) & " "
                        end try
                        try
                          set hay to hay & (value of attribute "AXIdentifier" of ui as text) & " "
                        end try
                        try
                          set hay to hay & (value of attribute "AXHelp" of ui as text) & " "
                        end try
                        if hay contains theNeedle then
                          try
                            perform action "AXPress" of ui
                            return "ok"
                          end try
                          try
                            click ui
                            return "ok"
                          end try
                        end if
                      end if
                    end try
                  end repeat
                end repeat
              end try
            end tell
          end repeat
          return "missing"
        end tell
      end tell
    end run
    """
    mode = "checkbox" if checkboxes_first else "any"
    try:
        completed = osa(script, str(pid), needle, mode, timeout=16)
    except subprocess.TimeoutExpired:
        log(f"WARN: AX click timed out on {needle}")
        return False
    if (completed.stdout or "").strip() == "ok":
        return True
    if checkboxes_first:
        return _ax_press(pid, needle, checkboxes_first=False)
    return False


def ax_click_retry(pid: int, needle: str, attempts: int = 4) -> bool:
    for _ in range(attempts):
        if ax_click(pid, needle):
            return True
        time.sleep(0.35)
    return False


def click_until_config(
    pid: int,
    needle: str,
    directory: Path,
    key: str,
    want: object,
    attempts: int = 8,
    *,
    toggle: bool = False,
) -> bool:
    """Press `needle` until config.json `key` equals `want`."""
    from e2e_mous.harness import read_config

    if read_config(directory).get(key) == want:
        return True
    press = ax_click_toggle if toggle else ax_click
    for _ in range(attempts):
        press(pid, needle)
        time.sleep(0.12)
        if read_config(directory).get(key) == want:
            return True
    return False


def ax_has(pid: int, needle: str) -> bool:
    """True if any AX name/identifier/description in the pid contains needle."""
    script = """
    on run argv
      set thePid to item 1 of argv as integer
      set theNeedle to item 2 of argv
      tell application "System Events"
        if not (exists (first process whose unix id is thePid)) then return "no"
        tell (first process whose unix id is thePid)
          if (count of windows) is 0 then return "no"
          set winCount to count of windows
          repeat with wi from winCount to 1 by -1
            tell window wi
              try
                set elems to entire contents as list
                repeat with ui in elems
                  try
                    set hay to ""
                    try
                      set hay to hay & (name of ui as text) & " "
                    end try
                    try
                      set hay to hay & (value of attribute "AXTitle" of ui as text) & " "
                    end try
                    try
                      set hay to hay & (value of attribute "AXDescription" of ui as text) & " "
                    end try
                    try
                      set hay to hay & (value of attribute "AXIdentifier" of ui as text) & " "
                    end try
                    try
                      set hay to hay & (value of ui as text) & " "
                    end try
                    if hay contains theNeedle then return "ok"
                  end try
                end repeat
              end try
            end tell
          end repeat
          return "no"
        end tell
      end tell
    end run
    """
    completed = osa(script, str(pid), needle)
    return (completed.stdout or "").strip() == "ok"


def wait_ui(pid: int, needle: str, timeout: float = 4.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if ax_has(pid, needle):
            return True
        time.sleep(0.35)
    return False


def move_mouse(x: int, y: int) -> bool:
    script = """
    function run(argv) {
      ObjC.import('CoreGraphics');
      ObjC.import('AppKit');
      var x = Number(argv[0]);
      var yFromTop = Number(argv[1]);
      var h = $.NSScreen.mainScreen.frame.size.height;
      var ev = $.CGEventCreateMouseEvent(null, $.kCGEventMouseMoved, $.CGPointMake(x, h - yFromTop), 0);
      $.CGEventPost($.kCGHIDEventTap, ev);
      return 'ok';
    }
    """
    completed = subprocess.run(
        ["osascript", "-l", "JavaScript", "-", str(x), str(y)],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode == 0 and "ok" in (completed.stdout or "")


def hover_in_window(pid: int, x_frac: float, y_frac: float) -> bool:
    """Post mouse-moved to the pid. Does not move the user's cursor."""
    frame = mous_frame(pid)
    if frame is None:
        return False
    x, y, w, h = frame
    return pid_mouse(pid, x + w * x_frac, y + h * y_frac)


def wait_demo_coffee_posted(timeout: float = 8.0) -> bool:
    """Seed posts one -4 coffee; the demo line posts the second, then clears the field."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        txs = request("GET", "/transactions")
        n = 0
        for row in (txs or {}).get("items", []):
            if str(row.get("name") or "").lower() != "coffee":
                continue
            try:
                if abs(float(row.get("value") or 0) + 4) < 1e-6:
                    n += 1
            except (TypeError, ValueError):
                continue
        if n >= 2:
            return True
        time.sleep(0.25)
    return False
