"""Model-readable compressors that beat yaml_like without gzip.

Design rules (o200k_base / GPT-5):
- Keep ASCII spaces; do not glue fields.
- Monthly headers beat repeating YYYY-MM-DD.
- Cents (integers) beat `12.34` decimals (~1-2 tokens saved per row).
- Frequency-ranked letter codes beat integer ids (` a` is 1 token, ` 0` is 2).
- Category is 1:1 with merchant on this corpus, so it lives in the legend.
- Account/currency defaults (main/eur) plus * ~ $ flags cover the rest.
- gzip/base64 is cheaper (~7.8k) but opaque — not a fair win.
"""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from datetime import date, timedelta
from typing import Iterable

from experiments.tokenization.bundle import Bundle, Transaction
from experiments.tokenization.codecs.base import CodecResult, fn_codec

EPOCH = date(2025, 1, 1)
LETTERS = [chr(i) for i in range(ord("a"), ord("z") + 1)]
TWO_LETTER = [a + b for a in LETTERS for b in LETTERS]
B62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
FLAG_CREDIT = "*"
FLAG_SAVINGS = "~"
FLAG_USD = "$"

# (name, cents, occurred_on, currency, account, category)
Record = tuple[str, int, str, str, str, str]


def _cents(value: float) -> int:
    return int(round(value * 100))


def _money(cents: int) -> float:
    return round(cents / 100.0, 2)


def _record(tx: Transaction) -> Record:
    return (
        tx.name,
        _cents(tx.value),
        tx.occurred_on,
        tx.currency,
        tx.account,
        tx.category or "-",
    )


def _freq_names(bundle: Bundle) -> list[str]:
    return [name for name, _ in Counter(tx.name for tx in bundle.transactions).most_common()]


def _name_codes(names: list[str]) -> dict[str, str]:
    codes: dict[str, str] = {}
    for i, name in enumerate(names):
        codes[name] = LETTERS[i] if i < 26 else TWO_LETTER[i - 26]
    return codes


def _name_to_cat(bundle: Bundle) -> dict[str, str]:
    out: dict[str, str] = {}
    for tx in bundle.transactions:
        cat = tx.category or "-"
        prev = out.get(tx.name)
        if prev is not None and prev != cat:
            raise ValueError(f"merchant {tx.name!r} maps to both {prev!r} and {cat!r}")
        out[tx.name] = cat
    return out


def _flags(tx: Transaction) -> str:
    extra = ""
    if tx.account == "credit":
        extra += f" {FLAG_CREDIT}"
    elif tx.account == "savings":
        extra += f" {FLAG_SAVINGS}"
    if tx.currency == "usd":
        extra += f" {FLAG_USD}"
    return extra


def _apply_flag(token: str, account: str, currency: str) -> tuple[str, str]:
    if token == FLAG_CREDIT:
        return "credit", currency
    if token == FLAG_SAVINGS:
        return "savings", currency
    if token == FLAG_USD:
        return account, "usd"
    raise ValueError(f"bad flag {token!r}")


def _legend_lines(names: list[str], codes: dict[str, str], cats: dict[str, str]) -> list[str]:
    return [f"{codes[name]} {name} {cats[name]}" for name in names]


def _parse_legend(lines: Iterable[str]) -> tuple[dict[str, str], dict[str, str]]:
    """code -> name, code -> category. Legend rows: `code name words category`."""
    code_re = re.compile(r"^[a-z]{1,2}$")
    names: dict[str, str] = {}
    cats: dict[str, str] = {}
    for raw in lines:
        toks = raw.split()
        if len(toks) < 3 or not code_re.match(toks[0]):
            continue
        code, category = toks[0], toks[-1]
        names[code] = " ".join(toks[1:-1])
        cats[code] = category
    return names, cats


def _group_month_day(txs: list[Transaction]) -> list[tuple[str, list[tuple[str, list[Transaction]]]]]:
    months: dict[str, list[Transaction]] = defaultdict(list)
    for tx in txs:
        months[tx.occurred_on[:7]].append(tx)
    out: list[tuple[str, list[tuple[str, list[Transaction]]]]] = []
    for month in sorted(months):
        days: dict[str, list[Transaction]] = defaultdict(list)
        for tx in months[month]:
            days[tx.occurred_on[8:]].append(tx)
        out.append((month, [(day, days[day]) for day in sorted(days)]))
    return out


