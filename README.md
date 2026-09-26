# mous

A tiny box where finances are spinning

![Typing a spending line into mous and watching the totals update](docs/demo.gif)

## Install it

macOS only (14+). This is a work in progress.

Just tell your agent to install the app!

```
Download the latest Mous .dmg from https://github.com/mikhailmits/mous/releases, open it, drag Mous onto Applications, then run: xattr -cr /Applications/Mous.app && open /Applications/Mous.app
macOS 14+ only; Windows and Linux are not supported yet. This is a work in progress. The app is not notarized, so macOS will block it until that command clears quarantine.
```

Or do it yourself:

1. Get the [latest release](https://github.com/mikhailmits/mous/releases/latest), open the `.dmg`, drag **Mous** onto **Applications**.
2. macOS will refuse to open it (not notarized yet). Clear that once:

```sh
xattr -cr /Applications/Mous.app && open /Applications/Mous.app
```

## What it is

mous is a tiny window where you quickly see all your spendings and things you may optimize. In mous you have only two components - the dashboard where you see all finances analysis and the input bar where you note your finances to the app

![The mous popup: spent today, money left, month total and saved percent](docs/main.png)

## Oh.. Cool things btw

You've got two shortcuts - <kbd>⌘</kbd> <kbd>M</kbd> and <kbd>⌘</kbd> <kbd>X</kbd>, first one shows the monthly money operations and the second one shows your most expensive spendings throughout the month, so don't forget to pay attention to those!

![History tip listing this month's transactions grouped by day](docs/history.png)

![Most expensive tip ranking categories by spend](docs/expensive.png)

## For those who are interested - architecture

The backend has been rewritten in Rust (`rust/`). Instead of an HTTP API, mous
now exposes a **CLI** (`mou`) backed by a long-lived **daemon** (`mousd`). The
daemon owns the SQLite books and all business logic; the CLI is just one
front-end (a web or GUI front-end can talk to the same daemon later).

- **`mousd`** — the server. Listens on a **Unix domain socket** and speaks a
  compact length-prefixed [`postcard`](https://docs.rs/postcard) binary
  protocol (no HTTP, no JSON). It holds a single-instance lock, self-exits
  after an idle timeout, and stores everything in SQLite (WAL).
- **`mou`** — the client. On first use it **auto-spawns** `mousd` (double-fork
  detach), so you never start a server yourself. It renders as a table
  (default), `--json`, or `--yaml`.
- **`mous-core`** — the domain logic and store, shared by the daemon.
- **`mous-proto`** — the wire types + framing, shared by client and daemon.

Transactions store their **native currency**; listings **display everything in
the default currency** (EUR/USD/UAH stub FX). Values are signed: negative is an
expense, positive is income, zero is not a transaction.

The previous Python FastAPI service is kept under `src/mous` purely as the
benchmark baseline; the macOS Swift app has not yet been migrated to the new
protocol.

## Run it

Build the workspace, then use `mou` — the daemon starts on demand:

```sh
cargo build --release --manifest-path rust/Cargo.toml
export PATH="$PWD/rust/target/release:$PATH"

mou new -23.10 --name groceries --ctg food     # an expense (auto-creates 'food')
mou new 110 --name salary --curr usd           # income in USD (auto-creates 'usd')
mou new -9.99 --name netflix --recurring "0 0 1 * *"
mou --all                                       # list, shown in the default currency
mou --all --curr usd uah                        # filter by one or more currencies
mou --all --since 2026-09-01 --until 2026-09-30 # filter by date
mou --id 2 --edit-amount -30 --ctg dining       # edit a transaction
mou -d --id 2                                    # delete a transaction

mou cur --all                                    # currencies
mou cur --set-default usd                         # switch the display currency
```

Output format: add `--json` or `--yaml` to any command.

## Development

```sh
# Rust backend (the product)
cargo build   --manifest-path rust/Cargo.toml
cargo test    --manifest-path rust/Cargo.toml
cargo clippy  --manifest-path rust/Cargo.toml --all-targets -- -D warnings

# Benchmarks (Rust vs the Python baseline) -> /opt/cursor/artifacts
uv sync                                # python baseline deps
bash scripts/bench/run_bench.sh /tmp/bench-out
python3 scripts/bench/summarize.py /tmp/bench-out/bench_raw.log

# macOS app (not yet migrated to the new protocol)
swift build --package-path macos/Mous --product Mous
```
