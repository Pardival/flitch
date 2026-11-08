"""Flitch, the river otter: pixel-art generator (concept v1).

Every sprite is drawn in code (32x32 px frames), so the look stays consistent
and anyone can tweak the palette or a pose.

Otter reading, from real river-otter photos:
- wide, FLAT head that flows straight into a thick neck (no "bear" head-on-ball);
- small eyes set HIGH on the head, tiny round ears on the top corners;
- a big, wide dark nose over two puffy cream WHISKER PADS, long pale whiskers;
- a pale cream chin / throat bib running down to the belly;
- a thick tail that rests on the ground.

    python art/otter.py      # writes art/preview/otter_concept.png and art/preview/poses/*.png
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W = H = 32
CX = 16.0  # horizontal center (pixel centers are x + 0.5)

# ---------------------------------------------------------------- palette
P = {
    "out":    (38, 22, 14),
    "fur":    (122, 80, 52),
    "furD":   (92, 58, 37),
    "furL":   (150, 104, 70),
    "cream":  (232, 214, 184),
    "creamD": (204, 182, 148),
    "pad":    (246, 236, 216),
    "padD":   (214, 196, 168),
    "nose":   (30, 18, 14),
    "noseL":  (96, 78, 72),
    "eye":    (20, 12, 8),
    "white":  (255, 255, 255),
    "mouth":  (88, 40, 30),
    "tongue": (222, 112, 110),
    "blush":  (226, 150, 128),
    "whisk":  (250, 246, 236),
    "band":   (48, 52, 70),
    "bandL":  (92, 98, 126),
    "cup":    (47, 191, 174),
    "cupD":   (28, 138, 126),
    "cupL":   (140, 232, 218),
    "glow":   (190, 255, 245),
    "stone":  (150, 160, 172),
    "stoneD": (104, 112, 126),
    "stoneL": (204, 212, 220),
    "shell":  (246, 196, 180),
    "shellD": (214, 146, 132),
    "zz":     (120, 160, 230),
    "note":   (255, 200, 80),
}


class Canvas:
    def __init__(self, w: int = W, h: int = H):
        self.w, self.h = w, h
        self.px: dict[tuple[int, int], tuple[int, int, int]] = {}

    def set(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = P[c] if isinstance(c, str) else c

    @staticmethod
    def inside(x, y, cx, cy, rx, ry):
        return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0

    def shape(self, ellipses, color, outline=True, shade=None, light=None):
        """Union of ellipses drawn as ONE part: one 1 px outline around the union,
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
                self.set(x, y, "out")
            elif shade and not ins(x, y, -1.3, -1.3):
                self.set(x, y, shade)
            elif light and (x - bx0) < bw * 0.40 and (y - by0) < bh * 0.30 and ins(x, y, 1.5, 1.5):
                self.set(x, y, light)
            else:
                self.set(x, y, color)
        return S

    def blob(self, cx, cy, rx, ry, color, **kw):
        return self.shape([(cx, cy, rx, ry)], color, **kw)

    def capsule(self, a, b, r, color, **kw):
        n = max(2, int(math.dist(a, b) / 0.7))
        es = [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, r, r) for i in range(n + 1)]
        return self.shape(es, color, **kw)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def flipped_v(self) -> "Canvas":
        c = Canvas(self.w, self.h)
        for (x, y), col in self.px.items():
            c.set(x, self.h - 1 - y, col)
        return c

    def image(self) -> Image.Image:
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            im.putpixel((x, y), (*c, 255))
        return im


def mx(x: int) -> int:
    """Mirror a column around the center (31 - x)."""
    return 31 - x


# ---------------------------------------------------------------- parts
HEAD = (16.0, 10.6, 9.2, 6.3)      # wide, flat
BODY = (16.0, 22.6, 7.0, 8.0)      # sleek, flows from the neck
NECK = (16.0, 15.8, 7.4, 3.6)


def draw_tail(c: Canvas, dy=0, curl=0.0):
    """Thick tail resting on the ground, to the right."""
    es = []
    for i in range(16):
        t = i / 15
        x = 20.5 + 9.0 * t
        y = 29.0 - 1.2 * t - curl * 6 * t * t + dy
        r = 2.8 - 1.7 * t
        es.append((x, y, r, r * 0.85))
    c.shape(es, "fur", shade="furD")