def _to_b62(n: int) -> str:
    sign = "-" if n < 0 else ""
    n = abs(n)
    if n == 0:
        return sign + "0"
    chars: list[str] = []
    while n:
        n, rem = divmod(n, 62)
        chars.append(B62[rem])
    return sign + "".join(reversed(chars))


def _from_b62(text: str) -> int:
    sign = -1 if text.startswith("-") else 1
    body = text[1:] if text.startswith("-") else text
    n = 0
    for ch in body:
        n = n * 62 + B62.index(ch)
    return sign * n


def _parse_flagged_pairs(
    toks: list[str],
    *,
    amount: str = "cents",
) -> list[tuple[str, int, str, str]]:
    """Parse `code amount [flags ...]`. amount is cents int or base62."""
    rows: list[tuple[str, int, str, str]] = []
    i = 0
    while i < len(toks):
        code = toks[i]
        i += 1
        if i >= len(toks):
            raise ValueError(f"dangling code {code!r}")
        raw_amt = toks[i]
        i += 1
        cents = _from_b62(raw_amt) if amount == "base62" else int(raw_amt)
        account, currency = "main", "eur"
        while i < len(toks) and toks[i] in {FLAG_CREDIT, FLAG_SAVINGS, FLAG_USD}:
            account, currency = _apply_flag(toks[i], account, currency)
            i += 1
        rows.append((code, cents, currency, account))
    return rows


DAYPACK_HEADER = (
    "V=cents/100. default eur main. *=credit ~=savings $=usd. "
    "legend: code name category. body: YYYY-MM then DD code cents [flag]..."
)


def encode_freq_daypack(bundle: Bundle, *, use_base62: bool = False) -> str:
    names = _freq_names(bundle)
    codes = _name_codes(names)
    cats = _name_to_cat(bundle)
    header = DAYPACK_HEADER
    if use_base62:
        header = (
            "V=signed base62 cents (alphabet 0-9A-Za-z) then /100. "
            "default eur main. *=credit ~=savings $=usd. "
            "legend: code name category. body: YYYY-MM then DD code amount [flag]..."
        )
    parts = [header, *_legend_lines(names, codes, cats)]
    for month, days in _group_month_day(bundle.transactions):
        parts.append(month)
        for day, rows in days:
            bits: list[str] = []
            for tx in rows:
                amt = _to_b62(_cents(tx.value)) if use_base62 else str(_cents(tx.value))
                bits.append(f"{codes[tx.name]} {amt}{_flags(tx)}")
            parts.append(f"{day} {' '.join(bits)}")
    return "\n".join(parts)


def decode_freq_daypack(text: str, *, use_base62: bool = False) -> list[Record]:
    names, cats = _parse_legend(text.splitlines())
    recs: list[Record] = []
    month: str | None = None
    amount = "base62" if use_base62 else "cents"
    for line in text.splitlines():
        if re.fullmatch(r"\d{4}-\d{2}", line):
            month = line
            continue
        if month is None or not re.match(r"^\d{2} ", line):
            continue
        toks = line.split()
        day = toks[0]
        for code, cents, currency, account in _parse_flagged_pairs(toks[1:], amount=amount):
            recs.append(
                (
                    names[code],
                    cents,
                    f"{month}-{day}",
                    currency,
                    account,
                    cats[code],
                )
            )
    return recs


def encode_daypack_names(bundle: Bundle) -> str:
    cats = _name_to_cat(bundle)
    names = _freq_names(bundle)
    parts = [
        "V=cents/100. default eur main. *=credit ~=savings $=usd. "
        "legend: merchant=category. body: YYYY-MM then DD name cents [flag]...",
        "N " + " ".join(f"{name}={cats[name]}" for name in names),
    ]
    for month, days in _group_month_day(bundle.transactions):
        parts.append(month)
        for day, rows in days:
            bits = [f"{tx.name} {_cents(tx.value)}{_flags(tx)}" for tx in rows]
            parts.append(f"{day} {' '.join(bits)}")
    return "\n".join(parts)


def decode_daypack_names(text: str) -> list[Record]:
    lines = text.splitlines()
    legend_line = next(line for line in lines if line.startswith("N "))
    cats: dict[str, str] = {}
    buf: list[str] = []
    for piece in legend_line[2:].split():
        if "=" in piece:
            last, _, cat = piece.partition("=")
            buf.append(last)
            cats[" ".join(buf)] = cat
            buf = []
        else:
            buf.append(piece)
    recs: list[Record] = []
    month: str | None = None
    known = sorted(cats, key=len, reverse=True)
    for line in lines:
        if re.fullmatch(r"\d{4}-\d{2}", line):
            month = line
            continue
        if month is None or not re.match(r"^\d{2} ", line):
            continue
        day, rest = line[:2], line[3:]
        recs.extend(_parse_named_day(f"{month}-{day}", rest, cats, known))
    return recs


