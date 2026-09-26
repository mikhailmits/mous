#!/usr/bin/env bash
# Benchmark the Rust backend (mousd over a Unix socket + postcard) against the
# Python FastAPI baseline (HTTP/JSON over TCP loopback). Both use SQLite.
#
# Emits RESULT lines (parsed by summarize.py) plus server RSS, and leaves a
# raw log the summarizer turns into a markdown table.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_BIN="$ROOT/rust/target/release"
VENV_PY="$ROOT/.venv/bin/python"
OUT="${1:-/opt/cursor/artifacts}"
RAW="$OUT/bench_raw.log"
mkdir -p "$OUT"
: > "$RAW"

PY_PORT=18999
PY_DIR="$(mktemp -d /tmp/mous-bench-py.XXXX)"
RS_DIR="$(mktemp -d /tmp/mous-bench-rs.XXXX)"
PY_PID=""
RS_PID=""

log() { echo "$@" | tee -a "$RAW"; }

cleanup() {
    [ -n "$PY_PID" ] && kill "$PY_PID" 2>/dev/null
    [ -n "$RS_PID" ] && kill "$RS_PID" 2>/dev/null
}
trap cleanup EXIT

# ---- start Python baseline -------------------------------------------------
log "== starting Python FastAPI baseline on :$PY_PORT =="
MOUS_CONFIG_DIR="$PY_DIR" MOUS_DATABASE_URL="sqlite:///$PY_DIR/data.db" \
    "$VENV_PY" -c "from mous.api.app import run; run(host='127.0.0.1', port=$PY_PORT)" \
    >"$PY_DIR/server.log" 2>&1 &
PY_PID=$!
for _ in $(seq 1 100); do
    if curl -sf "http://127.0.0.1:$PY_PORT/health" >/dev/null 2>&1; then break; fi
    sleep 0.1
done
curl -sf "http://127.0.0.1:$PY_PORT/health" >/dev/null 2>&1 || { log "python API failed to start"; cat "$PY_DIR/server.log"; exit 1; }
log "python API up (pid $PY_PID)"

# ---- start Rust daemon -----------------------------------------------------
log "== starting Rust mousd (unix socket) =="
export MOUS_CONFIG_DIR="$RS_DIR" MOUS_RUNTIME_DIR="$RS_DIR" \
       MOUS_DB="$RS_DIR/data.db" MOUS_SOCKET="$RS_DIR/mousd.sock" \
       MOUS_IDLE_TIMEOUT=0 MOUSD_BIN="$RUST_BIN/mousd"
"$RUST_BIN/mousd" --foreground >"$RS_DIR/daemon.log" 2>&1 &
RS_PID=$!
for _ in $(seq 1 100); do
    [ -S "$MOUS_SOCKET" ] && break
    sleep 0.1
done
[ -S "$MOUS_SOCKET" ] || { log "rust daemon failed to start"; cat "$RS_DIR/daemon.log"; exit 1; }
log "rust daemon up (pid $RS_PID)"

# ---- warm latency / throughput ---------------------------------------------
for op in ping create get list; do
    case "$op" in
        ping)   count=20000; seed=0 ;;
        create) count=10000; seed=0 ;;
        get)    count=20000; seed=2000 ;;
        list)   count=1000;  seed=2000 ;;
    esac
    log "== warm op=$op count=$count seed=$seed =="
    "$RUST_BIN/mous-bench" --op "$op" --count "$count" --seed "$seed" | tee -a "$RAW"
    python3 "$ROOT/scripts/bench/py_bench.py" --op "$op" --count "$count" --seed "$seed" \
        --base "http://127.0.0.1:$PY_PORT" | tee -a "$RAW"
done

# ---- cold start (per-invocation) -------------------------------------------
log "== cold start: single client invocation (process launch + one request) =="
python3 "$ROOT/scripts/bench/coldstart.py" --impl rust --op coldstart_get --count 300 -- \
    "$RUST_BIN/mou" --id 1 --json | tee -a "$RAW"
python3 "$ROOT/scripts/bench/coldstart.py" --impl python --op coldstart_get --count 300 -- \
    python3 "$ROOT/scripts/bench/py_oneshot.py" get 1 | tee -a "$RAW"

# ---- resident memory (RSS) -------------------------------------------------
log "== server resident memory (RSS) =="
RS_RSS=$(ps -o rss= -p "$RS_PID" | tr -d ' ')
PY_RSS=$(ps -o rss= -p "$PY_PID" | tr -d ' ')
log "RSS impl=rust kib=${RS_RSS}"
log "RSS impl=python kib=${PY_RSS}"

log "== done =="
