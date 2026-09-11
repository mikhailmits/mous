"""Denser OCR-able image encodings for the tokenization lab.

Hard constraints this module respects:
- Counting ``[image foo.png]`` as ~11 text tokens is a lie.
- OpenAI high-detail cost is ``85 + 170 * tiles`` after the 2048 / 768 rescale
  implemented in ``codecs.images.openai_image_tokens``.
- A 1000-line *tall* PNG is 765 high-detail tokens but the preprocessor
  crushes 9px glyphs to ~2px — not OCR-able.
- JPEG q=8 keeps the same tile count and wrecks glyphs; we do not chase JPEG.
- ``img_summary_card`` paints gold aggregates (cheat). Monthly table here is
  the same *family* of bound: ``reversible=False``, useful as an agent-mode
  ceiling, not a fair full-ledger winner.

Design:
- Never let max(width, height) exceed 2048 for a text ledger — that is what
  crushes glyphs. Shape the canvas so tiles are *native* 512px squares.
- 2 tiles (425 tokens) is the budget target: 512×1024 or 1024×512.
- 4 tiles (765 tokens) is the same cost as the tall PNG, but readable if we
  use a 4-column 512×2048 grid (no downscale).
- Splitting into N images pays the 85-token base *per image*, so it loses to
  one well-shaped strip at equal glyph size.
"""

from __future__ import annotations

import base64
import json
import math
import os
from collections import defaultdict
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from experiments.tokenization.bundle import Bundle, Transaction, month_key
from experiments.tokenization.codecs.base import CodecResult, fn_codec
from experiments.tokenization.codecs.images import openai_image_tokens
from experiments.tokenization.paths import IMAGES, RESULTS

MONO = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
SUBAGENT_DIR = RESULTS / "subagents"

# Hex nibble per category — 16 cats in this corpus.
CAT_HEX = {
    "coffee": "0",
    "education": "1",
    "entertainment": "2",
    "freelance": "3",
    "gifts": "4",
    "groceries": "5",
    "healthcare": "6",
    "insurance": "7",
    "rent": "8",
    "restaurants": "9",
    "salary": "a",
    "shopping": "b",
    "subscriptions": "c",
    "transport": "d",
    "travel": "e",
    "utilities": "f",
}
HEX_CAT = {v: k for k, v in CAT_HEX.items()}
ACC1 = {"main": "m", "savings": "s", "credit": "c"}
ACC_FROM = {v: k for k, v in ACC1.items()}
CUR1 = {"eur": "e", "usd": "u"}
CUR_FROM = {v: k for k, v in CUR1.items()}
CAT4 = {
    "coffee": "coff",
    "education": "educ",
    "entertainment": "ente",
    "freelance": "free",
    "gifts": "gift",
    "groceries": "groc",
    "healthcare": "heal",
    "insurance": "insu",
    "rent": "rent",
    "restaurants": "rest",
    "salary": "sala",
    "shopping": "shop",
    "subscriptions": "subs",
    "transport": "trnp",
    "travel": "trav",
    "utilities": "util",
}
CAT4_FROM = {v: k for k, v in CAT4.items()}
CAT_ORDER = list(CAT_HEX.keys())

COMPACT_LEGEND = (
    "Each row is 16 chars: YYMMDD + acct(m/s/c) + cat_hex + signed 6-digit cents + curr(e/u). "
    "cat_hex 0=coffee 1=education 2=entertainment 3=freelance 4=gifts 5=groceries "
    "6=healthcare 7=insurance 8=rent 9=restaurants a=salary b=shopping "
    "c=subscriptions d=transport e=travel f=utilities. "
    "Columns fill top→bottom, then left→right, chronological. "
    "Reconstruct: value=signed_cents/100, date=20YY-MM-DD."
)
NAMED_LEGEND = (
    "Each row: YYMMDD signed_amount cat4 merchant8. "
    "cat4: coff educ ente free gift groc heal insu rent rest sala shop subs trnp trav util. "
    "trnp=transport trav=travel. Columns top→bottom then left→right, chronological. "
    "Currency is EUR unless a trailing 'u' marks USD. Account is not painted (not needed for the three tasks)."
)


def _cents(value: float) -> int:
    return int(round(value * 100))


def _compact_line(tx: Transaction) -> str:
    yymmdd = tx.occurred_on.replace("-", "")[2:]
    acct = ACC1.get(tx.account, "?")
    cat = CAT_HEX.get(tx.category or "", "?")
    signed = f"{_cents(tx.value):+07d}"
    curr = CUR1.get(tx.currency, "?")
    return f"{yymmdd}{acct}{cat}{signed}{curr}"


EPOCH = "2025-03-01"


def _packed_line(tx: Transaction) -> str:
    """13-char compact row so 5×7 stamps fit 1000 rows in a 2-tile 512×1024.

    16-char × 5px × 7px × 1000 = 560k ink-cells > 512×1024 = 524k, so the year
    is replaced by a 3-digit day index from EPOCH (first ledger date).
    """
    from datetime import date as _date

    day = (_date.fromisoformat(tx.occurred_on) - _date.fromisoformat(EPOCH)).days
    acct = ACC1.get(tx.account, "?")
    cat = CAT_HEX.get(tx.category or "", "?")
    signed = f"{_cents(tx.value):+07d}"
    curr = CUR1.get(tx.currency, "?")
    return f"{day:03d}{acct}{cat}{signed}{curr}"


def _named_line(tx: Transaction) -> str:
    """Fits a 128px column at default size=8 (max ~121px on this corpus)."""
    date = tx.occurred_on.replace("-", "")[2:]  # YYMMDD
    cat = CAT4.get(tx.category or "", "????")
    amt = f"{tx.value:.2f}"
    name = (tx.name or "").replace(" ", "")[:8]
    tail = "u" if tx.currency == "usd" else ""
    return f"{date} {amt} {cat} {name}{tail}"


def _default_font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def _mono_font(size: int) -> ImageFont.ImageFont:
    if MONO.exists():
        return ImageFont.truetype(str(MONO), size=size)
    return _default_font(size)


def _text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def _openai_scaled(width: int, height: int) -> tuple[int, int, int, int]:
    """Return (scaled_w, scaled_h, tiles_x, tiles_y) matching openai_image_tokens."""
    w, h = width, height
    if w > 2048 or h > 2048:
        scale = 2048 / max(w, h)
        w, h = int(w * scale), int(h * scale)
    if min(w, h) > 768:
        scale = 768 / min(w, h)
        w, h = int(w * scale), int(h * scale)
    tiles_x = (w + 511) // 512
    tiles_y = (h + 511) // 512
    return w, h, tiles_x, tiles_y


def _effective_line_h(width: int, height: int, line_h: int) -> float:
    sw, sh, _, _ = _openai_scaled(width, height)
    if height <= 0:
        return 0.0
    return round(line_h * sh / height, 3)