def draw_silhouette(c: Canvas, dy=0):
    """Head + neck + body as ONE shape: the otter's seamless, sleek outline."""
    hx, hy, hrx, hry = HEAD
    bx, by, brx, bry = BODY
    nx, ny, nrx, nry = NECK
    c.shape([(hx, hy + dy, hrx, hry), (nx, ny + dy, nrx, nry), (bx, by + dy, brx, bry)],
            "fur", shade="furD", light="furL")
    # cream chin, throat and belly (no outline)
    c.shape([(16, 14.6 + dy, 4.6, 2.4), (16, 18.0 + dy, 4.0, 3.0), (16, 24.0 + dy, 4.6, 5.4)],
            "cream", outline=False, shade="creamD")
    # webbed feet
    for fx in (11.5, 20.5):
        c.blob(fx, 30.4, 2.5, 1.3, "furD")


def draw_ears(c: Canvas, dy=0):
    for ex in (8.6, 23.4):
        c.blob(ex, 5.6 + dy, 1.7, 1.6, "fur", shade="furD")


def draw_face(c: Canvas, dy=0, eyes="open", mouth="smile", blush=True):
    oy = int(round(dy))
    # whisker pads: two puffy cream bumps under the nose
    c.blob(13.7, 12.9 + dy, 2.7, 2.0, "pad", outline=False, shade="padD")
    c.blob(18.3, 12.9 + dy, 2.7, 2.0, "pad", outline=False, shade="padD")
    for x, y in ((12, 13), (13, 12), (14, 13), (17, 13), (18, 12), (19, 13)):
        c.set(x, y + oy, "padD")   # whisker dots
    # big wide nose
    c.rect(14, 10 + oy, 17, 11 + oy, "nose")
    c.set(13, 11 + oy, "nose"); c.set(18, 11 + oy, "nose")
    c.set(15, 10 + oy, "noseL")
    draw_mouth(c, mouth, oy)
    draw_eyes(c, eyes, oy)
    if blush:
        for bx in (9, 10, 21, 22):
            c.set(bx, 11 + oy, "blush")
    # long pale whiskers, poking out of the silhouette
    for (x, y) in ((9, 14), (8, 14), (7, 14), (6, 13), (5, 13), (9, 15), (8, 16), (7, 16), (6, 17)):
        c.set(x, y + oy, "whisk"); c.set(mx(x), y + oy, "whisk")


def draw_eyes(c: Canvas, style: str, oy: int):
    y = 8 + oy
    for x in (11, 19):
        if style == "open":
            c.rect(x, y, x + 1, y + 1, "eye"); c.set(x, y, "white")
        elif style == "sparkle":
            c.rect(x, y - 1, x + 1, y + 1, "eye"); c.set(x, y - 1, "white"); c.set(x + 1, y + 1, "white")
        elif style == "up":
            c.rect(x, y - 1, x + 1, y, "eye"); c.set(x + 1, y - 1, "white")
        elif style == "closed":
            c.set(x - 1, y, "eye"); c.set(x, y + 1, "eye"); c.set(x + 1, y + 1, "eye"); c.set(x + 2, y, "eye")
        elif style == "happy":
            c.set(x - 1, y + 1, "eye"); c.set(x, y, "eye"); c.set(x + 1, y, "eye"); c.set(x + 2, y + 1, "eye")
        elif style == "blink":
            c.rect(x - 1, y + 1, x + 2, y + 1, "eye")


def draw_mouth(c: Canvas, style: str, oy: int):
    y = 12 + oy
    if style == "smile":            # otter "w" between the pads
        c.set(15, y, "mouth"); c.set(16, y, "mouth")
        c.set(14, y + 2, "mouth"); c.set(15, y + 3, "mouth"); c.set(16, y + 3, "mouth"); c.set(17, y + 2, "mouth")
    elif style == "calm":
        c.set(15, y, "mouth"); c.set(16, y, "mouth")
        c.rect(14, y + 3, 17, y + 3, "mouth")
    elif style == "open":
        c.set(15, y, "mouth"); c.set(16, y, "mouth")
        c.rect(14, y + 2, 17, y + 3, "mouth"); c.set(15, y + 3, "tongue"); c.set(16, y + 3, "tongue")
    elif style == "big":
        c.set(15, y, "mouth"); c.set(16, y, "mouth")
        c.rect(13, y + 2, 18, y + 2, "mouth"); c.rect(14, y + 3, 17, y + 4, "mouth")
        c.set(15, y + 4, "tongue"); c.set(16, y + 4, "tongue")
    elif style == "o":
        c.set(15, y, "mouth"); c.set(16, y, "mouth")
        c.rect(15, y + 2, 16, y + 3, "mouth")
    elif style == "sleep":
        c.set(15, y, "mouth"); c.set(16, y, "mouth"); c.set(15, y + 3, "mouth"); c.set(16, y + 3, "mouth")


