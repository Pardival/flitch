"""Hulo, the little owl: pixel-art generator for the `owl` character pack.

Little owl reading, from photos (Wikimedia Commons, Athene noctua):
- a round, FLAT-topped head with no ear tufts, merging into a plump body;
- brown back and head speckled with WHITE spots;
- WHITE "eyebrows" forming a V above big YELLOW eyes with black pupils;
- a pale facial disc around the eyes, a small yellow-grey hooked beak;
- a cream belly with brown streaks, short tail, feathered legs and grey-yellow toes.

    ../art/.venv/bin/python art/owl.py   # writes Characters/owl/sprites and art/preview/owl/sheet.png
"""
from __future__ import annotations

import math
from pathlib import Path

from pixel import Canvas, draw_note, draw_phones, draw_side_phones, draw_zz, export_pack

PAL = {
    "fur": (138, 100, 70),
    "furD": (102, 72, 50),
    "furL": (168, 128, 92),
    "spot": (238, 226, 204),
    "disc": (198, 172, 136),
    "discD": (172, 146, 112),
    "brow": (246, 240, 228),
    "cream": (236, 222, 194),
    "creamD": (210, 192, 160),
    "streak": (150, 112, 78),
    "iris": (248, 204, 56),
    "irisD": (214, 160, 30),
    "beak": (212, 200, 140),
    "beakD": (160, 148, 96),
    "mouth": (92, 50, 34),
    "toe": (200, 188, 132),
    "book": (70, 110, 180),
    "bookD": (48, 78, 136),
    "page": (250, 248, 240),
    "pageD": (210, 206, 196),
    "acorn": (176, 118, 58),
    "acornD": (130, 84, 40),
    "cap": (118, 86, 52),
}

# little white spots scattered on the head and back (front view)
SPOTS = [(9, 5), (13, 4), (18, 4), (22, 5), (7, 8), (24, 8), (10, 3), (21, 3), (16, 3), (8, 19), (23, 19),
         (7, 23), (24, 23), (9, 26), (22, 26)]


def canvas() -> Canvas:
    return Canvas(PAL)


def mx(x):
    return 31 - x


# ---------------------------------------------------------------- front view
def draw_body(c: Canvas, dy=0, puff=0.0):
    c.shape([(16, 10.6 + dy, 9.6 + puff, 7.2), (16, 14.6 + dy, 9.8 + puff, 5.0),
             (16, 22.0 + dy, 8.6 + puff, 8.2)], "fur", shade="furD", light="furL")
    for x, y in SPOTS:
        if c.get(x, y + int(dy)) not in (None, c.palette["out"]):
            c.set(x, y + dy, "spot")
    # streaked cream belly
    c.shape([(16, 23.2 + dy, 5.8, 6.4)], "cream", outline=False, shade="creamD")
    for x, y in ((13, 20), (13, 21), (16, 22), (16, 23), (19, 20), (19, 21), (14, 25), (14, 26), (18, 25),
                 (18, 26), (16, 27)):
        c.set(x, y + dy, "streak")
    # feet: three grey-yellow toes each
    for fx in (12.5, 19.5):
        for t in (-1.2, 0, 1.2):
            c.set(fx + t, 30 + min(0, dy), "toe")
            c.set(fx + t, 31 + min(0, dy), "out")
        c.set(fx - 2.2, 30 + min(0, dy), "out")
        c.set(fx + 2.2, 30 + min(0, dy), "out")


def draw_face(c: Canvas, dy=0, eyes="open", mouth="closed", blush=True):
    oy = int(round(dy))
    for side in (-1, 1):
        c.blob(16 + side * 4.4, 11.4 + dy, 4.2, 3.8, "disc", outline=False, shade="discD")
    # white V eyebrows
    for i in range(6):
        c.set(10 + i, 7 + i * 0.45 + oy, "brow")
        c.set(mx(10 + i), 7 + i * 0.45 + oy, "brow")
    c.set(15, 10 + oy, "brow"); c.set(16, 10 + oy, "brow")
    draw_eyes(c, eyes, oy)
    draw_beak(c, mouth, oy)
    if blush:
        c.set(8, 14 + oy, "blush"); c.set(23, 14 + oy, "blush")


def draw_eyes(c: Canvas, style, oy):
    for cx in (11.4, 20.6):
        x0 = int(cx)
        if style in ("closed", "happy", "blink"):
            # the lid: a closed-eye curve on the facial disc
            y = 11 + oy
            if style == "closed":
                c.rect(x0 - 2, y, x0 + 1, y, "eye"); c.set(x0 - 2, y - 1, "furD"); c.set(x0 + 1, y - 1, "furD")
            elif style == "happy":
                c.set(x0 - 2, y + 1, "eye"); c.set(x0 - 1, y, "eye"); c.set(x0, y, "eye"); c.set(x0 + 1, y + 1, "eye")
            else:
                c.rect(x0 - 2, y + 1, x0 + 1, y + 1, "eye")
            continue
        c.blob(cx, 11.4 + oy, 2.7, 2.7, "iris", shade="irisD")
        px, py = x0 - 1, 11 + oy
        if style == "up":
            py -= 1
        elif style == "left":
            px -= 1
        elif style == "right":
            px += 1
        elif style == "down":
            py += 1
        c.rect(px, py, px + 1, py + 1, "eye")
        c.set(px, py, "white")
        if style == "sparkle":
            c.set(px + 1, py + 1, "white")
            c.set(px + 2, py - 1, "white")


