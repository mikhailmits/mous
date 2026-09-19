"""EUR-pivoted display FX. Same stub as macOS `FXBook` until a live feed exists.

`EUR→USD` 1.1, `EUR→UAH` 40. Cross pairs go through EUR. Missing pairs
return None so totals never pretend 1:1.
"""

from __future__ import annotations

import math

PIVOT = "EUR"
# Quote units per one base unit.
_STUB_PAIRS = (("EUR", "USD", 1.1), ("EUR", "UAH", 40.0))


def normalize(code: str) -> str:
    return code.strip().upper()


def _stub_rates() -> dict[tuple[str, str], float]:
    rates: dict[tuple[str, str], float] = {}
    for base, quote, rate in _STUB_PAIRS:
        rates[(base, quote)] = rate
        rates[(quote, base)] = 1.0 / rate
    return rates


_RATES = _stub_rates()


def quote(frm: str, to: str) -> float | None:
    src = normalize(frm)
    dst = normalize(to)
    if not src or not dst:
        return None
    if src == dst:
        return 1.0
    direct = _RATES.get((src, dst))
    if direct is not None and direct > 0 and math.isfinite(direct):
        return direct
    if src != PIVOT and dst != PIVOT:
        to_pivot = _RATES.get((src, PIVOT))
        from_pivot = _RATES.get((PIVOT, dst))
        if (
            to_pivot is not None
            and from_pivot is not None
            and to_pivot > 0
            and from_pivot > 0
        ):
            crossed = to_pivot * from_pivot
            if math.isfinite(crossed) and crossed > 0:
                return crossed
    return None


def convert(amount: float, frm: str, to: str) -> float | None:
    if not math.isfinite(amount):
        return None
    rate = quote(frm, to)
    if rate is None:
        return None
    converted = amount * rate
    if not math.isfinite(converted):
        return None
    return converted
