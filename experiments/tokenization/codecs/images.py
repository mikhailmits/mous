"""(e) Render the ledger as compressed images with text on them."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from experiments.tokenization.bundle import Bundle
from experiments.tokenization.codecs.base import CodecResult, fn_codec
from experiments.tokenization.paths import IMAGES


def openai_image_tokens(width: int, height: int, detail: str = "high") -> int:
    """Approximate GPT-4o / GPT-5 vision tokens (tile formula)."""
    if detail == "low":
        return 85
    w, h = width, height
    if w > 2048 or h > 2048:
        scale = 2048 / max(w, h)
        w, h = int(w * scale), int(h * scale)
    if min(w, h) > 768:
        scale = 768 / min(w, h)
        w, h = int(w * scale), int(h * scale)
    tiles_x = (w + 511) // 512
    tiles_y = (h + 511) // 512
    return 85 + 170 * tiles_x * tiles_y


def _font() -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=8)
    except TypeError:
        return ImageFont.load_default()


def _lines(bundle: Bundle, sticky: bool = False) -> list[str]:
    out = []
    for tx in bundle.transactions:
        if sticky:
            out.append(
                f"{tx.occurred_on}{tx.value}{tx.currency}{tx.name.replace(' ', '')}"
            )
        else:
            out.append(
                f"{tx.occurred_on} {tx.name} {tx.value}{tx.currency} {tx.category or ''}"
            )
    return out


def _render(lines: list[str], path: Path, width: int = 320) -> tuple[int, int]:
    font = _font()
    dummy = Image.new("L", (1, 1), 255)
    draw = ImageDraw.Draw(dummy)
    line_h = 9
    height = max(16, line_h * len(lines) + 4)
    img = Image.new("L", (width, height), 255)
    draw = ImageDraw.Draw(img)
    y = 1
    for line in lines:
        draw.text((1, y), line[:80], fill=0, font=font)
        y += line_h
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    return img.size


def _jpeg(lines: list[str], path: Path, quality: int, width: int = 320) -> tuple[int, int]:
    font = _font()
    line_h = 9
    height = max(16, line_h * len(lines) + 4)
    img = Image.new("L", (width, height), 255)
    draw = ImageDraw.Draw(img)
    y = 1
    for line in lines:
        draw.text((1, y), line[:80], fill=0, font=font)
        y += line_h
    rgb = img.convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb.save(path, format="JPEG", quality=quality, optimize=True)
    return rgb.size


@fn_codec("img_png_full", "images", "Full ledger as one tall 1-bit-ish PNG.")
def img_png_full(bundle: Bundle) -> CodecResult:
    path = IMAGES / "ledger_full.png"
    w, h = _render(_lines(bundle), path, width=360)
    return CodecResult(
        name="img_png_full",
        family="images",
        text=f"[image {path.name} {w}x{h}]",
        image_paths=[str(path)],
        decode_instructions="Read every line of text painted on the image.",
        extras={
            "width": w,
            "height": h,
            "bytes": path.stat().st_size,
            "openai_high_tokens": openai_image_tokens(w, h, "high"),
            "openai_low_tokens": openai_image_tokens(w, h, "low"),
        },
        notes="Vision tokens dominate if the strip is tall.",
    )


@fn_codec("img_jpeg_q8", "images", "Same ledger as JPEG quality=8.")
def img_jpeg_q8(bundle: Bundle) -> CodecResult:
    path = IMAGES / "ledger_q8.jpg"
    w, h = _jpeg(_lines(bundle), path, quality=8, width=280)
    return CodecResult(
        name="img_jpeg_q8",
        family="images",
        text=f"[image {path.name} {w}x{h}]",
        image_paths=[str(path)],
        decode_instructions="OCR the compressed JPEG; expect artifacts.",
        extras={
            "width": w,
            "height": h,
            "bytes": path.stat().st_size,
            "openai_high_tokens": openai_image_tokens(w, h, "high"),
            "openai_low_tokens": openai_image_tokens(w, h, "low"),
        },
        reversible=False,
        notes="Lossy. OCR quality will drop.",
    )


@fn_codec("img_png_sticky_grid", "images", "Sticky no-space lines painted densely.")
def img_png_sticky_grid(bundle: Bundle) -> CodecResult:
    path = IMAGES / "ledger_sticky.png"
    w, h = _render(_lines(bundle, sticky=True), path, width=240)
    return CodecResult(
        name="img_png_sticky_grid",
        family="images",
        text=f"[image {path.name} {w}x{h}]",
        image_paths=[str(path)],
        decode_instructions="Read glued amount+currency+name lines from the image.",
        extras={
            "width": w,
            "height": h,
            "bytes": path.stat().st_size,
            "openai_high_tokens": openai_image_tokens(w, h, "high"),
            "openai_low_tokens": openai_image_tokens(w, h, "low"),
        },
    )


@fn_codec("img_summary_card", "images", "Only aggregates painted — tiny image, lossy vs raw tx.")
def img_summary_card(bundle: Bundle) -> CodecResult:
    from experiments.tokenization.gold import compute_gold

    gold = compute_gold(bundle)
    lines = [
        f"n={gold['reports']['n_transactions']} net={gold['reports']['net']}",
        f"in={gold['reports']['total_income']} out={gold['reports']['total_expense']}",
        f"top={gold['reports']['top_category_by_spend']} {gold['reports']['top_category_spend']}",
        f"fc_spend={gold['forecasts']['next_month_spend_naive']}",
        f"disc={gold['optimize']['discretionary_share']}",
    ]
    path = IMAGES / "summary_card.png"
    w, h = _render(lines, path, width=220)
    return CodecResult(
        name="img_summary_card",
        family="images",
        text="\n".join(lines),
        image_paths=[str(path)],
        decode_instructions="The image already contains gold aggregates; transcribe them.",
        reversible=False,
        extras={
            "width": w,
            "height": h,
            "bytes": path.stat().st_size,
            "openai_high_tokens": openai_image_tokens(w, h, "high"),
            "openai_low_tokens": openai_image_tokens(w, h, "low"),
        },
        notes="Cheats by pre-aggregating. Useful as a lower bound, not a fair codec.",
    )
