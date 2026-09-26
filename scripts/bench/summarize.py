#!/usr/bin/env python3
"""Turn bench_raw.log RESULT/RSS lines into a markdown report."""

from __future__ import annotations

import sys
from pathlib import Path


def parse_result(line: str) -> dict[str, str]:
    fields = {}
    for tok in line.split()[1:]:
        if "=" in tok:
            k, v = tok.split("=", 1)
            fields[k] = v
    return fields


def main() -> None:
    raw = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/opt/cursor/artifacts/bench_raw.log")
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else raw.with_name("bench_results.md")

    results: dict[tuple[str, str], dict[str, str]] = {}
    rss: dict[str, int] = {}
    for line in raw.read_text().splitlines():
        if line.startswith("RESULT "):
            f = parse_result(line)
            results[(f["op"], f["impl"])] = f
        elif line.startswith("RSS "):
            f = parse_result(line)
            rss[f["impl"]] = int(f["kib"])

    ops = []
    for (op, _impl) in results:
        if op not in ops:
            ops.append(op)

    lines: list[str] = []
    lines.append("# mous backend benchmark: Rust vs Python\n")
    lines.append(
        "Python baseline = FastAPI HTTP/JSON over TCP loopback. "
        "Rust = `mousd` over a Unix domain socket with length-prefixed `postcard` frames. "
        "Both persist to SQLite. Lower latency and higher throughput are better.\n"
    )
    lines.append("## Warm-path latency and throughput\n")
    lines.append(
        "| Operation | Impl | mean (µs) | p50 (µs) | p90 (µs) | p99 (µs) | throughput (req/s) |"
    )
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    speedups: list[tuple[str, float, float]] = []
    for op in ops:
        r = results.get((op, "rust"))
        p = results.get((op, "python"))
        for impl, f in (("rust", r), ("python", p)):
            if not f:
                continue
            lines.append(
                f"| {op} | {impl} | {float(f['mean_us']):.1f} | {float(f['p50_us']):.1f} | "
                f"{float(f['p90_us']):.1f} | {float(f['p99_us']):.1f} | {int(float(f['throughput_rps'])):,} |"
            )
        if r and p:
            lat_speedup = float(p["p50_us"]) / float(r["p50_us"]) if float(r["p50_us"]) else 0.0
            thr_speedup = (
                float(r["throughput_rps"]) / float(p["throughput_rps"])
                if float(p["throughput_rps"])
                else 0.0
            )
            speedups.append((op, lat_speedup, thr_speedup))

    lines.append("\n## Speedup (Rust vs Python)\n")
    lines.append("| Operation | p50 latency speedup | throughput speedup |")
    lines.append("| --- | ---: | ---: |")
    for op, lat, thr in speedups:
        lines.append(f"| {op} | {lat:.1f}× | {thr:.1f}× |")

    if rss:
        lines.append("\n## Resident memory (idle-ish server)\n")
        lines.append("| Impl | RSS (MiB) |")
        lines.append("| --- | ---: |")
        for impl in ("rust", "python"):
            if impl in rss:
                lines.append(f"| {impl} | {rss[impl] / 1024:.1f} |")
        if "rust" in rss and "python" in rss and rss["rust"]:
            lines.append(
                f"\nPython uses **{rss['python'] / rss['rust']:.1f}×** the memory of the Rust daemon."
            )

    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out}")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