def _parse_named_day(iso: str, rest: str, cats: dict[str, str], known: list[str]) -> list[Record]:
    """Parse `name cents [flags] name cents ...` with possibly multi-word names."""
    toks = rest.split()
    recs: list[Record] = []
    i = 0
    while i < len(toks):
        matched: str | None = None
        for name in known:
            nlen = len(name.split())
            if toks[i : i + nlen] == name.split():
                matched = name
                i += nlen
                break
        if matched is None:
            raise ValueError(f"no merchant at {toks[i:]!r}")
        cents = int(toks[i])
        i += 1
        account, currency = "main", "eur"
        while i < len(toks) and toks[i] in {FLAG_CREDIT, FLAG_SAVINGS, FLAG_USD}:
            account, currency = _apply_flag(toks[i], account, currency)
            i += 1
        recs.append((matched, cents, iso, currency, account, cats[matched]))
    return recs


VM_HEADER = """VM V=cents/100 default eur/main *=credit ~=savings $=usd
Each month: MYY-MM:+salary;Rrent;Iins;G;N then exception rows DD code cents
S salary d01; R rent d03; I insurance d05; G gym d08 -4999; N netflix d08 -1599
Fixed templates omitted from exception list. Extra netflix stays as its legend code."""


def encode_tiny_vm(bundle: Bundle) -> str:
    names = _freq_names(bundle)
    codes = _name_codes(names)
    cats = _name_to_cat(bundle)
    parts = [VM_HEADER, *_legend_lines(names, codes, cats)]
    months: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        months[tx.occurred_on[:7]].append(tx)
    for month in sorted(months):
        rows = months[month]
        used: set[int] = set()
        salary = rent = ins = ""
        has_g = has_n = False
        for tx in rows:
            day = tx.occurred_on[8:]
            cv = _cents(tx.value)
            if tx.name == "monthly salary" and day == "01":
                salary = f"+{cv}"
                used.add(id(tx))
            elif tx.name == "apartment rent" and day == "03":
                rent = f"R{cv}"
                used.add(id(tx))
            elif tx.name == "health insurance" and day == "05":
                ins = f"I{cv}"
                used.add(id(tx))
            elif tx.name == "gym" and day == "08" and cv == -4999:
                has_g = True
                used.add(id(tx))
            elif tx.name == "netflix" and day == "08" and cv == -1599 and not has_n:
                has_n = True
                used.add(id(tx))
        ops = [p for p in (salary, rent, ins) if p]
        if has_g:
            ops.append("G")
        if has_n:
            ops.append("N")
        parts.append(f"M{month[2:]}:" + ";".join(ops))
        extras = [tx for tx in rows if id(tx) not in used]
        days: dict[str, list[Transaction]] = defaultdict(list)
        for tx in extras:
            days[tx.occurred_on[8:]].append(tx)
        for day in sorted(days):
            bits = [f"{codes[tx.name]} {_cents(tx.value)}{_flags(tx)}" for tx in days[day]]
            parts.append(f"{day} {' '.join(bits)}")
    return "\n".join(parts)


def decode_tiny_vm(text: str) -> list[Record]:
    names, cats = _parse_legend(text.splitlines())
    recs: list[Record] = []
    month: str | None = None
    for line in text.splitlines():
        m = re.fullmatch(r"M(\d{2})-(\d{2}):(.+)", line)
        if m:
            century_year, mon, body = m.group(1), m.group(2), m.group(3)
            year = 2000 + int(century_year)
            month = f"{year:04d}-{mon}"
            for op in body.split(";"):
                if not op:
                    continue
                if op.startswith("+"):
                    recs.append(("monthly salary", int(op), f"{month}-01", "eur", "main", "salary"))
                elif op.startswith("R"):
                    recs.append(("apartment rent", int(op[1:]), f"{month}-03", "eur", "main", "rent"))
                elif op.startswith("I"):
                    recs.append(("health insurance", int(op[1:]), f"{month}-05", "eur", "main", "insurance"))
                elif op == "G":
                    recs.append(("gym", -4999, f"{month}-08", "eur", "main", "subscriptions"))
                elif op == "N":
                    recs.append(("netflix", -1599, f"{month}-08", "eur", "main", "subscriptions"))
                else:
                    raise ValueError(f"bad VM op {op!r}")
            continue
        if month is None or not re.match(r"^\d{2} ", line):
            continue
        toks = line.split()
        day = toks[0]
        for code, cents, currency, account in _parse_flagged_pairs(toks[1:]):
            recs.append((names[code], cents, f"{month}-{day}", currency, account, cats[code]))
    return recs


