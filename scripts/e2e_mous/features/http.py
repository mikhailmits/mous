"""HTTP API e2e: every router path, validation, FX conversion, subscriptions."""

from __future__ import annotations

import json
from datetime import date, timedelta

from e2e_mous.harness import (
    API_SPEC_PATHS,
    expect,
    fetch_bytes,
    request,
    unix_midnight,
)

def run(env: dict[str, str]) -> None:
    today = unix_midnight(date.today())
    yesterday = unix_midnight(date.today() - timedelta(days=1))
    from mous.fx import convert as fx_convert

    health = request("GET", "/health")
    expect(health == {"status": "ok"}, f"health {health}")

    spec = json.loads(fetch_bytes("/openapi.json"))
    expect(spec.get("info", {}).get("title") == "mous", "openapi title")
    paths = spec.get("paths") or {}
    for item in API_SPEC_PATHS:
        expect(item in paths, f"openapi missing {item}")
    docs = fetch_bytes("/docs")
    expect(b"swagger" in docs.lower() or b"openapi" in docs.lower(), "docs html")

    accounts = request("GET", "/accounts")
    expect(accounts and accounts["count"] >= 1, "missing default account")
    main_id = next(a["id"] for a in accounts["items"] if a["name"] == "main")
    got_main = request("GET", f"/accounts/{main_id}")
    expect(got_main and got_main["name"] == "main", "get account by id")
    missing_account = request("GET", "/accounts/999999", expected=404)
    expect(missing_account and missing_account["error"] == "not_found", "missing account")
    dup_account = request("POST", "/accounts", body={"name": "main"}, expected=409)
    expect(dup_account and dup_account["error"] == "conflict", "duplicate account")
    too_long_account = request("POST", "/accounts", body={"name": "x" * 65}, expected=422)
    expect(too_long_account and too_long_account["error"] == "validation_error", "account name too long")

    currencies = request("GET", "/currencies")
    expect(currencies and any(c["symbol"] == "eur" for c in currencies["items"]), "missing eur")
    by_symbol_row = {c["symbol"]: c for c in currencies["items"]}
    expect("usd" in by_symbol_row and "uah" in by_symbol_row, f"starter currencies {list(by_symbol_row)}")
    eur_id = by_symbol_row["eur"]["id"]
    usd = by_symbol_row["usd"]
    by_id = request("GET", f"/currencies/{eur_id}")
    expect(by_id and by_id["symbol"] == "eur", "get eur by id")

    expect(usd and usd["symbol"] == "usd", "starter usd")
    dup_usd = request(
        "POST",
        "/currencies",
        body={"symbol": "usd", "name": "US Dollar 2", "is_default": False},
        expected=409,
    )
    expect(dup_usd and dup_usd["error"] == "conflict", "duplicate currency")
    patched = request("PATCH", f"/currencies/{usd['id']}", body={"is_default": True})
    expect(patched and patched["is_default"] is True, "usd default")
    dup_default = request(
        "POST",
        "/currencies",
        body={"symbol": "usd", "name": "US Dollar 3", "is_default": True},
        expected=409,
    )
    expect(dup_default and dup_default["error"] == "conflict", "duplicate default currency")
    still_usd = request("GET", f"/currencies/{usd['id']}")
    expect(still_usd and still_usd["is_default"] is True, "failed default create keeps usd")
    listed_fx = request("GET", "/currencies")
    defaults = [c for c in (listed_fx or {}).get("items", []) if c.get("is_default")]
    expect(
        len(defaults) == 1 and defaults[0]["id"] == usd["id"],
        "exactly one default after conflict",
    )
    renamed_fx = request(
        "PATCH",
        f"/currencies/{usd['id']}",
        body={"name": "Dollar", "symbol": "usd"},
    )
    expect(renamed_fx and renamed_fx["name"] == "Dollar", "patch currency name")
    request("PATCH", f"/currencies/{eur_id}", body={"is_default": True})
    last_default = request(
        "PATCH",
        f"/currencies/{eur_id}",
        body={"is_default": False},
        expected=409,
    )
    expect(last_default and last_default["error"] == "last_default", "last default kept")
    blocked_default = request("DELETE", f"/currencies/{eur_id}", expected=409)
    expect(blocked_default and blocked_default["error"] == "last_default", "cannot delete default")
    by_symbol = request("GET", "/currencies/eur")
    expect(by_symbol and by_symbol["id"] == eur_id, "get eur by symbol")
    missing_fx = request("GET", "/currencies/nope", expected=404)
    expect(missing_fx and missing_fx["error"] == "not_found", "missing currency")

    gbp = request(
        "POST",
        "/currencies",
        body={"symbol": "gbp", "name": "Pound", "is_default": False},
        expected=201,
    )
    expect(gbp is not None, "create gbp")

    starter = request("GET", "/categories")
    starter_names = {c["name"] for c in (starter or {}).get("items", [])}
    for name in ("groceries", "eating out", "transport", "rent", "salary", "health", "fun", "other"):
        expect(name in starter_names, f"missing starter category {name}")

    food = request("POST", "/categories", body={"name": "food"}, expected=201)
    expect(food and food["name"] == "food", "create food")
    by_name = request("GET", "/categories/food")
    expect(by_name and by_name["id"] == food["id"], "get category by name")
    by_cat_id = request("GET", f"/categories/{food['id']}")
    expect(by_cat_id and by_cat_id["id"] == food["id"], "get category by id")
    meals = request("PATCH", f"/categories/{food['id']}", body={"name": "meals"})
    expect(meals and meals["name"] == "meals", "rename category")
    request("PATCH", f"/categories/{food['id']}", body={"name": "food"})
    dup = request("POST", "/categories", body={"name": "food"}, expected=409)
    expect(dup and dup["error"] == "conflict", "duplicate category")
    long_cat = request("POST", "/categories", body={"name": "c" * 31}, expected=422)
    expect(long_cat and long_cat["error"] == "validation_error", "category name too long")

    salary = request(
        "POST",
        "/transactions",
        body={
            "name": "salary",
            "value": 2000,
            "currency_id": eur_id,
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    omitted_account = request(
        "POST",
        "/transactions",
        body={"name": "default-account", "value": -1, "currency_id": eur_id},
        expected=201,
    )
    expect(omitted_account and omitted_account["account_id"] == main_id, "default account is main")
    request("DELETE", f"/transactions/{omitted_account['id']}", expected=204)

    coffee = request(
        "POST",
        "/transactions",
        body={
            "name": "coffee",
            "value": -12.5,
            "currency_id": eur_id,
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    grocery = request(
        "POST",
        "/transactions",
        body={
            "name": "grocery shop",
            "value": -50,
            "currency_id": eur_id,
            "account_id": main_id,
            "occurred_unix_time": today,
            "category_id": food["id"],
        },
        expected=201,
    )
    expect(grocery and grocery["category_id"] == food["id"], "tagged grocery")
    zero = request(
        "POST",
        "/transactions",
        body={"name": "zero", "value": 0, "currency_id": eur_id},
        expected=422,
    )
    expect(zero and zero["error"] == "validation_error", "zero rejected")
    missing_tx_fields = request("POST", "/transactions", body={"name": "x"}, expected=422)
    expect(missing_tx_fields and missing_tx_fields["error"] == "validation_error", "tx missing fields")

    tagged = request(
        "PATCH",
        f"/transactions/{coffee['id']}",
        body={"category_id": food["id"]},
    )
    expect(tagged and tagged["category_id"] == food["id"], "patch category")
    untagged = request(
        "PATCH",
        f"/transactions/{coffee['id']}",
        body={"category_id": None},
    )
    expect(untagged and untagged["category_id"] is None, "clear category")
    request(
        "PATCH",
        f"/transactions/{coffee['id']}",
        body={"category_id": food["id"]},
    )
    patched_tx = request(
        "PATCH",
        f"/transactions/{coffee['id']}",
        body={
            "name": "espresso",
            "value": -3.5,
            "currency_id": gbp["id"],
            "occurred_unix_time": yesterday,
        },
    )
    expect(patched_tx and patched_tx["name"] == "espresso", "patch tx name")
    expect(patched_tx and patched_tx["value"] == -3.5, "patch tx value")
    expect(patched_tx and patched_tx["currency_id"] == gbp["id"], "patch tx currency")
    expect(patched_tx and patched_tx.get("amount") is None, "gbp amount omitted")
    expect(patched_tx and patched_tx["occurred_unix_time"] == yesterday, "patch tx date")
    request(
        "PATCH",
        f"/transactions/{coffee['id']}",
        body={
            "name": "coffee",
            "value": -12.5,
            "currency_id": eur_id,
            "occurred_unix_time": today,
        },
    )
    zero_patch = request(
        "PATCH",
        f"/transactions/{coffee['id']}",
        body={"value": 0},
        expected=422,
    )
    expect(zero_patch and zero_patch["error"] == "validation_error", "patch zero rejected")
    named = request("GET", f"/transactions/{salary['id']}")
    expect(named and named["value"] == 2000, "get transaction")
    expect(named and named.get("amount") == 2000, "get transaction converted amount")
    expect((named or {}).get("currency", "").lower() == "eur", "get transaction currency")
    missing_tx = request("GET", "/transactions/999999", expected=404)
    expect(missing_tx and missing_tx["error"] == "not_found", "missing transaction")

    listed = request(
        "GET",
        "/transactions",
        params=f"?account_id={main_id}&from_unix_time={today}&to_unix_time={today}",
    )
    expect(listed and listed["count"] >= 3, f"list today {listed}")
    income = request("GET", "/transactions", params=f"?account_id={main_id}&btm_value=0")
    expect(income and all(item["value"] > 0 for item in income["items"]), "btm_value income")
    expenses = request("GET", "/transactions", params=f"?account_id={main_id}&top_value=0")
    expect(expenses and all(item["value"] < 0 for item in expenses["items"]), "top_value expenses")

    balance = request("GET", f"/accounts/{main_id}/balance")
    expect(balance and abs(balance["amount"] - (2000 - 12.5 - 50)) < 1e-9, f"balance {balance}")
    expect((balance or {}).get("currency", "").lower() == "eur", f"balance currency {balance}")
    parts = {item["currency_id"]: item["amount"] for item in (balance or {}).get("by_currency", [])}
    expect(parts.get(eur_id) is not None, "by_currency includes eur")
    expect(abs(parts[eur_id] - (2000 - 12.5 - 50)) < 1e-9, f"eur bucket {parts}")
    usd_row = request(
        "POST",
        "/transactions",
        body={
            "name": "usd-coffee",
            "value": -4,
            "currency_id": usd["id"],
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    uah = by_symbol_row["uah"]
    uah_row = request(
        "POST",
        "/transactions",
        body={
            "name": "uah-metro",
            "value": -40,
            "currency_id": uah["id"],
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    usd_as_eur = fx_convert(-4, "usd", "eur")
    uah_as_eur = fx_convert(-40, "uah", "eur")
    expect(usd_as_eur is not None and uah_as_eur is not None, "fx mixed quotes")
    expect(usd_row and usd_row.get("amount") is not None, "usd row converted")
    expect(abs((usd_row or {}).get("amount", 0) - usd_as_eur) < 1e-9, f"usd amount {usd_row}")
    expect((usd_row or {}).get("currency", "").lower() == "eur", "usd row currency")
    expect(uah_row and abs((uah_row or {}).get("amount", 0) - uah_as_eur) < 1e-9, f"uah amount {uah_row}")
    converted_net = (2000 - 12.5 - 50) + usd_as_eur + uah_as_eur
    mixed = request("GET", f"/accounts/{main_id}/balance")
    mixed_parts = {item["currency_id"]: item["amount"] for item in (mixed or {}).get("by_currency", [])}
    expect(mixed and abs(mixed["amount"] - converted_net) < 1e-9, f"converted mixed {mixed}")
    expect((mixed or {}).get("currency", "").lower() == "eur", "mixed balance currency")
    expect(abs(mixed_parts.get(eur_id, 0) - (2000 - 12.5 - 50)) < 1e-9, f"eur after mix {mixed_parts}")
    expect(abs(mixed_parts.get(usd["id"], 0) - (-4)) < 1e-9, f"usd after mix {mixed_parts}")
    expect(abs(mixed_parts.get(uah["id"], 0) - (-40)) < 1e-9, f"uah after mix {mixed_parts}")
    gbp_row = request(
        "POST",
        "/transactions",
        body={
            "name": "gbp-tea",
            "value": -5,
            "currency_id": gbp["id"],
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    with_gbp = request("GET", f"/accounts/{main_id}/balance")
    expect(with_gbp and abs(with_gbp["amount"] - converted_net) < 1e-9, f"gbp omitted {with_gbp}")
    converted_spent = 62.5 + (-usd_as_eur) + (-uah_as_eur)
    spent_mixed = request(
        "GET",
        f"/accounts/{main_id}/spent",
        params=f"?from_unix_time={today}&to_unix_time={today}",
    )
    expect(
        spent_mixed and abs(spent_mixed["amount"] - converted_spent) < 1e-9,
        f"converted spent {spent_mixed}",
    )
    expect((spent_mixed or {}).get("currency", "").lower() == "eur", "spent currency")
    expect(gbp_row and gbp_row.get("amount") is None, "gbp row amount omitted")
    request("DELETE", f"/transactions/{gbp_row['id']}", expected=204)
    request("DELETE", f"/transactions/{uah_row['id']}", expected=204)
    request("DELETE", f"/transactions/{usd_row['id']}", expected=204)
    spent = request(
        "GET",
        f"/accounts/{main_id}/spent",
        params=f"?from_unix_time={today}&to_unix_time={today}",
    )
    expect(spent and abs(spent["amount"] - 62.5) < 1e-9, f"spent {spent}")
    spent_default = request("GET", f"/accounts/{main_id}/spent")
    expect(spent_default and spent_default["amount"] >= 0, "spent default window")

    extra = request("POST", "/accounts", body={"name": "card"}, expected=201)
    renamed = request("PATCH", f"/accounts/{extra['id']}", body={"name": "visa"})
    expect(renamed and renamed["name"] == "visa", "rename account")
    request("DELETE", f"/accounts/{extra['id']}", expected=204)
    last = request("DELETE", f"/accounts/{main_id}", expected=409)
    expect(last and last["error"] == "last_account", "last account kept")

    sub = request(
        "POST",
        "/subscriptions",
        body={
            "name": "netflix",
            "value": -9.99,
            "currency_id": eur_id,
            "account_id": main_id,
            "cron_stamp": "0 0 1 * *",
            "occurred_unix_time": today,
        },
        expected=201,
    )
    expect(sub and sub["cron_stamp"] == "0 0 1 * *", "create subscription")
    expect(sub and sub.get("amount") == -9.99, f"subscription converted {sub}")
    expect((sub or {}).get("currency", "").lower() == "eur", "subscription currency")
    netflix_good = sub["good_id"]
    got_sub = request("GET", f"/subscriptions/{sub['id']}")
    expect(got_sub and got_sub["name"] == "netflix", "get subscription")
    cron = request("PATCH", f"/subscriptions/{sub['id']}", body={"cron_stamp": "0 0 2 * *"})
    expect(cron and cron["cron_stamp"] == "0 0 2 * *", "patch cron")
    empty_patch = request("PATCH", f"/subscriptions/{sub['id']}", body={})
    expect(empty_patch and empty_patch["id"] == sub["id"], "patch subscription noop")
    subs = request("GET", "/subscriptions", params=f"?account_id={main_id}")
    expect(subs and subs["count"] >= 1, "list subscriptions")
    by_good = request("GET", "/subscriptions", params=f"?good_id={sub['good_id']}")
    expect(by_good and by_good["count"] >= 1, "list subscriptions by good")
    request("DELETE", f"/subscriptions/{sub['id']}", expected=204)
    request("DELETE", f"/transactions/{netflix_good}", expected=204)
    missing_sub = request("GET", "/subscriptions/999999", expected=404)
    expect(missing_sub and missing_sub["error"] == "not_found", "missing subscription")

    spotify = request(
        "POST",
        "/transactions",
        body={
            "name": "spotify",
            "value": -12,
            "currency_id": eur_id,
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    linked = request(
        "POST",
        "/subscriptions",
        body={"good_id": spotify["id"], "cron_stamp": "0 0 1 * *"},
        expected=201,
    )
    expect(linked and linked["good_id"] == spotify["id"], "subscription from good_id")
    request("DELETE", f"/subscriptions/{linked['id']}", expected=204)
    request("DELETE", f"/transactions/{spotify['id']}", expected=204)
    bad_sub = request(
        "POST",
        "/subscriptions",
        body={"cron_stamp": "0 0 1 * *"},
        expected=422,
    )
    expect(bad_sub and bad_sub["error"] == "validation_error", "subscription needs good or fields")
    zero_sub = request(
        "POST",
        "/subscriptions",
        body={"name": "zero-sub", "value": 0, "currency_id": eur_id, "cron_stamp": "0 0 1 * *"},
        expected=422,
    )
    expect(zero_sub and zero_sub["error"] == "validation_error", "zero subscription")

    request("DELETE", f"/transactions/{grocery['id']}", expected=204)
    request("DELETE", f"/transactions/{coffee['id']}", expected=204)
    request("DELETE", f"/categories/{food['id']}", expected=204)
    request("DELETE", f"/currencies/{gbp['id']}", expected=204)
    missing = request("GET", "/categories/nope", expected=404)
    expect(missing and missing["error"] == "not_found", "missing category")