def draw_beak(c: Canvas, style, oy):
    y = 13 + oy
    c.rect(15, y, 16, y + 1, "beak")
    c.set(15, y + 2, "beakD"); c.set(16, y + 2, "beak")
    c.set(14, y, "beakD"); c.set(17, y, "beakD")
    if style == "o":
        c.set(15, y + 3, "mouth"); c.set(16, y + 3, "mouth")
    elif style == "open":
        c.rect(15, y + 3, 16, y + 3, "mouth"); c.rect(15, y + 4, 16, y + 4, "beakD")
    elif style == "big":
        c.rect(14, y + 3, 17, y + 3, "mouth"); c.set(15, y + 4, "tongue"); c.set(16, y + 4, "tongue")
        c.rect(15, y + 5, 16, y + 5, "beakD")


def wing(c: Canvas, side, tip, dy=0, base_y=17.5):
    """A wing from the shoulder to `tip`, as a tapering feathered shape."""
    sx = 16 + side * 7.6
    es = []
    for i in range(9):
        t = i / 8
        es.append((sx + (tip[0] - sx) * t, base_y + dy + (tip[1] + dy - base_y - dy) * t, 2.4 - 1.2 * t,
                   2.4 - 1.2 * t))
    c.shape(es, "furD", shade="out")
    c.set((sx + tip[0]) / 2, (base_y + tip[1]) / 2 + dy, "spot")


def draw_wings(c: Canvas, style="hold", dy=0, lift=0.0, wave=0.0):
    if style == "hold":   # folded along the sides
        for side in (-1, 1):
            c.shape([(16 + side * 7.4, 21.6 + dy, 2.2, 5.8)], "furD", shade="out")
            c.set(16 + side * 7.4, 20 + dy, "spot"); c.set(16 + side * 7.4, 24 + dy, "spot")
    elif style == "cup":
        wing(c, -1, (6.0, 12.6), dy)
        c.shape([(23.4, 21.6 + dy, 2.2, 5.8)], "furD", shade="out")
    elif style == "up":
        wing(c, -1, (3.6, 9.0), dy); wing(c, 1, (28.4, 9.0), dy)
    elif style == "wave":
        c.shape([(8.6, 21.6 + dy, 2.2, 5.8)], "furD", shade="out")
        wing(c, 1, (28.2 + wave, 9.6 - abs(wave) * 0.4), dy)
    elif style == "book":  # an open book held in front of the belly; `lift` turns a page
        for side in (-1, 1):
            c.shape([(16 + side * 7.4, 21.6 + dy, 2.2, 5.8)], "furD", shade="out")
        c.rect(9, 21 + dy, 22, 27 + dy, "out")
        c.rect(10, 22 + dy, 21, 26 + dy, "book")
        c.rect(10, 22 + dy, 15, 25 + dy, "page"); c.rect(16, 22 + dy, 21, 25 + dy, "page")
        c.set(15, 22 + dy, "pageD"); c.set(16, 22 + dy, "pageD")
        for x in (11, 12, 13, 17, 18, 19, 20):
            c.set(x, 23 + dy + (x % 2), "pageD")
        if lift:  # the page flipping over
            for y in range(22, 26):
                c.set(16 + int(lift * 2), y + dy, "pageD")
        c.blob(10.5, 25.0 + dy, 1.4, 1.2, "furD", shade="out")
        c.blob(21.5, 25.0 + dy, 1.4, 1.2, "furD", shade="out")
    elif style == "none":
        pass


def owl(eyes="open", mouth="closed", wings="hold", glow=False, dy=0, blush=True, lift=0.0, wave=0.0, puff=0.0):
    c = canvas()
    draw_body(c, dy, puff)
    draw_face(c, dy, eyes, mouth, blush)
    draw_phones(c, cy=10.0 + dy, rx=10.6, ry=7.6, cup_dx=9.8, glow=glow)
    draw_wings(c, wings, dy, lift, wave)
    return c