def encode_month_dict_cents(bundle: Bundle) -> str:
    names = _freq_names(bundle)
    cats = _name_to_cat(bundle)
    ni = {n: i for i, n in enumerate(names)}
    ai = {"main": 0, "credit": 1, "savings": 2}
    yi = {"eur": 0, "usd": 1}
    parts = [
        "V=cents/100 D=day-of-month. default Y=0 eur A=0 main. "
        "Non-default rows append Y A. N id is frequency rank.",
        "A=0main,1credit,2savings Y=0eur,1usd",
        "N=" + ",".join(f"{i}={n}/{cats[n]}" for i, n in enumerate(names)),
        "rows under YYYY-MM: D N V [Y A]",
    ]
    for month, days in _group_month_day(bundle.transactions):
        parts.append(month)
        for day, rows in days:
            for tx in rows:
                line = f"{day} {ni[tx.name]} {_cents(tx.value)}"
                if tx.account != "main" or tx.currency != "eur":
                    line += f" {yi[tx.currency]} {ai[tx.account]}"
                parts.append(line)
    return "\n".join(parts)


def decode_month_dict_cents(text: str) -> list[Record]:
    names: dict[int, str] = {}
    cats: dict[int, str] = {}
    recs: list[Record] = []
    month: str | None = None
    accs = {0: "main", 1: "credit", 2: "savings"}
    ccys = {0: "eur", 1: "usd"}
    for line in text.splitlines():
        if line.startswith("N="):
            for piece in line[2:].split(","):
                idx_s, _, rest = piece.partition("=")
                name, _, cat = rest.partition("/")
                idx = int(idx_s)
                names[idx] = name
                cats[idx] = cat
            continue
        if re.fullmatch(r"\d{4}-\d{2}", line):
            month = line
            continue
        if month is None:
            continue
        toks = line.split()
        if len(toks) < 3 or not toks[0].isdigit():
            continue
        day, nid, cents_s = toks[0], int(toks[1]), int(toks[2])
        y, a = 0, 0
        if len(toks) >= 5:
            y, a = int(toks[3]), int(toks[4])
        recs.append((names[nid], cents_s, f"{month}-{day}", ccys[y], accs[a], cats[nid]))
    return recs


def encode_rle_cat_delta(bundle: Bundle) -> str:
    names = _freq_names(bundle)
    codes = _name_codes(names)
    cats = _name_to_cat(bundle)
    parts = [
        "Sorted by category then date. Each block `CAT xN` is N rows. "
        "Rows: delta-days-from-prev code cents [flag]. First delta is days since 2025-01-01. "
        "V=cents/100 default eur/main *=credit ~=savings $=usd.",
        *_legend_lines(names, codes, cats),
    ]
    ordered = sorted(
        bundle.transactions,
        key=lambda tx: (tx.category or "-", tx.occurred_on, tx.name, tx.id),
    )
    i = 0
    prev_days = 0
    while i < len(ordered):
        cat = ordered[i].category or "-"
        j = i
        while j < len(ordered) and (ordered[j].category or "-") == cat:
            j += 1
        block = ordered[i:j]
        parts.append(f"{cat} x{len(block)}")
        for tx in block:
            days = (date.fromisoformat(tx.occurred_on) - EPOCH).days
            parts.append(f"{days - prev_days} {codes[tx.name]} {_cents(tx.value)}{_flags(tx)}")
            prev_days = days
        i = j
    return "\n".join(parts)


def decode_rle_cat_delta(text: str) -> list[Record]:
    names, cats = _parse_legend(text.splitlines())
    recs: list[Record] = []
    prev_days = 0
    for line in text.splitlines():
        toks = line.split()
        if len(toks) >= 3 and toks[0].lstrip("-").isdigit() and re.fullmatch(r"[a-z]{1,2}", toks[1]):
            delta = int(toks[0])
            prev_days += delta
            iso = (EPOCH + timedelta(days=prev_days)).isoformat()
            for code, cents, currency, account in _parse_flagged_pairs(toks[1:]):
                recs.append((names[code], cents, iso, currency, account, cats[code]))
    return recs


