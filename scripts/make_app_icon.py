#!/usr/bin/env python3
"""Build macOS AppIcon master PNG + .icns from a mark PNG.

Creates a dark-navy squircle (transparent outside) with the mark centered
at ~62% of the icon side, then packs sizes via iconutil.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "macos" / "Mous" / "Icon"

SIZE = 1024
# Wordmark width inside the squircle. The source letters are a wide, short
# "mo", so this is capped by height as well in compose_icon.
MARK_WIDTH_FRAC = 0.88
MARK_HEIGHT_FRAC = 0.50

# Quiet near-black cards (~screenshot charcoal) with soft theme hues.
# Leaf is the strongest dark pairing; the rest sit quieter.
# White is warm paper with soft ink, not black on pure white.
THEME_COLORS: dict[str, tuple[tuple[int, int, int], tuple[int, int, int]]] = {
    "logo-variant": ((118, 178, 72), (30, 34, 28)),
    "logo-variant-1": ((156, 160, 148), (34, 34, 32)),
    "logo-variant-2": ((112, 168, 78), (32, 32, 30)),
    "logo-variant-3": ((128, 168, 156), (30, 34, 33)),
    "logo-variant-4": ((112, 156, 164), (28, 32, 34)),
    "logo-variant-5": ((176, 140, 128), (34, 30, 28)),
    "logo-variant-6": ((72, 74, 78), (247, 245, 241)),
}
# Soft left draw-nudge so "mo" reads optically centered (mass sits a hair right).
OPTICAL_DRAW_NUDGE_X_FRAC = -0.012
# Superellipse exponent; ~5 approximates continuous macOS corners.
# Radius fallback for rounded-rect: ~22% of side.
SUPERELLIPSE_N = 5.0


def squircle_mask(size: int, n: float = SUPERELLIPSE_N) -> Image.Image:
    """Alpha mask: 255 inside the squircle, 0 outside (with soft AA on the edge)."""
    half = (size - 1) / 2.0
    # Slight inset so the silhouette doesn't clip at the bitmap edge.
    radius = half * 0.998
    pixels = bytearray(size * size)
    aa_band = 1.25  # pixels of antialias falloff

    for y in range(size):
        dy = (y - half) / radius
        row = y * size
        for x in range(size):
            dx = (x - half) / radius
            # Lamé / superellipse distance: (|x|^n + |y|^n)^(1/n)
            dist = (abs(dx) ** n + abs(dy) ** n) ** (1.0 / n)
            if dist <= 1.0 - aa_band / radius:
                a = 255
            elif dist >= 1.0 + aa_band / radius:
                a = 0
            else:
                # Linear AA across the rim
                t = (1.0 + aa_band / radius - dist) / (2.0 * aa_band / radius)
                a = max(0, min(255, int(round(255 * t))))
            pixels[row + x] = a

    return Image.frombytes("L", (size, size), bytes(pixels))


def ink_coverage(mark: Image.Image) -> tuple[Image.Image, tuple[int, int, int, int]]:
    """Alpha of the wordmark. Near-black field becomes clear."""
    rgba = mark.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    coverage = Image.new("L", (width, height), 0)
    out = coverage.load()
    peak = 190.0
    min_x, min_y, max_x, max_y = width, height, 0, 0
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha < 8:
                continue
            luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            if luma < 12:
                continue
            value = max(0, min(255, int(round(luma / peak * 255))))
            out[x, y] = value
            if value > 24:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x <= min_x or max_y <= min_y:
        raise SystemExit("mark has no ink")
    pad_y = max(2, int((max_y - min_y) * 0.06))
    pad_x = max(2, int((max_x - min_x) * 0.03))
    box = (
        max(0, min_x - pad_x),
        max(0, min_y - pad_y),
        min(width, max_x + 1 + pad_x),
        min(height, max_y + 1 + pad_y),
    )
    return coverage, box


def colorize(coverage: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    red, green, blue = rgb
    out = Image.new("RGBA", coverage.size)
    src = coverage.load()
    dst = out.load()
    width, height = coverage.size
    for y in range(height):
        for x in range(width):
            alpha = src[x, y]
            if alpha:
                dst[x, y] = (red, green, blue, alpha)
    return out


def mass_center_x(coverage: Image.Image) -> float:
    """Ink mass center along x (alpha-weighted)."""
    src = coverage.load()
    width, height = coverage.size
    total = 0.0
    weighted = 0.0
    for y in range(height):
        for x in range(width):
            alpha = src[x, y]
            if alpha < 8:
                continue
            total += alpha
            weighted += alpha * x
    if total <= 0:
        return width / 2.0
    return weighted / total


def balance_mass(coverage: Image.Image) -> Image.Image:
    """Pad so ink mass sits on the geometric midline (no optical nudge)."""
    width, height = coverage.size
    mass_x = mass_center_x(coverage)
    ratio = 0.5
    current = mass_x / max(width, 1)
    if abs(current - ratio) < 0.001:
        return coverage
    if current > ratio:
        right = max(0, int(round(mass_x / ratio - width)))
        left = 0
    else:
        left = max(0, int(round((ratio * width - mass_x) / (1.0 - ratio))))
        right = 0
    if left == 0 and right == 0:
        return coverage
    out = Image.new("L", (width + left + right, height), 0)
    out.paste(coverage, (left, 0))
    return out


def rebuild_marks(source: Path) -> None:
    """Crop the wordmark tight and recolor each theme so the letters read larger."""
    image = Image.open(source)
    coverage, box = ink_coverage(image)
    cropped = coverage.crop(box)
    # A later run already has a tight wordmark. Recolor it; don't scale again.
    coverage_fill = (cropped.width * cropped.height) / max(1, image.width * image.height)
    if coverage_fill < 0.45:
        target_w = max(cropped.width * 2, 1400)
        target_h = max(1, int(round(cropped.height * (target_w / cropped.width))))
        cropped = cropped.resize((target_w, target_h), Image.Resampling.LANCZOS)
    cropped = balance_mass(cropped)
    for stem, (mark_rgb, _canvas) in THEME_COLORS.items():
        path = ICON_DIR / f"{stem}.png"
        colorize(cropped, mark_rgb).save(path, format="PNG")
        print(f"wrote {path} ({cropped.width}x{cropped.height})")


def compose_icon(
    mark_path: Path,
    fill: tuple[int, int, int],
    size: int = SIZE,
) -> Image.Image:
    mask = squircle_mask(size)
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    plate = Image.new("RGBA", (size, size), (*fill, 255))
    base = Image.composite(plate, base, mask)

    mark = Image.open(mark_path).convert("RGBA")
    max_w = size * MARK_WIDTH_FRAC
    max_h = size * MARK_HEIGHT_FRAC
    scale = min(max_w / mark.width, max_h / mark.height)
    mark_w = max(1, int(round(mark.width * scale)))
    mark_h = max(1, int(round(mark.height * scale)))
    mark = mark.resize((mark_w, mark_h), Image.Resampling.LANCZOS)
    ox = (size - mark_w) // 2 + int(round(size * OPTICAL_DRAW_NUDGE_X_FRAC))
    oy = (size - mark_h) // 2
    base.alpha_composite(mark, (ox, oy))

    # Re-apply mask so mark cannot spill outside the squircle.
    r, g, b, a = base.split()
    a = Image.composite(a, Image.new("L", (size, size), 0), mask)
    return Image.merge("RGBA", (r, g, b, a))


ICONSET_SIZES = [
    (16, "icon_16x16.png"),
    (32, "diana.k@example.org"),
    (32, "icon_32x32.png"),
    (64, "ivan.p@example.net"),
    (128, "icon_128x128.png"),
    (256, "peter.m@example.com"),
    (256, "icon_256x256.png"),
    (512, "wendy.h@example.net"),
    (512, "icon_512x512.png"),
    (1024, "walt.e@example.net"),
]


def write_icns(master: Image.Image, icns_path: Path) -> None:
    # iconutil must run with a real .iconset on disk (sandbox often rejects it).
    iconset = icns_path.parent / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    try:
        for px, name in ICONSET_SIZES:
            master.resize((px, px), Image.Resampling.LANCZOS).save(
                iconset / name, format="PNG"
            )
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)],
            check=True,
        )
    finally:
        shutil.rmtree(iconset, ignore_errors=True)


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    default_mark = ICON_DIR / "logo-variant-2.png"
    if not default_mark.is_file():
        raise SystemExit(f"missing mark: {default_mark}")
    rebuild_marks(default_mark)

    master = compose_icon(default_mark, THEME_COLORS["logo-variant-2"][1])
    master_path = ICON_DIR / "AppIcon-master.png"
    master.save(master_path, format="PNG")
    print(f"wrote {master_path}")

    icns_path = ICON_DIR / "AppIcon.icns"
    write_icns(master, icns_path)
    print(f"wrote {icns_path}")

    # Themed previews: same squircle, each theme's own canvas.
    for stem, (_mark, canvas) in THEME_COLORS.items():
        if stem == "logo-variant-2":
            continue
        variant = ICON_DIR / f"{stem}.png"
        preview = compose_icon(variant, canvas)
        out = ICON_DIR / f"AppIcon-preview-{stem}.png"
        preview.save(out, format="PNG")
        print(f"wrote {out}")

    # Corner / center alpha sanity check
    px = master.load()
    corner = px[0, 0][3]
    center = px[SIZE // 2, SIZE // 2][3]
    print(f"corner(0,0) alpha={corner}  center alpha={center}")
    if corner != 0:
        raise SystemExit("expected transparent corner")
    if center < 250:
        raise SystemExit("expected opaque squircle center")


if __name__ == "__main__":
    main()
