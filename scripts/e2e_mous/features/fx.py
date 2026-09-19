"""EUR/USD/UAH conversion; unquoted currencies omitted (not 1:1)."""

from __future__ import annotations

from datetime import date

from e2e_mous.harness import expect, request, unix_midnight


def run_stub() -> None:
    from mous.fx import convert as fx_convert

    expect(abs((fx_convert(10, "EUR", "USD") or 0) - 11) < 1e-9, "fx eur→usd")
    expect(abs((fx_convert(10, "EUR", "UAH") or 0) - 400) < 1e-9, "fx eur→uah")
    expect(abs((fx_convert(11, "USD", "EUR") or 0) - 10) < 1e-9, "fx usd→eur")
    expect(fx_convert(10, "GBP", "EUR") is None, "fx gbp omitted")
    expect(fx_convert(10, "EUR", "GBP") is None, "fx eur→gbp omitted")


def run_http() -> None:
    """Ledger value stays native; GET amount follows the API default currency."""
    from mous.fx import convert as fx_convert

    today = unix_midnight(date.today())
    accounts = request("GET", "/accounts")
    main_id = next(a["id"] for a in accounts["items"] if a["name"] == "main")
    currencies = request("GET", "/currencies")
    eur = next(c for c in currencies["items"] if c["symbol"] == "eur")
    expect(eur["is_default"] is True, "fx http expects eur default")
    usd_existed = any(c["symbol"] == "usd" for c in currencies["items"])
    usd = next((c for c in currencies["items"] if c["symbol"] == "usd"), None)
    if usd is None:
        usd = request(
            "POST",
            "/currencies",
            body={"symbol": "usd", "name": "US Dollar", "is_default": False},
            expected=201,
        )
    salary = request(
        "POST",
        "/transactions",
        body={
            "name": "fx-salary",
            "value": 100,
            "currency_id": eur["id"],
            "account_id": main_id,
            "occurred_unix_time": today,
        },
        expected=201,
    )
    expect(salary and salary["value"] == 100, "fx salary native value")
    expect(salary and salary.get("amount") == 100, "fx salary amount in eur")
    expect((salary or {}).get("currency", "").lower() == "eur", "fx salary currency eur")

    patched = request("PATCH", f"/currencies/{usd['id']}", body={"is_default": True})
    expect(patched and patched["is_default"] is True, "fx usd default")
    got = request("GET", f"/transactions/{salary['id']}")
    usd_amount = fx_convert(100, "eur", "usd")
    expect(usd_amount is not None, "fx 100 eur→usd")
    expect(got and got["value"] == 100, "fx ledger value stays native after default switch")
    expect(got and abs(got.get("amount", 0) - usd_amount) < 1e-9, f"fx amount in usd {got}")
    expect((got or {}).get("currency", "").lower() == "usd", "fx GET currency follows default")

    request("PATCH", f"/currencies/{eur['id']}", body={"is_default": True})
    restored = request("GET", f"/transactions/{salary['id']}")
    expect(restored and restored.get("amount") == 100, "fx amount back in eur")
    expect((restored or {}).get("currency", "").lower() == "eur", "fx default restored eur")
    request("DELETE", f"/transactions/{salary['id']}", expected=204)
    if not usd_existed:
        request("DELETE", f"/currencies/{usd['id']}", expected=204)


def run() -> None:
    run_stub()
    run_http()
    run_left_in_default()


def run_left_in_default() -> None:
    """GET /balance amount is leftover converted into the API default."""
    from mous.fx import convert as fx_convert

    accounts = request("GET", "/accounts")
    main_id = next(a["id"] for a in accounts["items"] if a["name"] == "main")
    currencies = request("GET", "/currencies")
    codes = {c["id"]: c["symbol"] for c in currencies["items"]}
    eur = next(c for c in currencies["items"] if c["symbol"] == "eur")
    uah = next((c for c in currencies["items"] if c["symbol"] == "uah"), None)
    uah_existed = uah is not None
    if uah is None:
        uah = request(
            "POST",
            "/currencies",
            body={"symbol": "uah", "name": "Hryvnia", "is_default": False},
            expected=201,
        )
        codes[uah["id"]] = "uah"
    patched = request("PATCH", f"/currencies/{uah['id']}", body={"is_default": True})
    expect(patched and patched["is_default"] is True, "fx left uah default")
    balance = request("GET", f"/accounts/{main_id}/balance")
    expect(balance is not None, "fx left balance")
    expect((balance or {}).get("currency", "").lower() == "uah", f"fx left currency {balance}")
    parts = (balance or {}).get("by_currency") or []
    expect(isinstance(parts, list) and len(parts) >= 1, f"fx left by_currency {balance}")
    expected = 0.0
    for part in parts:
        src = codes.get(part["currency_id"])
        converted = fx_convert(part["amount"], src or "", "uah")
        if converted is not None:
            expected += converted
    expect(
        abs((balance or {}).get("amount", 0) - expected) < 1e-6,
        f"fx left amount {balance} expected {expected}",
    )
    request("PATCH", f"/currencies/{eur['id']}", body={"is_default": True})
    if not uah_existed:
        request("DELETE", f"/currencies/{uah['id']}", expected=204)