def draw_phones(c: Canvas, dy=0, glow=False):
    hx, hy = 16.0, 10.2 + dy
    for a in range(196, 345, 3):
        t = math.radians(a)
        x = hx + 10.2 * math.cos(t)
        y = hy + 7.5 * math.sin(t)
        c.set(x, y, "band"); c.set(x, y - 1, "out")
    c.set(15, hy - 8.3, "bandL"); c.set(16, hy - 8.3, "bandL")
    for side in (-1, 1):
        cx = hx + side * 9.3
        c.blob(cx, hy + 0.2, 2.3, 3.2, "cup", shade="cupD", light="cupL")
        if glow:
            gx = int(cx) + (0 if side < 0 else -1)
            c.set(gx, int(hy) - 1, "glow"); c.set(gx, int(hy), "glow")


def draw_arms(c: Canvas, style="hold", dy=0):
    k = dict(shade="furD")
    L = lambda a, b, r=1.4: c.capsule((a[0], a[1] + dy), (b[0], b[1] + dy), r, "fur", **k)
    if style == "hold":       # paws held together under the chin (classic otter)
        c.blob(14.0, 20.2 + dy, 1.8, 1.3, "furD", outline=False, shade="out"); c.blob(18.0, 20.2 + dy, 1.8, 1.3, "furD", outline=False, shade="out")
    elif style == "cup":      # one paw pressing the headphone (listening)
        L((10.4, 18.0), (6.6, 14.0)); c.blob(18.0, 20.2 + dy, 1.8, 1.3, "furD", outline=False, shade="out")
    elif style == "up":
        L((10.6, 18.0), (5.8, 13.0), 1.5); L((21.4, 18.0), (26.2, 13.0), 1.5)
    elif style == "wave":
        c.blob(14.0, 20.2 + dy, 1.8, 1.3, "furD", outline=False, shade="out"); L((21.4, 18.0), (26.4, 13.2), 1.5)
        c.set(28, 11 + dy, "out"); c.set(29, 14 + dy, "out")
    elif style == "tool":     # shell on the tummy, pebble raised: about to tap
        c.blob(16.0, 24.4 + dy, 3.6, 2.4, "shell", shade="shellD")
        for x in (14, 16, 18):
            c.set(x, 23 + dy, "shellD")
        c.blob(23.8, 13.6 + dy, 2.6, 2.2, "stone", shade="stoneD", light="stoneL")
        L((11.6, 19.6), (13.4, 23.4)); L((21.0, 19.0), (23.4, 15.6))
    elif style == "edge":     # both paws gripping the screen edge (peek)
        c.blob(9.0, 22.4 + dy, 2.3, 1.7, "fur", shade="furD")
        c.blob(23.0, 22.4 + dy, 2.3, 1.7, "fur", shade="furD")


def draw_zz(c: Canvas, x=24, y=2):
    for dx, dy in ((0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)):
        c.set(x + dx, y + dy, "zz")
    for dx, dy in ((4, -2), (5, -2), (5, -1), (4, 0), (5, 0)):
        c.set(x + dx, y + dy, "zz")


def draw_note(c: Canvas, x, y):
    c.rect(x + 2, y, x + 2, y + 3, "note"); c.set(x + 3, y, "note")
    c.rect(x, y + 3, x + 1, y + 4, "note")


def otter(eyes="open", mouth="smile", arms="hold", glow=False, dy=0, tail=True, curl=0.0, blush=True):
    c = Canvas()
    if tail:
        draw_tail(c, curl=curl)
    draw_ears(c, dy)
    draw_silhouette(c, dy)
    draw_face(c, dy, eyes, mouth, blush)
    draw_phones(c, dy, glow)
    draw_arms(c, arms, dy)
    return c


