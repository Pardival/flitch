"""Shared pixel-art tools for the character scripts (red panda, owl, axolotl…).

A character script defines a palette, draws its frames on `Canvas`, and calls `export_pack`
with every animation the app needs (see ANIMATIONS). The otter (otter.py) predates this module.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W = H = 32

# Every animation a pack must provide, with its frame count (the app reads pack.json).
ANIMATIONS = {
    "idle": 6, "listen": 4, "think": 8, "talk": 4, "happy": 6, "wave": 4, "sleep": 4,
    "walk": 6, "look": 6, "juggle": 8, "groom": 6, "dance": 8, "sleepBack": 4, "wake": 6,
}

# Colours every character shares: outline, eyes, the teal headphones (Flitch's signature), effects.
COMMON = {
    "out": (38, 22, 14),
    "eye": (20, 12, 8),
    "white": (255, 255, 255),
    "band": (48, 52, 70),
    "bandL": (92, 98, 126),
    "cup": (47, 191, 174),
    "cupD": (28, 138, 126),
    "cupL": (140, 232, 218),
    "glow": (190, 255, 245),
    "zz": (120, 160, 230),
    "note": (255, 200, 80),
    "tongue": (222, 112, 110),
    "blush": (232, 140, 130),
}


class Canvas:
    def __init__(self, palette: dict, w: int = W, h: int = H):
        self.palette = {**COMMON, **palette}
        self.w, self.h = w, h
        self.px: dict[tuple[int, int], tuple[int, int, int]] = {}

    def new(self) -> "Canvas":
        return Canvas(self.palette, self.w, self.h)

    def set(self, x, y, c):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = self.palette[c] if isinstance(c, str) else c

    def get(self, x, y):
        return self.px.get((x, y))

    @staticmethod
    def inside(x, y, cx, cy, rx, ry):
        return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0

    def shape(self, ellipses, color, outline=True, shade=None, light=None, outline_color="out"):
        """Union of ellipses drawn as ONE part: a 1 px outline around the union,
        lower-right shade, upper-left light."""
        def ins(x, y, dx=0.0, dy=0.0):
            return any(self.inside(x + dx, y + dy, cx, cy, rx, ry) for cx, cy, rx, ry in ellipses)
        x0 = int(min(cx - rx for cx, cy, rx, ry in ellipses)) - 2
        x1 = int(max(cx + rx for cx, cy, rx, ry in ellipses)) + 2
        y0 = int(min(cy - ry for cx, cy, rx, ry in ellipses)) - 2
        y1 = int(max(cy + ry for cx, cy, rx, ry in ellipses)) + 2
        S = {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1) if ins(x, y)}
        if not S:
            return S
        bx0, by0 = min(x for x, _ in S), min(y for _, y in S)
        bw = max(x for x, _ in S) - bx0 + 1
        bh = max(y for _, y in S) - by0 + 1
        for (x, y) in S:
            edge = any((x + dx, y + dy) not in S for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if outline and edge:
                self.set(x, y, outline_color)
            elif shade and not ins(x, y, -1.3, -1.3):
                self.set(x, y, shade)
            elif light and (x - bx0) < bw * 0.40 and (y - by0) < bh * 0.30 and ins(x, y, 1.5, 1.5):
                self.set(x, y, light)
            else:
                self.set(x, y, color)
        return S

    def recolor(self, ellipses, color):
        """Repaints the pixels inside `ellipses` that are already drawn, keeping the outline."""
        out = self.palette["out"]
        for (x, y), col in list(self.px.items()):
            if col != out and any(self.inside(x, y, cx, cy, rx, ry) for cx, cy, rx, ry in ellipses):
                self.set(x, y, color)

    def blob(self, cx, cy, rx, ry, color, **kw):
        return self.shape([(cx, cy, rx, ry)], color, **kw)

    def capsule(self, a, b, r, color, **kw):
        n = max(2, int(math.dist(a, b) / 0.7))
        es = [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, r, r) for i in range(n + 1)]
        return self.shape(es, color, **kw)

    def poly(self, pts, color, **kw):
        """Filled triangle/quad made of small ellipses along a scanline fill (keeps one outline)."""
        ys = [p[1] for p in pts]
        es = []
        for y in [min(ys) + i * 0.5 for i in range(int((max(ys) - min(ys)) * 2) + 1)]:
            xs = []
            for (ax, ay), (bx, by) in zip(pts, pts[1:] + pts[:1]):
                if (ay <= y <= by) or (by <= y <= ay):
                    if ay == by:
                        xs += [ax, bx]
                    else:
                        xs.append(ax + (bx - ax) * (y - ay) / (by - ay))
            if len(xs) >= 2:
                lo, hi = min(xs), max(xs)
                es.append(((lo + hi) / 2, y, max(0.6, (hi - lo) / 2), 0.6))
        return self.shape(es, color, **kw)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, c)

    def line(self, a, b, c):
        n = max(1, int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2))
        for i in range(n + 1):
            self.set(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, c)

    def paste(self, other: "Canvas", dx=0, dy=0):
        for (x, y), col in other.px.items():
            self.set(x + dx, y + dy, col)
        return self

    def mirrored(self) -> "Canvas":
        c = self.new()
        for (x, y), col in self.px.items():
            c.set(self.w - 1 - x, y, col)
        return c

    def image(self) -> Image.Image:
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            im.putpixel((x, y), (*c, 255))
        return im


# ---------------------------------------------------------------- shared props
def draw_zz(c: Canvas, x=24, y=2):
    for dx, dy in ((0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)):
        c.set(x + dx, y + dy, "zz")
    for dx, dy in ((4, -2), (5, -2), (5, -1), (4, 0), (5, 0)):
        c.set(x + dx, y + dy, "zz")


def draw_note(c: Canvas, x, y):
    c.rect(x + 2, y, x + 2, y + 3, "note")
    c.set(x + 3, y, "note")
    c.rect(x, y + 3, x + 1, y + 4, "note")


def draw_phones(c: Canvas, cx=16.0, cy=10.2, rx=10.2, ry=7.5, cup_rx=2.3, cup_ry=3.2, cup_dx=9.3, glow=False):
    """Flitch's teal headphones: a band over the head and a cup on each side."""
    for a in range(196, 345, 3):
        t = math.radians(a)
        x, y = cx + rx * math.cos(t), cy + ry * math.sin(t)
        c.set(x, y, "band")
        c.set(x, y - 1, "out")
    c.set(cx - 1, cy - ry - 0.8, "bandL")
    c.set(cx, cy - ry - 0.8, "bandL")
    for side in (-1, 1):
        x = cx + side * cup_dx
        c.blob(x, cy + 0.2, cup_rx, cup_ry, "cup", shade="cupD", light="cupL")
        if glow:
            gx = int(x) + (0 if side < 0 else -1)
            c.set(gx, int(cy) - 1, "glow")
            c.set(gx, int(cy), "glow")


