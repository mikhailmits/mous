//! Warm-path latency/throughput benchmark for `mousd`.
//!
//! Opens one persistent connection to the daemon socket and issues `--count`
//! requests of `--op`, reporting p50/p90/p99 latency and throughput. This is
//! the mirror of `scripts/bench/py_bench.py`, which does the same against the
//! Python FastAPI baseline over HTTP.

use std::os::unix::net::UnixStream;
use std::time::Instant;

use mous_proto::{paths, read_msg, write_msg, NewTx, Request, Response, TxFilter};

struct Opts {
    op: String,
    count: usize,
    seed: usize,
}

fn parse() -> Opts {
    let mut op = "ping".to_string();
    let mut count = 5000usize;
    let mut seed = 1000usize;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--op" => op = args.next().unwrap_or(op),
            "--count" => count = args.next().and_then(|v| v.parse().ok()).unwrap_or(count),
            "--seed" => seed = args.next().and_then(|v| v.parse().ok()).unwrap_or(seed),
            _ => {}
        }
    }
    Opts { op, count, seed }
}

fn connect() -> UnixStream {
    let sock = paths::socket_path();
    UnixStream::connect(&sock).unwrap_or_else(|e| panic!("connect {}: {e}", sock.display()))
}

fn roundtrip(stream: &mut UnixStream, req: &Request) -> Response {
    write_msg(stream, req).expect("write");
    read_msg(stream).expect("read")
}

fn new_tx() -> Request {
    Request::TxNew(NewTx {
        amount: -1.23,
        name: Some("bench".into()),
        currency: None,
        category: None,
        recurring: None,
        occurred_on: None,
    })
}

fn main() {
    let opts = parse();
    let mut stream = connect();

    // Seed rows for get/list benchmarks.
    let mut seeded_ids: Vec<i64> = Vec::new();
    if opts.op == "get" || opts.op == "list" {
        for _ in 0..opts.seed {
            if let Response::Tx(tx) = roundtrip(&mut stream, &new_tx()) {
                seeded_ids.push(tx.id);
            }
        }
    }

    let build = |i: usize| -> Request {
        match opts.op.as_str() {
            "ping" => Request::Ping,
            "create" => new_tx(),
            "get" => {
                let id = seeded_ids[i % seeded_ids.len().max(1)];
                Request::TxGet(id)
            }
            "list" => Request::TxList(TxFilter::default()),
            other => panic!("unknown op {other}"),
        }
    };

    // Warmup.
    for i in 0..opts.count.min(200) {
        let _ = roundtrip(&mut stream, &build(i));
    }

    let mut latencies_ns: Vec<u128> = Vec::with_capacity(opts.count);
    let wall = Instant::now();
    for i in 0..opts.count {
        let req = build(i);
        let t0 = Instant::now();
        let _ = roundtrip(&mut stream, &req);
        latencies_ns.push(t0.elapsed().as_nanos());
    }
    let total = wall.elapsed().as_secs_f64();

    report("rust", &opts.op, opts.count, total, &mut latencies_ns);
}

fn report(impl_name: &str, op: &str, count: usize, total_s: f64, lat: &mut [u128]) {
    lat.sort_unstable();
    let pct = |p: f64| -> f64 {
        if lat.is_empty() {
            return 0.0;
        }
        let idx = ((p / 100.0) * (lat.len() as f64 - 1.0)).round() as usize;
        lat[idx.min(lat.len() - 1)] as f64 / 1000.0 // µs
    };
    let mean_us = if lat.is_empty() {
        0.0
    } else {
        lat.iter().sum::<u128>() as f64 / lat.len() as f64 / 1000.0
    };
    let thr = count as f64 / total_s;
    // Machine-readable line consumed by the bench runner.
    println!(
        "RESULT impl={impl_name} op={op} count={count} mean_us={mean:.2} p50_us={p50:.2} p90_us={p90:.2} p99_us={p99:.2} throughput_rps={thr:.0}",
        mean = mean_us,
        p50 = pct(50.0),
        p90 = pct(90.0),
        p99 = pct(99.0),
    );
}
