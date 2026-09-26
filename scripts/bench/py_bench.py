#!/usr/bin/env python3
"""Warm-path latency/throughput benchmark for the Python FastAPI baseline.

Mirror of the Rust `mous-bench` client: issues `--count` requests of `--op`
over HTTP against a running mous API and reports p50/p90/p99 + throughput in
the same `RESULT ...` line format the bench runner parses.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.request
from urllib.error import HTTPError


def _request(method: str, url: str, body: dict | None = None) -> bytes:
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read()
    except HTTPError as exc:
        return exc.read()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--op", default="ping")
    parser.add_argument("--count", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=1000)
    parser.add_argument("--base", default="http://127.0.0.1:18999")
    args = parser.parse_args()

    base = args.base.rstrip("/")
    new_tx = {"name": "bench", "value": -1.23, "currency_id": 1}

    seeded_ids: list[int] = []
    if args.op in ("get", "list"):
        for _ in range(args.seed):
            raw = _request("POST", f"{base}/transactions", new_tx)
            try:
                seeded_ids.append(json.loads(raw)["id"])
            except Exception:
                pass

    def do(i: int) -> None:
        if args.op == "ping":
            _request("GET", f"{base}/health")
        elif args.op == "create":
            _request("POST", f"{base}/transactions", new_tx)
        elif args.op == "get":
            tid = seeded_ids[i % max(len(seeded_ids), 1)]
            _request("GET", f"{base}/transactions/{tid}")
        elif args.op == "list":
            _request("GET", f"{base}/transactions")
        else:
            raise SystemExit(f"unknown op {args.op}")

    for i in range(min(args.count, 200)):  # warmup
        do(i)

    latencies_us: list[float] = []
    wall = time.perf_counter()
    for i in range(args.count):
        t0 = time.perf_counter()
        do(i)
        latencies_us.append((time.perf_counter() - t0) * 1e6)
    total = time.perf_counter() - wall

    latencies_us.sort()

    def pct(p: float) -> float:
        if not latencies_us:
            return 0.0
        idx = round((p / 100.0) * (len(latencies_us) - 1))
        return latencies_us[min(idx, len(latencies_us) - 1)]

    mean = sum(latencies_us) / len(latencies_us) if latencies_us else 0.0
    thr = args.count / total if total else 0.0
    print(
        f"RESULT impl=python op={args.op} count={args.count} "
        f"mean_us={mean:.2f} p50_us={pct(50):.2f} p90_us={pct(90):.2f} "
        f"p99_us={pct(99):.2f} throughput_rps={thr:.0f}"
    )


if __name__ == "__main__":
    main()