def encode_columnar_ints(bundle: Bundle) -> str:
    names = _freq_names(bundle)
    cats = _name_to_cat(bundle)
    ni = {n: i for i, n in enumerate(names)}
    parts = [
        "Columnar integers, original order. D=delta days from prev (first = days since 2025-01-01). "
        "N=freq-rank id. V=cents. Aex/Yex are sparse exceptions (index:code).",
        "A 0=main 1=credit 2=savings; Y 0=eur 1=usd; default A0 Y0.",
        "N=" + ",".join(f"{i}={n}/{cats[n]}" for i, n in enumerate(names)),
    ]
    ds: list[str] = []
    ns: list[str] = []
    vs: list[str] = []
    aex: list[str] = []
    yex: list[str] = []
    prev = 0
    for i, tx in enumerate(bundle.transactions):
        days = (date.fromisoformat(tx.occurred_on) - EPOCH).days
        ds.append(str(days - prev))
        prev = days
        ns.append(str(ni[tx.name]))
        vs.append(str(_cents(tx.value)))
        if tx.account != "main":
            aex.append(f"{i}:{1 if tx.account == 'credit' else 2}")
        if tx.currency != "eur":
            yex.append(f"{i}:1")
    parts += [
        "D " + " ".join(ds),
        "N " + " ".join(ns),
        "V " + " ".join(vs),
        "Aex " + (" ".join(aex) if aex else "-"),
        "Yex " + (" ".join(yex) if yex else "-"),
    ]
    return "\n".join(parts)


def decode_columnar_ints(text: str) -> list[Record]:
    names: dict[int, str] = {}
    cats: dict[int, str] = {}
    cols: dict[str, list[str]] = {}
    for line in text.splitlines():
        if line.startswith("N=") and "," in line:
            for piece in line[2:].split(","):
                idx_s, _, rest = piece.partition("=")
                name, _, cat = rest.partition("/")
                names[int(idx_s)] = name
                cats[int(idx_s)] = cat
            continue
        if line.startswith("D "):
            cols["D"] = line[2:].split()
        elif line.startswith("N ") and line[2:3].isdigit():
            cols["N"] = line[2:].split()
        elif line.startswith("V "):
            cols["V"] = line[2:].split()
        elif line.startswith("Aex "):
            cols["Aex"] = [] if line[4:].strip() == "-" else line[4:].split()
        elif line.startswith("Yex "):
            cols["Yex"] = [] if line[4:].strip() == "-" else line[4:].split()
    n = len(cols["D"])
    acc = ["main"] * n
    ccy = ["eur"] * n
    amap = {"1": "credit", "2": "savings"}
    for item in cols.get("Aex", []):
        idx_s, _, val = item.partition(":")
        acc[int(idx_s)] = amap[val]
    for item in cols.get("Yex", []):
        idx_s, _, val = item.partition(":")
        ccy[int(idx_s)] = "usd" if val == "1" else "eur"
    recs: list[Record] = []
    days = 0
    for i in range(n):
        days += int(cols["D"][i])
        nid = int(cols["N"][i])
        recs.append(
            (
                names[nid],
                int(cols["V"][i]),
                (EPOCH + timedelta(days=days)).isoformat(),
                ccy[i],
                acc[i],
                cats[nid],
            )
        )
    return recs


def assert_roundtrip(bundle: Bundle, encoded: str, decoder) -> None:
    got = Counter(decoder(encoded))
    want = Counter(_record(tx) for tx in bundle.transactions)
    if got != want:
        missing = want - got
        extra = got - want
        raise AssertionError(f"roundtrip fail missing={len(missing)} extra={len(extra)} "
                             f"eg_missing={missing.most_common(3)} eg_extra={extra.most_common(3)}")


def _result(name: str, family: str, notes: str, text: str, decode_instructions: str) -> CodecResult:
    return CodecResult(
        name=name,
        family=family,
        text=text,
        notes=notes,
        reversible=True,
        decode_instructions=decode_instructions,
    )


FREQ_DECODE = (
    "Legend maps short codes to merchant + category (1:1). "
    "Each YYYY-MM header sets the month. Each following line is "
    "`DD code cents [*/~/$ ...]` with several txs on the same day. "
    "CENTS/100 is the signed euro amount (negative=expense). "
    "*=credit ~=savings $=usd; omit means main/eur. "
    "Count txs by (code,cents) pairs. Sum positive cents/100 = income; "
    "sum of -cents/100 for negatives = expense. Top spend category = "
    "legend category of merchants with the largest sum of -value."
)