def _fit_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_w: int) -> str:
    if max_w <= 0:
        return ""
    if _text_size(draw, text, font)[0] <= max_w:
        return text
    while text and _text_size(draw, text, font)[0] > max_w:
        text = text[:-1]
    return text


def _cat_rgb(category: str | None) -> tuple[int, int, int]:
    name = category or ""
    if name not in CAT_ORDER:
        return (80, 80, 80)
    idx = CAT_ORDER.index(name)
    # Distinct hues, high contrast on white. Gutters only — text stays black.
    hue = idx / max(len(CAT_ORDER), 1)
    import colorsys

    r, g, b = colorsys.hsv_to_rgb(hue, 0.78, 0.72)
    return int(r * 255), int(g * 255), int(b * 255)


# ---------------------------------------------------------------------------
# Packed 5×7 bitmap font (crisp 1-bit stamps, 0-pad cells).
# Rows are 5-bit ints, MSB = leftmost pixel.
# ---------------------------------------------------------------------------
_ROW5 = tuple[int, ...]
_GLYPHS_5X7: dict[str, _ROW5] = {
    "0": (0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110),
    "1": (0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110),
    "2": (0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111),
    "3": (0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110),
    "4": (0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010),
    "5": (0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110),
    "6": (0b01110, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b01110),
    "7": (0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000),
    "8": (0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110),
    "9": (0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b10001, 0b01110),
    "a": (0b00000, 0b01110, 0b00001, 0b01111, 0b10001, 0b10001, 0b01111),
    "b": (0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b11110),
    "c": (0b00000, 0b01110, 0b10001, 0b10000, 0b10000, 0b10001, 0b01110),
    "d": (0b00001, 0b00001, 0b01111, 0b10001, 0b10001, 0b10001, 0b01111),
    "e": (0b00000, 0b01110, 0b10001, 0b11111, 0b10000, 0b10001, 0b01110),
    "f": (0b00110, 0b01000, 0b01000, 0b11100, 0b01000, 0b01000, 0b01000),
    "m": (0b00000, 0b11010, 0b10101, 0b10101, 0b10101, 0b10101, 0b10001),
    "s": (0b00000, 0b01111, 0b10000, 0b01110, 0b00001, 0b10001, 0b01110),
    "u": (0b00000, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01111),
    "g": (0b00000, 0b01111, 0b10001, 0b10001, 0b01111, 0b00001, 0b01110),
    "h": (0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b10001),
    "i": (0b00100, 0b00000, 0b01100, 0b00100, 0b00100, 0b00100, 0b01110),
    "k": (0b10000, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001),
    "n": (0b00000, 0b10110, 0b11001, 0b10001, 0b10001, 0b10001, 0b10001),
    "o": (0b00000, 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110),
    "p": (0b00000, 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000),
    "r": (0b00000, 0b10110, 0b11001, 0b10000, 0b10000, 0b10000, 0b10000),
    "t": (0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100),
    "x": (0b00000, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b00000),
    "y": (0b00000, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110),
    "+": (0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000),
    "-": (0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000),
    " ": (0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000),
    "?": (0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100),
}


def _stamp_bitmap(img: Image.Image, x: int, y: int, text: str, *, color: int = 0) -> None:
    px = img.load()
    w, h = img.size
    cx = x
    for ch in text:
        rows = _GLYPHS_5X7.get(ch, _GLYPHS_5X7["?"])
        for ry, bits in enumerate(rows):
            for rx in range(5):
                if bits & (1 << (4 - rx)):
                    xx, yy = cx + rx, y + ry
                    if 0 <= xx < w and 0 <= yy < h:
                        px[xx, yy] = color
        cx += 5  # zero inter-glyph gap