# ---------------------------------------------------------------- side view (hopping right)
def side_owl(phase=0.0, eyes="open"):
    """Little owls hop and run on the ground: the body bobs, the feet tuck in mid-hop."""
    c = canvas()
    hop = max(0.0, math.sin(phase * 2 * math.pi)) * 3.0
    oy = -hop
    # short tail
    c.shape([(8.6, 24.6 + oy, 3.0, 1.4)], "furD", shade="out")
    # legs
    if hop < 1.0:
        for x in (14.5, 17.5):
            c.capsule((x, 27.0 + oy), (x + 0.6, 30.0), 0.9, "cream", shade="out")
            c.set(x + 1.6, 30, "toe"); c.set(x + 2.4, 30, "toe")
    else:
        c.blob(16.0, 28.4 + oy, 2.0, 1.0, "toe", shade="out")
    # plump body + round head (one shape)
    c.shape([(15.4, 23.0 + oy, 6.6, 5.4), (20.4, 15.6 + oy, 6.0, 5.4)], "fur", shade="furD", light="furL")
    for x, y in ((12, 21), (15, 19), (11, 24), (17, 17), (21, 11), (18, 12), (23, 12)):
        c.set(x, y + oy, "spot")
    c.shape([(18.4, 24.0 + oy, 3.6, 3.6)], "cream", outline=False, shade="creamD")
    c.shape([(12.6, 22.6 + oy, 3.4, 3.4)], "furD", shade="out")   # folded wing
    o = int(round(oy))
    # face to the right: eye, brow, beak
    c.blob(24.2, 16.0 + oy, 2.6, 2.4, "disc", outline=False)
    if eyes == "open":
        c.blob(24.6, 15.6 + oy, 1.8, 1.8, "iris", shade="irisD")
        c.set(25, 15 + o, "eye"); c.set(25, 16 + o, "eye"); c.set(25, 15 + o, "white")
    else:
        c.set(24, 16 + o, "eye"); c.set(25, 16 + o, "eye")
    for i in range(3):
        c.set(23 + i, 13 + o, "brow")
    c.set(27, 17 + o, "beak"); c.set(27, 18 + o, "beakD"); c.set(26, 18 + o, "beak")
    draw_side_phones(c, 19.6, 15.4 + oy, r=5.4)
    return c


def nest_owl(eyes="closed", breathe=0, zz=True):
    """Dozing: fluffed up into a round ball, head sunk into the shoulders."""
    c = owl(eyes=eyes, mouth="closed", wings="hold", dy=2 + breathe, puff=0.8 + breathe * 0.3, blush=False)
    if zz:
        draw_zz(c, 23, 1)
    return c


# ---------------------------------------------------------------- dock activities
def juggle_frame(i, n=8):
    """Tossing two acorns with the wings."""
    c = owl(eyes="up", mouth="closed", wings="up")
    for k in range(2):
        t = ((i / n) + k * 0.5) % 1.0
        x = 5.0 + 22.0 * t
        y = 9.0 - 8.0 * math.sin(math.pi * t)
        c.blob(x, y + 0.6, 1.8, 2.0, "acorn", shade="acornD")
        c.rect(x - 1.6, y - 1.6, x + 1.2, y - 1.0, "cap")
    return c


def groom_frame(i):
    """Preening: the beak dips into the raised wing, then the head shakes."""
    side = -1 if i < 3 else 1
    c = owl(eyes="closed", mouth="closed", wings="none", dy=(0, 1, 0)[i % 3])
    for s in (-1, 1):
        if s == side:
            wing(c, s, (16 + s * 4.0, 15.4), 0, base_y=22.0)
        else:
            c.shape([(16 + s * 7.4, 21.6, 2.2, 5.8)], "furD", shade="out")
    return c


def dance_frame(i):
    c = owl(eyes="happy", mouth="big" if i % 4 == 0 else "o", wings="up" if i % 2 == 0 else "wave", dy=-(i % 2),
            wave=1.5 if i % 4 == 1 else -1.5)
    draw_note(c, 1 if i % 4 < 2 else 26, 1 + (i % 2))
    return c


def frames():
    return {
        "idle": [owl(), owl(), owl(eyes="left"), owl(), owl(eyes="blink"), owl()],
        "listen": [owl(eyes="sparkle", mouth="closed", wings="cup", glow=g) for g in (True, False, True, False)],
        # reads a little book, turns a page on frame 5 (the "tap" sound)
        "think": [owl(eyes="down", wings="book", lift=l) for l in (0, 0, 0, 0, 0.5, 1, 0, 0)],
        "talk": [owl(mouth="closed"), owl(mouth="o"), owl(mouth="open"), owl(mouth="big")],
        "happy": [owl(eyes="happy", mouth="big", wings="up", dy=d) for d in (0, -1, -3, -3, -1, 0)],
        "wave": [owl(eyes="happy", wings="wave", wave=w) for w in (0, 1.5, 0, -1.5)],
        "sleep": [owl(eyes="closed", dy=d, puff=0.4) for d in (1, 1, 2, 2)],
        "walk": [side_owl(phase=k / 6) for k in range(6)],
        "look": [owl(eyes=e) for e in ("left", "left", "open", "right", "right", "open")],
        "juggle": [juggle_frame(k) for k in range(8)],
        "groom": [groom_frame(k) for k in range(6)],
        "dance": [dance_frame(k) for k in range(8)],
        "sleepBack": [nest_owl(breathe=b) for b in (0, 0, 1, 1)],
        "wake": [nest_owl(eyes="open", zz=False), nest_owl(eyes="sparkle", breathe=1, zz=False),
                 owl(eyes="closed", mouth="big", wings="up"), owl(eyes="closed", mouth="big", wings="up"),
                 owl(eyes="blink"), owl()],
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    export_pack(frames(), root.parent / "Characters" / "owl", root / "preview" / "owl",
                "Hulo · little owl (32x32, shown x5)")
    print("ok")