# ---------------------------------------------------------------- poses
def peek(eyes="sparkle", mouth="smile", glow=True) -> Canvas:
    """Half body rising from the bottom edge, paws on the edge.
    Bottom corners use it as is; TOP corners flip it: she hangs head-down from the top of the screen."""
    full = Canvas()
    draw_ears(full); draw_silhouette(full); draw_face(full, 0, eyes, mouth); draw_phones(full, 0, glow)
    c = Canvas()
    for (x, y), col in full.px.items():
        if y <= 21:                       # keep head + shoulders
            c.set(x, y + 9, col)
    draw_arms(c, "edge", dy=8)
    return c


def pose(name: str) -> Canvas:
    if name == "idle":
        return otter()
    if name == "listen":
        return otter(eyes="sparkle", mouth="o", arms="cup", glow=True)
    if name == "think":
        return otter(eyes="up", mouth="calm", arms="tool")
    if name == "talk":
        return otter(eyes="open", mouth="open")
    if name == "happy":
        c = otter(eyes="happy", mouth="big", arms="up", dy=-1, curl=0.6)
        draw_note(c, 26, 1)
        return c
    if name == "wave":
        return otter(eyes="happy", mouth="smile", arms="wave")
    if name == "sleep":
        c = otter(eyes="closed", mouth="sleep", dy=1)
        draw_zz(c)
        return c
    if name == "peek_bottom":
        return peek()
    if name == "peek_top":
        return peek().flipped_v()
    raise ValueError(name)


POSES = ["idle", "listen", "think", "talk", "happy", "wave", "sleep", "peek_bottom", "peek_top"]
LABELS = {
    "idle": "idle · holds paws", "listen": "listening · headphones glow", "think": "thinking · shell + pebble",
    "talk": "talking", "happy": "happy", "wave": "hello!", "sleep": "sleeping",
    "peek_bottom": "peek · bottom corners", "peek_top": "peek · top corners (head down)",
}


def sheet(out: Path, scale=8):
    try:
        font = ImageFont.load_default(size=14)
    except TypeError:
        font = ImageFont.load_default()
    cols = 5
    cell_w, cell_h = W * scale + 24, H * scale + 44
    rows = math.ceil(len(POSES) / cols)
    im = Image.new("RGBA", (cols * cell_w + 24, rows * cell_h + 150), (246, 244, 240, 255))
    d = ImageDraw.Draw(im)
    d.text((24, 16), "Flitch · river otter · concept v1 (32x32 px, shown x8)", fill=(40, 30, 25), font=font)
    for i, name in enumerate(POSES):
        r, col = divmod(i, cols)
        x0, y0 = 24 + col * cell_w, 50 + r * cell_h
        d.rectangle([x0 - 4, y0 - 4, x0 + W * scale + 4, y0 + H * scale + 4], fill=(228, 226, 222, 255))
        if name.startswith("peek"):
            ey = y0 + (H * scale if name == "peek_bottom" else 0)
            d.rectangle([x0 - 4, ey - 2, x0 + W * scale + 4, ey + 2], fill=(60, 60, 70, 255))
        spr = pose(name).image().resize((W * scale, H * scale), Image.NEAREST)
        im.alpha_composite(spr, (x0, y0))
        d.text((x0, y0 + H * scale + 10), LABELS[name], fill=(40, 30, 25), font=font)
    yb = 50 + rows * cell_h
    d.text((24, yb), "actual size x1 / x2:", fill=(40, 30, 25), font=font)
    for i, name in enumerate(POSES):
        im.alpha_composite(pose(name).image(), (200 + i * 40, yb))
        im.alpha_composite(pose(name).image().resize((64, 64), Image.NEAREST), (24 + i * 76, yb + 40))
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    poses_dir = root / "preview" / "poses"
    poses_dir.mkdir(parents=True, exist_ok=True)
    for old in poses_dir.glob("*.png"):
        old.unlink()
    for n in POSES:
        pose(n).image().save(poses_dir / f"{n}.png")
    sheet(root / "preview" / "otter_concept.png")
    print("ok", file=sys.stderr)