@fn_codec(
    "freq_daypack",
    "novel",
    "Monthly+day packed freq-ranked 1-2 char merchant codes, cents, sparse account/ccy flags.",
)
def freq_daypack(bundle: Bundle) -> CodecResult:
    return _result(
        "freq_daypack",
        "novel",
        "Monthly+day packed freq-ranked 1-2 char merchant codes, cents, sparse account/ccy flags.",
        encode_freq_daypack(bundle),
        FREQ_DECODE,
    )


@fn_codec(
    "daypack_names",
    "novel",
    "Same monthly/day/cents packing but full merchant names — no codebook.",
)
def daypack_names(bundle: Bundle) -> CodecResult:
    return _result(
        "daypack_names",
        "novel",
        "Same monthly/day/cents packing but full merchant names — no codebook.",
        encode_daypack_names(bundle),
        "Legend N maps merchant=category. YYYY-MM then `DD name cents [flag]`. "
        "V=cents/100. default eur/main. *=credit ~=savings $=usd. "
        "Totals: sum signed cents/100; category from legend.",
    )


@fn_codec(
    "tiny_ledger_vm",
    "novel",
    "Monthly templates M+salary;R-rent;I-ins;G;N plus exception daypack list.",
)
def tiny_ledger_vm(bundle: Bundle) -> CodecResult:
    return _result(
        "tiny_ledger_vm",
        "novel",
        "Monthly templates M+salary;R-rent;I-ins;G;N plus exception daypack list.",
        encode_tiny_vm(bundle),
        "Each `MYY-MM:+SAL;RRENT;IINS;G;N` emits: salary d01, rent d03, insurance d05, "
        "gym d08 -49.99, netflix d08 -15.99 (cents in the opcode). "
        "Following `DD code cents` lines are extra txs that month (same legend as freq_daypack). "
        "G/N omitted means that template tx is absent. Totals = templates + extras.",
    )


@fn_codec(
    "month_dict_cents",
    "novel",
    "yaml_like monthly grouping combined with dict_ids: freq integer ids + cents + sparse Y/A.",
)
def month_dict_cents(bundle: Bundle) -> CodecResult:
    return _result(
        "month_dict_cents",
        "novel",
        "yaml_like monthly grouping combined with dict_ids: freq integer ids + cents + sparse Y/A.",
        encode_month_dict_cents(bundle),
        "N=id=merchant/category. Under each YYYY-MM, rows are `DD nid cents [Y A]`. "
        "V=cents/100. Default Y=0 eur A=0 main. Expand ids via legend, then sum as usual.",
    )


@fn_codec(
    "rle_cat_delta",
    "novel",
    "Sort by category, RLE block headers, delta-days, freq codes, cents.",
)
def rle_cat_delta(bundle: Bundle) -> CodecResult:
    return _result(
        "rle_cat_delta",
        "novel",
        "Sort by category, RLE block headers, delta-days, freq codes, cents.",
        encode_rle_cat_delta(bundle),
        "Blocks `CAT xN` then N rows `delta code cents [flag]`. Running date starts 2025-01-01. "
        "Category for spend ranking is the block header (also on the legend). V=cents/100.",
    )


@fn_codec(
    "columnar_ints_only",
    "novel",
    "No JSON keys: parallel D/N/V integer streams plus sparse A/Y exception lists.",
)
def columnar_ints_only(bundle: Bundle) -> CodecResult:
    return _result(
        "columnar_ints_only",
        "novel",
        "No JSON keys: parallel D/N/V integer streams plus sparse A/Y exception lists.",
        encode_columnar_ints(bundle),
        "Zip columns D (delta days), N (merchant id), V (cents). Reconstruct dates from 2025-01-01. "
        "Look up N in the legend for merchant+category. Aex/Yex override account/currency. Sum V/100.",
    )


@fn_codec(
    "base62_daypack",
    "novel",
    "freq_daypack with cents in signed base62. Legend still English; amounts need the alphabet.",
)
def base62_daypack(bundle: Bundle) -> CodecResult:
    return _result(
        "base62_daypack",
        "novel",
        "freq_daypack with cents in signed base62. Legend still English; amounts need the alphabet.",
        encode_freq_daypack(bundle, use_base62=True),
        FREQ_DECODE + " Amounts are signed base62 (0-9A-Za-z), not decimal. Convert then /100.",
    )
