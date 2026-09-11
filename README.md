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

```
-4.50 coffee with dave      → spent €4.50
-23.10 groceries            → spent €23.10
+2600 salary                → got €2,600
-24uah taxi                 → spent 24 hryvnia (any currency you add)
```

![The mous popup: spent today, money left, month total and saved percent](docs/main.png)

## Oh.. Cool things btw

You've got two shortcuts - cmd + m and cmd + x, first one shows the monthly money operations and the second one shows your most expensive spendings throughout the month, so don't forget to pay attention to those!

![History tip listing this month's transactions grouped by day](docs/history.png)

![Most expensive tip ranking categories by spend](docs/expensive.png)

## For those who are interested - architecture

A web server listens on a port and exposes an API with all the functionality: listing transactions, creating them, managing accounts, currencies, categories, and so on. The client — the macOS app — talks to that API, and that's how the figures end up on a simple page.

The server is FastAPI with SQLite (`src/mous`) on `127.0.0.1:8000`. The client is a native Swift app (`macos/Mous`): a borderless popup that asks the API for data and renders it. The app does not store the books itself; it only talks to this local server.

## Run it

Backend (Docker):

```sh
docker compose up -d
```

App (macOS 14+, Swift toolchain):

```sh
uv run mous dev     # builds and launches the popup
```

Or without Docker, run the API directly:

```sh
uv run mous serve
```

## Accessing the API directly

The app uses a local HTTP API at `http://127.0.0.1:8000`. Once the server is running, interactive docs are at `http://127.0.0.1:8000/docs`.

```sh
# add a category and a tagged expense
curl -X POST 127.0.0.1:8000/categories -H 'Content-Type: application/json' \
     -d '{"name": "food"}'
curl -X POST 127.0.0.1:8000/transactions -H 'Content-Type: application/json' \
     -d '{"name": "groceries", "value": -23.10, "currency_id": 1, "category_id": 1}'
```

Values are signed: negative is an expense, positive is income, zero is not a
transaction.

## Development

```sh
uv sync                                                  # python deps
uv run mous serve                                        # API on :8000
swift run --package-path macos/Mous MousCoreCheck        # swift checks
swift build --package-path macos/Mous --product Mous     # build the app
```
