#!/usr/bin/env python3
"""Measure per-invocation (cold-start) wall time of a command.

Runs `command` `--count` times as fresh subprocesses and reports
p50/p90/p99 + throughput in the same `RESULT ...` format as the warm benches.
"""

from __future__ import annotations

import argparse
import subprocess
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--impl", required=True)
    parser.add_argument("--op", default="coldstart")
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    cmd = args.command
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        raise SystemExit("no command given")

    # Warmup.
    for _ in range(min(args.count, 20)):
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    latencies_us: list[float] = []
    wall = time.perf_counter()
    for _ in range(args.count):
        t0 = time.perf_counter()
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        latencies_us.append((time.perf_counter() - t0) * 1e6)
    total = time.perf_counter() - wall

    latencies_us.sort()

    def pct(p: float) -> float:
        idx = round((p / 100.0) * (len(latencies_us) - 1))
        return latencies_us[min(idx, len(latencies_us) - 1)]

    mean = sum(latencies_us) / len(latencies_us)
    thr = args.count / total if total else 0.0
    print(
        f"RESULT impl={args.impl} op={args.op} count={args.count} "
        f"mean_us={mean:.2f} p50_us={pct(50):.2f} p90_us={pct(90):.2f} "
        f"p99_us={pct(99):.2f} throughput_rps={thr:.0f}"
    )


if __name__ == "__main__":
    main()