def _vision_extras(
    paths: list[Path],
    sizes: list[tuple[int, int]],
    *,
    line_h: int,
    mode: str,
    n_cols: int,
    layout: str,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    highs: list[int] = []
    lows: list[int] = []
    per: list[dict[str, Any]] = []
    for path, (w, h) in zip(paths, sizes, strict=True):
        sw, sh, tx, ty = _openai_scaled(w, h)
        hi = openai_image_tokens(w, h, "high")
        lo = openai_image_tokens(w, h, "low")
        highs.append(hi)
        lows.append(lo)
        per.append(
            {
                "path": path.name,
                "width": w,
                "height": h,
                "bytes": path.stat().st_size,
                "scaled_w": sw,
                "scaled_h": sh,
                "tiles_x": tx,
                "tiles_y": ty,
                "tiles": tx * ty,
                "openai_high_tokens": hi,
                "openai_low_tokens": lo,
                "effective_line_h": _effective_line_h(w, h, line_h),
            }
        )
    w0, h0 = sizes[0]
    payload: dict[str, Any] = {
        "width": w0 if len(sizes) == 1 else [s[0] for s in sizes],
        "height": h0 if len(sizes) == 1 else [s[1] for s in sizes],
        "bytes": sum(p.stat().st_size for p in paths),
        "openai_high_tokens": int(sum(highs)),
        "openai_low_tokens": int(sum(lows)),
        "n_images": len(paths),
        "n_cols": n_cols,
        "line_h": line_h,
        "mode": mode,
        "layout": layout,
        "tiles_total": int(sum(item["tiles"] for item in per)),
        "effective_line_h": per[0]["effective_line_h"] if len(per) == 1 else [item["effective_line_h"] for item in per],
        "scaled": per[0] if len(per) == 1 else per,
        "low_detail_note": (
            "low detail is always 85 tokens per image: the model sees one 512×512 "
            "thumbnail. A tall/wide ledger is crushed; a small monthly table may survive."
        ),
    }
    if extra:
        payload.update(extra)
    return payload


def _save_scaled_preview(src: Path, dest: Path, orig_size: tuple[int, int]) -> None:
    """What the high-detail preprocessor actually feeds the encoder (approx)."""
    w, h = orig_size
    sw, sh, _, _ = _openai_scaled(w, h)
    img = Image.open(src)
    preview = img.resize((max(1, sw), max(1, sh)), Image.Resampling.NEAREST)
    dest.parent.mkdir(parents=True, exist_ok=True)
    preview.save(dest, optimize=True)


def _new_canvas(width: int, height: int, mode: str) -> Image.Image:
    if mode == "1":
        return Image.new("1", (width, height), 1)
    if mode == "L":
        return Image.new("L", (width, height), 255)
    if mode == "RGB":
        return Image.new("RGB", (width, height), (255, 255, 255))
    raise ValueError(mode)


def _ink(mode: str) -> int | tuple[int, int, int]:
    return 0 if mode != "RGB" else (0, 0, 0)


def _render_text_grid(
    lines: list[str],
    path: Path,
    *,
    width: int,
    height: int,
    n_cols: int,
    font: ImageFont.ImageFont,
    mode: str = "1",
    header: str = "",
    gutters: list[tuple[int, int, int]] | None = None,
    line_h_override: int | None = None,
) -> tuple[int, int, int]:
    """Column-major grid. Returns (w, h, line_h)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    img = _new_canvas(width, height, mode)
    draw = ImageDraw.Draw(img)
    ink = _ink(mode)
    sample = lines[0] if lines else "Ag"
    _, gh = _text_size(draw, sample[:24] or "Ag", font)
    line_h = line_h_override or max(gh + 1, 5)
    y0 = 0
    if header:
        hdr = _fit_text(draw, header, font, width - 2)
        draw.text((1, 1), hdr, fill=ink, font=font)
        y0 = line_h
    usable_h = height - y0
    rows = max(1, usable_h // line_h)
    n_cols = max(1, n_cols)
    col_w = width // n_cols
    gutter_w = 3 if (gutters is not None and mode == "RGB") else 0
    text_max = max(8, col_w - 3 - gutter_w)
    for i, line in enumerate(lines):
        col = i // rows
        row = i % rows
        if col >= n_cols:
            break
        x = col * col_w
        y = y0 + row * line_h
        if gutter_w and i < len(gutters or []):
            draw.rectangle((x, y, x + gutter_w, y + line_h - 1), fill=gutters[i])
            x += gutter_w + 1
        clipped = _fit_text(draw, line, font, text_max)
        draw.text((x + 1, y), clipped, fill=ink, font=font)
    rule = (160, 160, 160) if mode == "RGB" else ink
    for c in range(1, n_cols):
        x = c * col_w
        draw.line((x, y0, x, height - 1), fill=rule)
    capacity = n_cols * rows
    if len(lines) > capacity:
        raise RuntimeError(
            f"{path.name} overflow: {len(lines)} lines > {n_cols} cols × {rows} rows "
            f"(line_h={line_h}, {width}x{height})"
        )
    img.save(path, optimize=True)
    return img.size[0], img.size[1], line_h


def _render_bitmap_grid(
    lines: list[str],
    path: Path,
    *,
    width: int,
    height: int,
    n_cols: int,
    header: str = "",
) -> tuple[int, int, int]:
    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("1", (width, height), 1)
    line_h = 7  # packed: no vertical pad
    y0 = 0
    if header:
        _stamp_bitmap(img, 1, 1, header[: width // 5])
        y0 = line_h + 1
        # 1px rule under header
        px = img.load()
        for x in range(width):
            if y0 - 1 >= 0:
                px[x, y0 - 1] = 0
    rows = max(1, (height - y0) // line_h)
    col_w = width // max(1, n_cols)
    max_chars = col_w // 5
    for i, line in enumerate(lines):
        col = i // rows
        row = i % rows
        if col >= n_cols:
            break
        x = col * col_w + 1
        y = y0 + row * line_h
        _stamp_bitmap(img, x, y, line[:max_chars])
    capacity = n_cols * rows
    if len(lines) > capacity:
        raise RuntimeError(
            f"{path.name} overflow: {len(lines)} lines > {n_cols} cols × {rows} rows"
        )
    img.save(path, optimize=True)
    return img.size[0], img.size[1], line_h


def _result(
    name: str,
    paths: list[Path],
    sizes: list[tuple[int, int]],
    *,
    line_h: int,
    mode: str,
    n_cols: int,
    layout: str,
    decode: str,
    reversible: bool,
    notes: str,
    extra: dict[str, Any] | None = None,
) -> CodecResult:
    extras = _vision_extras(paths, sizes, line_h=line_h, mode=mode, n_cols=n_cols, layout=layout, extra=extra)
    label = " ".join(
        f"[image {p.name} {w}x{h} high={openai_image_tokens(w, h, 'high')} low=85]"
        for p, (w, h) in zip(paths, sizes, strict=True)
    )
    return CodecResult(
        name=name,
        family="images",
        text=label,
        image_paths=[str(p) for p in paths],
        decode_instructions=decode,
        reversible=reversible,
        notes=notes,
        extras=extras,
    )


def _save_preview_pair(path: Path, size: tuple[int, int], tag: str) -> None:
    dest = IMAGES / "previews" / f"{tag}_scaled.png"
    try:
        _save_scaled_preview(path, dest, size)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Codecs
# ---------------------------------------------------------------------------


@fn_codec(
    "img_1tile_micro",
    "images",
    "512×512 1-bit compact ledger — 1 tile / 255 high tokens. Glyphs ~4px.",
)
def img_1tile_micro(bundle: Bundle) -> CodecResult:
    lines = [_compact_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_1tile_micro.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=512,
        n_cols=10,
        font=_default_font(6),
        mode="1",
        header="YYMMDDacct cat±cccccc curr  cols↓→",
    )
    _save_preview_pair(path, (w, h), "1tile_micro")
    return _result(
        "img_1tile_micro",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=10,
        layout="10-col compact on a single 512 tile",
        decode=COMPACT_LEGEND,
        reversible=True,
        notes=(
            "Lower bound for a fair full ledger: 85+170=255. Ten columns of 4px-tall "
            "glyphs. Almost certainly not OCR-able. Proves 1-tile packing is a density stunt."
        ),
    )


@fn_codec(
    "img_2tile_compact",
    "images",
    "512×1024 1-bit compact 6-col — TARGET 425 high tokens (85+170*2).",
)
def img_2tile_compact(bundle: Bundle) -> CodecResult:
    lines = [_compact_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_2tile_compact.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=1024,
        n_cols=6,
        font=_default_font(8),
        mode="1",
        header="YYMMDDacct cat±cccccc curr  cols↓ then →",
    )
    _save_preview_pair(path, (w, h), "2tile_compact")
    return _result(
        "img_2tile_compact",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=6,
        layout="6-col compact 512×1024 native 2-tile",
        decode=COMPACT_LEGEND,
        reversible=True,
        notes=(
            "Fair full-ledger at the 2-tile budget. Native 512×1024 so the preprocessor "
            "does not rescale. Glyph height ~5px — borderline OCR. Beats yaml_like (12020) "
            "on cost IF a vision model can read it."
        ),
        extra={"target_high_tokens": 425},
    )


@fn_codec(
    "img_2tile_named",
    "images",
    "512×1024 named 6-col 1-bit — still 425 tokens, tinier glyphs to keep names.",
)
def img_2tile_named(bundle: Bundle) -> CodecResult:
    lines = [_named_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_2tile_named.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=1024,
        n_cols=6,
        font=_default_font(5),
        mode="1",
        header="YYMMDD amt cat4 merchant8  cols↓→",
    )
    _save_preview_pair(path, (w, h), "2tile_named")
    return _result(
        "img_2tile_named",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=6,
        layout="6-col named 512×1024 native 2-tile",
        decode=NAMED_LEGEND,
        reversible=True,
        notes="Same 425-token canvas as img_2tile_compact but size=5 named lines. Worse OCR, more text.",
    )


@fn_codec(
    "img_packed_bitmap",
    "images",
    "5×7 packed 1-bit stamps, 6-col 512×1024 compact — 425 tokens, zero pad.",
)
def img_packed_bitmap(bundle: Bundle) -> CodecResult:
    lines = [_packed_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_packed_bitmap.png"
    w, h, lh = _render_bitmap_grid(
        lines,
        path,
        width=512,
        height=1024,
        n_cols=7,
        header="5x7 ddd acct cat signed-cents curr",
    )
    _save_preview_pair(path, (w, h), "packed_bitmap")
    packed_legend = (
        f"Each row is 13 chars: DDD (days since {EPOCH}) + acct(m/s/c) + cat_hex + "
        "signed 6-digit cents + curr(e/u). "
        + COMPACT_LEGEND.split("Each row is 16 chars: YYMMDD + acct(m/s/c) + cat_hex + signed 6-digit cents + curr(e/u). ", 1)[-1]
        + " Glyphs are a 5x7 pixel font with 0px tracking (not a TTF)."
    )
    return _result(
        "img_packed_bitmap",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=7,
        layout="packed 5×7 bitmap cells, 7-col 512×1024, 0 padding",
        decode=packed_legend,
        reversible=True,
        notes=(
            "Packed bitmap vs TTF: 5×7 LED stamps, 0px tracking, 13-char day-index rows "
            "(16-char×5×7×1000 exceeds 2-tile pixels). Same 425-token budget. Crisp 1-bit; "
            "may look unlike natural photos VLMs trained on."
        ),
        extra={"glyph": "5x7", "tracking_px": 0, "row_chars": 13, "epoch": EPOCH},
    )


@fn_codec(
    "img_3tile_4col",
    "images",
    "512×1536 4-col named 1-bit — 3 tiles / 595 high tokens.",
)
def img_3tile_4col(bundle: Bundle) -> CodecResult:
    lines = [_named_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_3tile_4col.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=1536,
        n_cols=4,
        font=_default_font(6),
        mode="1",
        header="YYMMDD amt cat4 merchant8  4col ↓→",
    )
    _save_preview_pair(path, (w, h), "3tile_4col")
    return _result(
        "img_3tile_4col",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=4,
        layout="4-col named 512×1536 native 3-tile",
        decode=NAMED_LEGEND,
        reversible=True,
        notes="Mid budget: 85+170*3=595. 4 columns as requested, glyphs ~5px. Under 765, over 425.",
    )


@fn_codec(
    "img_4col_1bit",
    "images",
    "FAIR headline: 512×2048 4-col named 1-bit — 765 tokens, native 8px, no crush.",
)
def img_4col_1bit(bundle: Bundle) -> CodecResult:
    lines = [_named_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_4col_1bit.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=2048,
        n_cols=4,
        font=_default_font(8),
        mode="1",
        header="YYMMDD amt cat4 name8 | 4 col top→bottom then →",
        line_h_override=8,
    )
    _save_preview_pair(path, (w, h), "4col_1bit")
    return _result(
        "img_4col_1bit",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=4,
        layout="4-col named 512×2048 native 4-tile (same cost as tall PNG, no downscale)",
        decode=NAMED_LEGEND,
        reversible=True,
        notes=(
            "Fair full-ledger packing. Same 765 high-detail tokens as the 1000-line tall "
            "PNG, but max side is 2048 so glyphs stay ~7–8px instead of being crushed to ~2px. "
            "This is the layout to test whether a model can actually read 1000 painted lines."
        ),
    )


@fn_codec(
    "img_4col_gray",
    "images",
    "Same 4-col 512×2048 grid saved as 8-bit grayscale PNG (not 1-bit).",
)
def img_4col_gray(bundle: Bundle) -> CodecResult:
    lines = [_named_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_4col_gray.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=2048,
        n_cols=4,
        font=_default_font(8),
        mode="L",
        header="YYMMDD amt cat4 name8 | 4 col (grayscale L)",
        line_h_override=8,
    )
    _save_preview_pair(path, (w, h), "4col_gray")
    return _result(
        "img_4col_gray",
        [path],
        [(w, h)],
        line_h=lh,
        mode="L",
        n_cols=4,
        layout="4-col named 512×2048 grayscale",
        decode=NAMED_LEGEND,
        reversible=True,
        notes="Tile tokens identical to img_4col_1bit. File bytes differ. Antialiasing if the font provides it.",
    )


@fn_codec(
    "img_4col_color",
    "images",
    "Same 4-col 512×2048 RGB with category color gutters (text stays black).",
)
def img_4col_color(bundle: Bundle) -> CodecResult:
    lines = [_named_line(tx) for tx in bundle.transactions]
    gutters = [_cat_rgb(tx.category) for tx in bundle.transactions]
    path = IMAGES / "extra_4col_color.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=2048,
        n_cols=4,
        font=_default_font(8),
        mode="RGB",
        header="YYMMDD amt cat4 name8 | color gutter = category",
        line_h_override=8,
        gutters=gutters,
    )
    _save_preview_pair(path, (w, h), "4col_color")
    return _result(
        "img_4col_color",
        [path],
        [(w, h)],
        line_h=lh,
        mode="RGB",
        n_cols=4,
        layout="4-col named 512×2048 RGB + category gutters",
        decode=NAMED_LEGEND + " Left 3px gutter is a category color (legend = CAT_HEX order on the HSV wheel).",
        reversible=True,
        notes=(
            "Vision models train on color photos. Gutters keep glyphs black-on-white (OCR) "
            "while making category mass visible (reports / optimize). Same 765 tiles as 1-bit."
        ),
        extra={"gutter_px": 3, "gutter_meaning": "category hue"},
    )


@fn_codec(
    "img_5col_large_glyph",
    "images",
    "512×2048 compact 5-col size=11 — 765 tokens, largest native glyphs that still fit.",
)
def img_5col_large_glyph(bundle: Bundle) -> CodecResult:
    lines = [_compact_line(tx) for tx in bundle.transactions]
    path = IMAGES / "extra_5col_large_glyph.png"
    w, h, lh = _render_text_grid(
        lines,
        path,
        width=512,
        height=2048,
        n_cols=5,
        font=_default_font(11),
        mode="1",
        header="compact 16ch 5col size11 native 4tile",
    )
    _save_preview_pair(path, (w, h), "5col_large_glyph")
    return _result(
        "img_5col_large_glyph",
        [path],
        [(w, h)],
        line_h=lh,
        mode="1",
        n_cols=5,
        layout="5-col compact 512×2048 native 4-tile, ~8px glyphs",
        decode=COMPACT_LEGEND,
        reversible=True,
        notes=(
            "Same 765-token 4-tile box as img_4col_1bit but compact 16-char rows so the "
            "font can grow to size=11 (~8px). Best glyph height at the tall-PNG budget."
        ),
    )


@fn_codec(
    "img_split_4x512",
    "images",
    "Four 512×512 named pages — 4×255=1020 high tokens. Split vs one strip.",
)
def img_split_4x512(bundle: Bundle) -> CodecResult:
    lines = [_named_line(tx) for tx in bundle.transactions]
    font = _default_font(8)
    paths: list[Path] = []
    sizes: list[tuple[int, int]] = []
    n_pages = 4
    chunk = math.ceil(len(lines) / n_pages)
    line_h = 8
    for i in range(n_pages):
        part = lines[i * chunk : (i + 1) * chunk]
        path = IMAGES / f"extra_split_512_{i}.png"
        w, h, line_h = _render_text_grid(
            part,
            path,
            width=512,
            height=512,
            n_cols=4,
            font=font,
            mode="1",
            header=f"page {i + 1}/4 YYMMDD amt cat4 name8",
            line_h_override=8,
        )
        paths.append(path)
        sizes.append((w, h))
    return _result(
        "img_split_4x512",
        paths,
        sizes,
        line_h=line_h,
        mode="1",
        n_cols=4,
        layout="4 separate 512×512 pages, 4-col named",
        decode=NAMED_LEGEND + " Four page images in order 1..4. Concatenate columns across pages.",
        reversible=True,
        notes=(
            "Same native 8px glyphs as img_4col_1bit but pays 85 base tokens four times "
            "(1020 vs 765). Splitting loses on the tile formula whenever one image can "
            "hold the same pixels as a 512×2048 strip."
        ),
        extra={"pages": 4},
    )


@fn_codec(
    "img_split_2x2tile",
    "images",
    "Two 512×1024 compact pages — 2×425=850 high tokens.",
)
def img_split_2x2tile(bundle: Bundle) -> CodecResult:
    lines = [_compact_line(tx) for tx in bundle.transactions]
    font = _default_font(8)
    paths: list[Path] = []
    sizes: list[tuple[int, int]] = []
    mid = math.ceil(len(lines) / 2)
    line_h = 6
    for i, part in enumerate((lines[:mid], lines[mid:])):
        path = IMAGES / f"extra_split_2tile_{i}.png"
        w, h, line_h = _render_text_grid(
            part,
            path,
            width=512,
            height=1024,
            n_cols=6,
            font=font,
            mode="1",
            header=f"page {i + 1}/2 compact 16ch",
        )
        paths.append(path)
        sizes.append((w, h))
    return _result(
        "img_split_2x2tile",
        paths,
        sizes,
        line_h=line_h,
        mode="1",
        n_cols=6,
        layout="2 separate 512×1024 pages, 6-col compact",
        decode=COMPACT_LEGEND + " Two page images in chronological order.",
        reversible=True,
        notes="Two 2-tile images = 850 tokens vs one 512×2048 at 765 or one 512×1024 at 425.",
        extra={"pages": 2},
    )


def _monthly_series(bundle: Bundle) -> dict[str, Any]:
    from experiments.tokenization.gold import DISCRETIONARY, NECESSARY

    txs = bundle.transactions
    by_cat: dict[str, float] = defaultdict(float)
    by_month_spend: dict[str, float] = defaultdict(float)
    by_month_inc: dict[str, float] = defaultdict(float)
    by_month_n: dict[str, int] = defaultdict(int)
    n_exp = n_inc = 0
    exp = inc = 0.0
    for tx in txs:
        cat = tx.category or "uncategorized"
        by_cat[cat] += tx.value
        mk = month_key(tx.occurred_on)
        by_month_n[mk] += 1
        if tx.value < 0:
            by_month_spend[mk] += -tx.value
            exp += -tx.value
            n_exp += 1
        else:
            by_month_inc[mk] += tx.value
            inc += tx.value
            n_inc += 1
    months = sorted(set(by_month_spend) | set(by_month_inc))
    spend_cats = sorted(
        ((name, round(-total, 2)) for name, total in by_cat.items() if total < 0),
        key=lambda kv: kv[1],
        reverse=True,
    )
    return {
        "n": len(txs),
        "n_inc": n_inc,
        "n_exp": n_exp,
        "inc": round(inc, 2),
        "exp": round(exp, 2),
        "net": round(inc - exp, 2),
        "months": months,
        "by_month_spend": by_month_spend,
        "by_month_inc": by_month_inc,
        "by_month_n": by_month_n,
        "spend_cats": spend_cats,
        "discretionary": DISCRETIONARY,
        "necessary": NECESSARY,
        "subs": bundle.subscriptions,
    }


def _render_monthly_card(bundle: Bundle, path: Path) -> tuple[int, int, int]:
    """Two-panel 512×512 table: months | categories+subs. No overlapping columns."""
    data = _monthly_series(bundle)
    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGB", (512, 512), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    font = _mono_font(11)
    ink = (20, 20, 20)
    muted = (90, 90, 90)
    y = 4
    draw.text((8, y), f"n={data['n']}  inc_n={data['n_inc']}  exp_n={data['n_exp']}", fill=ink, font=font)
    y += 16
    # Totals are NOT painted — sum the month columns. That is the point vs summary_card.
    draw.line((8, y, 504, y), fill=(180, 180, 180))
    y += 4
    left_x, right_x = 8, 268
    draw.line((256, y, 256, 504), fill=(180, 180, 180))
    draw.text((left_x, y), "month    spend    income  n", fill=muted, font=font)
    draw.text((right_x, y), "T category       spend", fill=muted, font=font)
    y += 14
    line_h = 14
    row_y = y
    for mk in data["months"]:
        draw.text(
            (left_x, row_y),
            f"{mk} {data['by_month_spend'][mk]:8.2f} {data['by_month_inc'][mk]:8.2f} {data['by_month_n'][mk]:3d}",
            fill=ink,
            font=font,
        )
        row_y += line_h
    draw.text((left_x, row_y + 4), "forecast = mean(spend last 3 mo)", fill=muted, font=font)

    row_y = y
    for name, spend in data["spend_cats"]:
        tag = "D" if name in data["discretionary"] else ("N" if name in data["necessary"] else "O")
        draw.text((right_x, row_y), f"{tag} {name:<14} {spend:8.2f}", fill=ink, font=font)
        row_y += line_h
    row_y += 6
    draw.text((right_x, row_y), "subscriptions", fill=muted, font=font)
    row_y += line_h
    for sub in data["subs"]:
        draw.text((right_x, row_y), f"{(sub.name or '')[:16]:<16} {sub.value}", fill=ink, font=font)
        row_y += line_h
    img.save(path, optimize=True)
    return 512, 512, line_h


@fn_codec(
    "img_monthly_table",
    "images",
    "Monthly+category table image. Agent-mode bound, reversible=False.",
)
def img_monthly_table(bundle: Bundle) -> CodecResult:
    path = IMAGES / "extra_monthly_table.png"
    w, h, lh = _render_monthly_card(bundle, path)
    _save_preview_pair(path, (w, h), "monthly_table")
    return _result(
        "img_monthly_table",
        [path],
        [(w, h)],
        line_h=lh,
        mode="RGB",
        n_cols=2,
        layout="2-panel monthly | category+subs table, 512×512 → 1 tile",
        decode=(
            "Transcribe the table. Reports: use n / sum_inc / sum_exp / the category list "
            "(top spend = max category). Optimize: rows tagged D are discretionary; pick the "
            "largest D. Forecasts: mean of spend over the last 3 month rows. "
            "This image is NOT a raw ledger."
        ),
        reversible=False,
        notes=(
            "Practical agent-mode bound, not a fair codec. Paints monthly and category "
            "aggregates (the model still picks top category / last-3 mean). Not the same "
            "cheat as img_summary_card (which paints gold net/top/forecast directly), but "
            "it is still pre-aggregation. Allowed as a bound only."
        ),
        extra={"preaggregated": True, "panels": 2},
    )


# ---------------------------------------------------------------------------
# Measurement + optional one-shot vision probe
# ---------------------------------------------------------------------------


def _load_dotenv() -> dict[str, str]:
    values: dict[str, str] = {}
    env_path = Path("/workspace/.env")
    if not env_path.exists():
        return values
    for line in env_path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, raw = line.split("=", 1)
        values[name.strip()] = raw.strip().strip('"')
    return values


def encode_image_codecs(bundle: Bundle) -> list[CodecResult]:
    from experiments.tokenization.codecs.base import all_codecs, load_all

    load_all()
    out: list[CodecResult] = []
    for codec in all_codecs():
        if codec.family != "images":
            continue
        if not codec.name.startswith("img_"):
            continue
        out.append(codec.encode(bundle))
    return out


def _md_table(rows: list[dict[str, Any]]) -> str:
    header = (
        "| codec | rev | W×H | cols | mode | bytes | tiles | high | low | "
        "eff. line-h | notes |"
    )
    sep = "| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |"
    lines = [header, sep]
    for row in rows:
        wh = row["wh"]
        note = (row.get("notes") or "").replace("|", "/")[:80]
        lines.append(
            f"| `{row['name']}` | {row['rev']} | {wh} | {row['n_cols']} | {row['mode']} | "
            f"{row['bytes']} | {row['tiles']} | **{row['high']}** | {row['low']} | "
            f"{row['eff']} | {note} |"
        )
    return "\n".join(lines)


def write_report(
    results: list[CodecResult],
    *,
    probe: dict[str, Any] | None = None,
    tall_ref: dict[str, Any] | None = None,
) -> Path:
    SUBAGENT_DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for item in results:
        ex = item.extras or {}
        w, h = ex.get("width"), ex.get("height")
        if isinstance(w, list):
            wh = " + ".join(f"{a}×{b}" for a, b in zip(w, h))
        else:
            wh = f"{w}×{h}"
        tiles = ex.get("tiles_total")
        rows.append(
            {
                "name": item.name,
                "rev": "yes" if item.reversible else "NO",
                "wh": wh,
                "n_cols": ex.get("n_cols"),
                "mode": ex.get("mode"),
                "bytes": ex.get("bytes"),
                "tiles": tiles,
                "high": ex.get("openai_high_tokens"),
                "low": ex.get("openai_low_tokens"),
                "eff": ex.get("effective_line_h"),
                "notes": item.notes,
                "extras": ex,
                "reversible": item.reversible,
            }
        )
    rows.sort(key=lambda r: (r["high"] is None, r["high"] or 10**9, r["name"]))

    tall = tall_ref or {
        "width": 360,
        "height": 9004,
        "line_h": 9,
        "high": openai_image_tokens(360, 9004, "high"),
        "low": 85,
    }
    sw, sh, tx, ty = _openai_scaled(tall["width"], tall["height"])
    tall_eff = _effective_line_h(tall["width"], tall["height"], tall["line_h"])

    fair = [r for r in rows if r["reversible"] and r["name"].startswith("img_")]
    under_425 = [r for r in fair if isinstance(r["high"], int) and r["high"] <= 425]
    headline = next((r for r in rows if r["name"] == "img_4col_1bit"), None)
    two_tile = next((r for r in rows if r["name"] == "img_2tile_compact"), None)
    monthly = next((r for r in rows if r["name"] == "img_monthly_table"), None)

    parts = [
        "# Image encodings — specialist 4/5",
        "",
        "Goal: minimize **real** OpenAI high-detail vision tokens while keeping the",
        "1000-row ledger OCR-able enough for reports / optimize / forecasts.",
        "",
        "## Tile formula (lab canonical)",
        "",
        "```",
        "if max(w,h) > 2048: scale so longest side = 2048",
        "if min(w,h) > 768:  scale so shortest side = 768",
        "tiles = ceil(w/512) * ceil(h/512)",
        "high_tokens = 85 + 170 * tiles",
        "low_tokens  = 85          # always, one 512×512 thumbnail — quality risk",
        "```",
        "",
        "Implemented in `codecs/images.py` `openai_image_tokens`. Placeholder text",
        "`[image ledger_full.png 360x9004]` is **11 text tokens and a lie**.",
        "",
        "## Why the tall 1000-line PNG is a trap",
        "",
        f"- Canvas `{tall['width']}×{tall['height']}`, line-h `{tall['line_h']}` → "
        f"**{tall['high']}** high / {tall['low']} low.",
        f"- Preprocessor scale: `{tall['width']}×{tall['height']}` → `{sw}×{sh}` "
        f"({tx}×{ty} tiles).",
        f"- Effective glyph height after scale: **{tall_eff} px**. Humans and VLMs do",
        "  not OCR 2px type. JPEG q=8 keeps this tile count and adds block noise.",
        "- **Fix:** keep `max(w,h) ≤ 2048` and pack with 2–5 columns so each 512px tile",
        "  is native resolution, not a crushed strip.",
        "",
        "## Results",
        "",
        _md_table(rows),
        "",
        "## Fair full-ledger headline",
        "",
    ]
    if headline:
        parts += [
            f"**`{headline['name']}`** — `{headline['wh']}`, {headline['n_cols']} columns, "
            f"mode `{headline['mode']}`, **{headline['high']} high-detail tokens**, "
            f"{headline['low']} low-detail, {headline['bytes']} bytes, effective line-h "
            f"{headline['eff']} px (no preprocessor crush).",
            "",
            "This matches the 765-token cost of the tall PNG *without* destroying glyphs.",
            "Named `YYMMDD amt cat4 name8` rows, 4 columns, chronological down then",
            "across. Reversible with the cat4 legend. Compared with `yaml_like` at 12,020",
            "GPT-5 text tokens this is ~6.4% of that cost **if OCR works**.",
            "",
        ]
    if two_tile:
        parts += [
            f"**2-tile target:** `{two_tile['name']}` is **{two_tile['high']}** tokens "
            f"(≤425). Compact 16-char reversible rows, 6 columns on 512×1024, 1-bit PNG, "
            f"effective line-h {two_tile['eff']} px. That is the cheapest *fair* packing",
            "that still fits 1000 rows without scaling. Glyphs are ~5px — this is the",
            "readability cliff.",
            "",
        ]
    if monthly:
        parts += [
            f"**Agent-mode bound (not a winner):** `{monthly['name']}` paints monthly +",
            f"category totals, `reversible=False`, **{monthly['high']}** high / "
            f"{monthly['low']} low. Unlike `img_summary_card` it does **not** paint",
            "`top=rent` / `fc_spend=...` as finished answers; the model still has to pick",
            "the max category and average the last 3 month rows. Still pre-aggregation.",
            "",
        ]
    parts += [
        "## Split vs one strip",
        "",
        "- One 512×2048 image = 4 tiles = **765** (85 paid once).",
        "- Four 512×512 images = 4×(85+170) = **1020**. Same pixels, **+255** for the extra bases.",
        "- Two 512×1024 images = 2×425 = **850**, still worse than one 4-tile strip.",
        "- Splitting only wins if a *single* canvas would exceed 2048 on a side and get crushed.",
        "  Our 4-col 512×2048 already avoids that, so splits are strictly more expensive.",
        "",
        "## 1-bit vs packed bitmap vs color",
        "",
        "- **1-bit PNG** (`img_4col_1bit`, `img_2tile_compact`): smallest files, sharp glyphs,",
        "  no dither. Preferred for OCR.",
        "- **Grayscale L** (`img_4col_gray`): same tiles, larger files; only useful if a",
        "  font antialiases (default bitmap font barely does).",
        "- **RGB + category gutters** (`img_4col_color`): same tiles, largest files. Black",
        "  text preserved; 3px hue gutter may help reports/optimize without painting gold.",
        "- **Packed 5×7 bitmap** (`img_packed_bitmap`): 2-tile budget, LED stamps, 0 tracking.",
        "  Densest reversible packing. Looks unlike natural photos; OCR is an open question.",
        "",
        "## Low detail = 85 (quality risk)",
        "",
        "Every image is 85 tokens at `detail=low` because the model only gets a 512×512",
        "thumbnail. For `img_4col_1bit` that means 2048→512 vertical squash (4×): 8px",
        "glyphs become 2px — same failure mode as the tall PNG. Low-detail is only",
        "plausible for `img_monthly_table` (already ≤512×512). Do not quote 85 as a",
        "fair full-ledger cost.",
        "",
        "## Can a model actually read 1000 painted lines?",
        "",
        "**Tall PNG (360×9004): no.** After the official scale the type is ~2px. That",
        "765-token number is real and also useless.",
        "",
        "**Native 4-col 512×2048 (`img_4col_1bit`): maybe, not proven by tile math.**",
        "Glyphs stay ~7–8px at high detail, 1000 rows, 4 columns. A VLM *can* read a",
        "screenshot of a table at that size, but 1000 rows is a long sequential scan;",
        "expect dropped rows, column mix-ups, and arithmetic errors even if glyphs are",
        "legible. Counting `n_transactions=1000` is easier than summing 942 expenses.",
        "",
        "**2-tile compact (512×1024, ~5px): unlikely for sums.** Legible to a determined",
        "human with zoom; VLMs usually fail at 4–6px condensed type, especially 6 columns.",
        "",
        "**1-tile micro (~4px, 10 columns): no.**",
        "",
        "Two-column full ledgers were tried on paper: 500 rows × 8px = 4000px height,",
        "which exceeds 2048 and gets crushed. **Minimum columns for native 8px on a",
        "4-tile canvas is 4.** That is why the fair packing is a 4-column grid, not a",
        "2-column book page.",
        "",
    ]
    if probe is not None:
        parts += [
            "## Gateway vision probe (one image, ≤$1, no retries)",
            "",
            f"- model: `{probe.get('model', '—')}`",
            f"- image: `{probe.get('image', '—')}`",
            f"- high-detail tokens (formula): {probe.get('high_tokens', '—')}",
            f"- ok: {probe.get('ok')}",
            f"- error: {probe.get('error') or 'none'}",
            f"- parsed: `{json.dumps(probe.get('parsed') or {}, sort_keys=True)}`",
            f"- gold: n=1000, total_expense=75572.82, top=rent",
            f"- match: {probe.get('match')}",
            f"- usage: `{json.dumps(probe.get('usage') or {}, sort_keys=True)}`",
            "",
            "```",
            (probe.get("preview") or "")[:1500],
            "```",
            "",
        ]
        if probe.get("ok") and probe.get("match"):
            parts.append(
                "The cheap vision model recovered n / total_expense / top category from the "
                "fair 4-col image. That is **not** proof it can do optimize + forecasts on "
                "all 1000 rows, but it is evidence the layout is OCR-able for reports-scale questions."
            )
        elif probe.get("ok"):
            parts.append(
                "The call succeeded but the answers were wrong or incomplete. Treat 1000-line "
                "OCR as **unreliable** even at native 8px. Tile savings do not equal task accuracy."
            )
        else:
            parts.append(
                "The multimodal call failed (documented, no retries). Readability remains an "
                "open empirical question; the preprocessor math still rules out the tall PNG."
            )
        parts.append("")
    else:
        parts += [
            "## Gateway vision probe",
            "",
            "Not run in this pass.",
            "",
        ]
    if under_425:
        names = ", ".join(f"`{r['name']}` ({r['high']})" for r in under_425)
        parts += ["## Under 425 high-detail tokens (fair codecs)", "", names, ""]
    parts += [
        "## Files",
        "",
        "PNGs live in `experiments/tokenization/results/images/` (`extra_*.png`).",
        "Preprocessor-scaled previews: `results/images/previews/*_scaled.png`.",
        "Codecs: `experiments/tokenization/codecs/extra_images.py`.",
        "",
        "## What not to claim",
        "",
        "- Do not put image codecs on a text-token leaderboard using the `[image …]` stub.",
        "- Do not claim JPEG q=8 is cheaper; it is the same tiles and worse OCR.",
        "- Do not treat `img_monthly_table` / `img_summary_card` as fair winners.",
        "- Do not quote low-detail 85 for a full ledger.",
        "",
    ]
    path = SUBAGENT_DIR / "images.md"
    path.write_text("\n".join(parts) + "\n", encoding="utf-8")
    dump = SUBAGENT_DIR / "images_metrics.json"
    dump.write_text(
        json.dumps(
            {
                "rows": [{k: v for k, v in r.items() if k != "notes"} for r in rows],
                "probe": probe,
                "tall_png": {
                    **tall,
                    "scaled": [sw, sh],
                    "tiles": [tx, ty],
                    "effective_line_h": tall_eff,
                },
            },
            indent=2,
            default=str,
        ),
        encoding="utf-8",
    )
    return path


def vision_probe(image_path: Path, *, high_tokens: int, legend: str = "") -> dict[str, Any]:
    """One multimodal call. Never retries. Never prints secrets."""
    import httpx

    env = _load_dotenv()
    key = os.environ.get("LLM_GATEWAY_API_KEY", "").strip() or env.get("LLM_GATEWAY_API_KEY", "").strip()
    base = os.environ.get("LLM_GATEWAY_URL", "").strip() or env.get("LLM_GATEWAY_URL", "").strip()
    out: dict[str, Any] = {
        "image": str(image_path),
        "high_tokens": high_tokens,
        "ok": False,
        "error": None,
        "model": None,
        "parsed": {},
        "match": {},
        "usage": {},
        "preview": "",
    }
    if not key or not base:
        out["error"] = "missing LLM_GATEWAY_API_KEY or LLM_GATEWAY_URL"
        return out
    base = base.rstrip("/")
    chat_url = base if base.endswith("/chat/completions") else base + "/chat/completions"
    models_url = (
        base[: -len("/chat/completions")] + "/models"
        if base.endswith("/chat/completions")
        else base + "/models"
    )
    preferred = [
        "google/gemini-2.5-flash",
        "google/gemini-2.0-flash-001",
        "google/gemini-2.5-flash-lite",
        "openai/gpt-4.1-nano",
        "openai/gpt-4.1-mini",
        "qwen/qwen2.5-vl-72b-instruct",
        "qwen/qwen-2.5-vl-7b-instruct",
        "meta-llama/llama-3.2-11b-vision-instruct",
    ]
    model = preferred[0]
    try:
        with httpx.Client(timeout=30.0) as client:
            data = client.get(models_url, headers={"Authorization": f"Bearer {key}"}).json()
        ids = {item.get("id") for item in data.get("data", []) if isinstance(item, dict)}
        for mid in preferred:
            if mid in ids:
                model = mid
                break
    except Exception as exc:
        out["error"] = f"model list failed; trying {model} anyway: {type(exc).__name__}"
    out["model"] = model
    raw = image_path.read_bytes()
    b64 = base64.b64encode(raw).decode("ascii")
    mime = "image/png" if image_path.suffix.lower() == ".png" else "image/jpeg"
    prompt = (
        "You are reading a painted ledger image. Multiple columns, filled top-to-bottom "
        "then left-to-right, chronological. "
        + (legend + " " if legend else "")
        + "Return ONLY JSON with keys n_transactions (int), total_expense (number, positive "
        "magnitude of all negative amounts), top_category (string, full category name with "
        "the largest expense magnitude, e.g. rent not rent's cat4). "
        "Do not guess a round 1000 without counting. Round money to 2 decimals."
    )
    body = {
        "model": model,
        "temperature": 0,
        "max_tokens": 250,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime};base64,{b64}",
                            "detail": "high",
                        },
                    },
                ],
            }
        ],
    }
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/mikhailmits/mous",
        "X-Title": "mous-tokenization-lab-images",
    }
    try:
        with httpx.Client(timeout=120.0) as client:
            response = client.post(chat_url, headers=headers, json=body)
            if response.status_code >= 400:
                out["error"] = f"HTTP {response.status_code}: {response.text[:400]}"
                return out
            payload = response.json()
    except Exception as exc:
        out["error"] = f"{type(exc).__name__}: {exc}"[:400]
        return out
    try:
        content = payload["choices"][0]["message"]["content"] or ""
    except Exception:
        content = json.dumps(payload)[:1500]
    out["preview"] = content[:1500]
    out["usage"] = payload.get("usage") or {}
    text = content.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
    start, end = text.find("{"), text.rfind("}")
    parsed: dict[str, Any] = {}
    if start != -1 and end != -1:
        try:
            parsed = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            parsed = {}
    out["parsed"] = parsed
    gold_n, gold_exp, gold_top = 1000, 75572.82, "rent"
    n = parsed.get("n_transactions")
    exp = parsed.get("total_expense")
    top = parsed.get("top_category") or parsed.get("top_category_by_spend")
    try:
        n_ok = int(n) == gold_n
    except (TypeError, ValueError):
        n_ok = False
    try:
        exp_ok = abs(float(exp) - gold_exp) / gold_exp <= 0.05
    except (TypeError, ValueError):
        exp_ok = False
    top_ok = isinstance(top, str) and top.strip().lower() == gold_top
    out["match"] = {
        "n_transactions": n_ok,
        "total_expense": exp_ok,
        "top_category": top_ok,
        "all": n_ok and exp_ok and top_ok,
    }
    out["ok"] = True
    return out


def main() -> None:
    from experiments.tokenization.bundle import load_bundle
    from experiments.tokenization.codecs.images import img_png_full

    bundle = load_bundle()
    # Ensure baseline tall PNG exists for the crush comparison / preview.
    try:
        img_png_full.encode(bundle)
        _save_preview_pair(IMAGES / "ledger_full.png", (360, 9004), "tall_png_original")
    except Exception:
        pass
    results = encode_image_codecs(bundle)
    probe = None
    headline = next((r for r in results if r.name == "img_4col_1bit"), None)
    if headline and headline.image_paths:
        probe = vision_probe(
            Path(headline.image_paths[0]),
            high_tokens=int((headline.extras or {}).get("openai_high_tokens") or 0),
            legend=headline.decode_instructions,
        )
    path = write_report(results, probe=probe)
    print(f"wrote {path}")
    for item in sorted(results, key=lambda r: (r.extras or {}).get("openai_high_tokens") or 0):
        ex = item.extras or {}
        print(
            f"{item.name:24} high={ex.get('openai_high_tokens')} low={ex.get('openai_low_tokens')} "
            f"bytes={ex.get('bytes')} {ex.get('width')}x{ex.get('height')} cols={ex.get('n_cols')} "
            f"eff={ex.get('effective_line_h')} rev={item.reversible}"
        )
    if probe:
        print(
            f"probe model={probe.get('model')} ok={probe.get('ok')} "
            f"match={probe.get('match')} err={probe.get('error')}"
        )


if __name__ == "__main__":
    main()