def draw_side_phones(c: Canvas, cx, cy, r=4.5, cup=(0.0, 0.0)):
    """Side view: the band over the head and one cup over the ear."""
    for deg in range(195, 350, 4):
        t = math.radians(deg)
        x, y = cx + r * math.cos(t), cy + r * math.sin(t)
        c.set(x, y, "band")
        c.set(x, y - 1, "out")
    c.blob(cx - 1.0 + cup[0], cy + cup[1], 1.8, 2.3, "cup", shade="cupD", light="cupL")


# ---------------------------------------------------------------- export
def export_pack(frames: dict[str, list[Canvas]], pack_dir: Path, preview_dir: Path, title: str):
    missing = set(ANIMATIONS) - set(frames)
    assert not missing, f"missing animations: {missing}"
    for name, n in ANIMATIONS.items():
        assert len(frames[name]) == n, f"{name}: {len(frames[name])} frames, expected {n}"
    sprites = pack_dir / "sprites"
    sprites.mkdir(parents=True, exist_ok=True)
    for old in sprites.glob("*.png"):
        old.unlink()
    preview_dir.mkdir(parents=True, exist_ok=True)
    for name, fs in frames.items():
        strip = Image.new("RGBA", (W * len(fs), H), (0, 0, 0, 0))
        for i, f in enumerate(fs):
            strip.alpha_composite(f.image(), (i * W, 0))
        strip.save(sprites / f"{name}.png")
    contact_sheet(frames, preview_dir / "sheet.png", title)


def contact_sheet(frames: dict[str, list[Canvas]], out: Path, title: str, scale=5):
    """Every animation on one image, to review the art at a glance."""
    try:
        font = ImageFont.load_default(size=13)
    except TypeError:
        font = ImageFont.load_default()
    cell = W * scale + 6
    cols = max(len(f) for f in frames.values())
    im = Image.new("RGBA", (110 + cols * cell, 40 + len(frames) * (cell + 4)), (246, 244, 240, 255))
    d = ImageDraw.Draw(im)
    d.text((10, 10), title, fill=(40, 30, 25), font=font)
    for r, (name, fs) in enumerate(frames.items()):
        y = 36 + r * (cell + 4)
        d.text((10, y + cell // 2 - 6), name, fill=(40, 30, 25), font=font)
        for i, f in enumerate(fs):
            x = 110 + i * cell
            d.rectangle([x, y, x + W * scale, y + H * scale], fill=(228, 226, 222, 255))
            im.alpha_composite(f.image().resize((W * scale, H * scale), Image.NEAREST), (x, y))
    im.save(out)
