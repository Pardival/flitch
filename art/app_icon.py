"""Flitch's app icon: Hulo the little owl, in pixel art, on a soft pink-and-aqua background with bubbles
(the same colours as the download page).

    ../art/.venv/bin/python art/app_icon.py
    → App/AppIcon.icon (Icon Composer format: a background layer + an owl layer) and art/preview/app_icon.png

macOS 26 only shows Icon Composer icons edge to edge; older-style icons get a grey frame.

The sprite is the real 32x32 owl from art/owl.py, scaled up by a whole number so its pixels stay crisp.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

import owl

S = 1024
PLATE = 824                # macOS icon grid: the rounded square is 824 px in a 1024 canvas
MARGIN = (S - PLATE) // 2
RADIUS = 185               # corner radius of the rounded square at 1024

TOP = (255, 206, 220)      # soft pink
MIDDLE = (255, 238, 238)   # a light stop, so pink and aqua don't mix into grey
BOTTOM = (168, 228, 236)   # water aqua
PX = 16                    # size of one "pixel" of the bubbles


def squircle_mask(n=5.0, oversample=4) -> Image.Image:
    """Apple's icon shape: a superellipse (|x|^n + |y|^n = 1) on the 824 px grid, antialiased."""
    big = S * oversample
    r = PLATE * oversample / 2
    c = big / 2
    m = Image.new("L", (big, big), 0)
    px = m.load()
    for y in range(big):
        dy = abs((y + 0.5 - c) / r)
        if dy > 1:
            continue
        half = r * (1 - dy ** n) ** (1 / n)
        for x in range(int(c - half), int(c + half) + 1):
            px[x, y] = 255
    return m.resize((S, S), Image.LANCZOS)


def plate() -> Image.Image:
    """The rounded square with the pink-to-aqua gradient and pixel bubbles."""
    mask = squircle_mask()
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(plate_content(), (0, 0), mask)
    return out


def pixel_bubble(d: ImageDraw.ImageDraw, cx: int, cy: int, r: int):
    """A bubble made of big square pixels: a white ring with a shine at the top left."""
    for gy in range(-r - 1, r + 2):
        for gx in range(-r - 1, r + 2):
            dist = (gx * gx + gy * gy) ** 0.5
            x, y = MARGIN + (cx + gx) * PX, MARGIN + (cy + gy) * PX
            if r - 0.5 <= dist < r + 0.5:
                d.rectangle([x, y, x + PX - 1, y + PX - 1], fill=(255, 255, 255, 215))
    sx, sy = MARGIN + (cx - r // 2) * PX, MARGIN + (cy - r // 2) * PX
    d.rectangle([sx, sy, sx + PX - 1, sy + PX - 1], fill=(255, 255, 255, 255))


def plate_content() -> Image.Image:
    """Full bleed: pink-to-aqua gradient with pixel bubbles."""
    grad = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        a, b, u = (TOP, MIDDLE, t * 2) if t < 0.5 else (MIDDLE, BOTTOM, t * 2 - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(p + (q - p) * u) for p, q in zip(a, b)) + (255,))
    bubbles = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bubbles)
    for cx, cy, r in ((6, 8, 3), (45, 9, 2), (43, 30, 3), (4, 33, 2), (10, 3, 1), (40, 2, 1)):
        pixel_bubble(bd, cx, cy, r)
    return Image.alpha_composite(grad, bubbles)


def icon() -> Image.Image:
    base = plate()
    sprite = owl.owl(eyes="sparkle", mouth="closed", wings="hold", glow=True).image()
    scale = 20                                     # 32 px → 640 px
    big = sprite.resize((32 * scale, 32 * scale), Image.NEAREST)
    x = (S - big.width) // 2
    y = MARGIN + PLATE - big.height - 34           # feet near the bottom of the plate
    # a small shadow under the feet
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([x + 170, y + big.height - 40, x + big.width - 170, y + big.height + 6],
                               fill=(10, 10, 30, 110))
    base = Image.alpha_composite(base, sh.filter(ImageFilter.GaussianBlur(10)))
    base.alpha_composite(big, (x, y))
    return base


def sky_layer() -> Image.Image:
    """Full-bleed background with the pixel bubbles (macOS cuts the rounded shape)."""
    return plate_content()


def owl_layer() -> Image.Image:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sprite = owl.owl(eyes="sparkle", mouth="closed", wings="hold", glow=True).image()
    big = sprite.resize((32 * 22, 32 * 22), Image.NEAREST)   # 704 px, whole-number scale
    layer.alpha_composite(big, ((S - big.width) // 2, S - big.height - 120))
    return layer


def write_icon_composer(folder: Path):
    """An Icon Composer `.icon` bundle: icon.json + the layer images."""
    assets = folder / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    for old in assets.glob("*.png"):
        old.unlink()
    sky_layer().save(assets / "sky.png")
    owl_layer().save(assets / "owl.png")
    doc = {
        "fill": {"automatic-gradient": "extended-srgb:1.00000,0.83922,0.87843,1.00000"},
        "groups": [
            {"layers": [{"image-name": "owl.png", "name": "owl", "glass": False}],
             "shadow": {"kind": "neutral", "opacity": 0.5},
             "translucency": {"enabled": False, "value": 0.5}},
            {"layers": [{"image-name": "sky.png", "name": "sky", "glass": False}],
             "shadow": {"kind": "neutral", "opacity": 0.0},
             "translucency": {"enabled": False, "value": 0.0}},
        ],
        "supported-platforms": {"squares": "shared"},
    }
    (folder / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    img = icon()
    (root / "preview").mkdir(exist_ok=True)
    img.save(root / "preview" / "app_icon.png")
    write_icon_composer(root.parent / "App" / "AppIcon.icon")
    print("ok")
