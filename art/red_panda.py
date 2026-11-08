"""Pip, the red panda: pixel-art generator for the `red-panda` character pack.

Red panda reading, from photos (Wikimedia Commons, Ailurus fulgens):
- rusty orange-red fur, a wide round face;
- big pointed ears with a WHITE rim and a dark-red inside;
- a white muzzle, white "eyebrow" spots above the eyes and white cheek patches;
- dark red-brown "tear marks" running from the eyes down to the muzzle;
- a small black nose, dark eyes;
- BLACK-brown legs, chest and belly;
- a long bushy tail with pale ochre rings.

    ../art/.venv/bin/python art/red_panda.py   # writes Characters/red-panda/sprites and art/preview/red-panda/sheet.png
"""
from __future__ import annotations

import math
from pathlib import Path

from pixel import Canvas, draw_note, draw_phones, draw_side_phones, draw_zz, export_pack

PAL = {
    "fur": (198, 92, 44),
    "furD": (152, 62, 30),
    "furL": (226, 132, 72),
    "cream": (248, 240, 228),
    "creamD": (218, 204, 188),
    "blk": (62, 34, 26),
    "blkL": (92, 54, 40),
    "belly": (84, 44, 32),
    "tear": (128, 52, 28),
    "ring": (236, 178, 116),
    "ringD": (204, 142, 88),
    "nose": (26, 16, 14),
    "mouth": (92, 36, 28),
    "earIn": (110, 40, 24),
    "bamboo": (150, 204, 84),
    "bambooD": (82, 130, 48),
    "leaf": (156, 206, 96),
    "apple": (214, 62, 52),
    "appleD": (164, 38, 34),
    "appleL": (246, 130, 112),
}


def canvas() -> Canvas:
    return Canvas(PAL)


def mx(x):
    return 31 - x


# ---------------------------------------------------------------- front view
def draw_tail(c: Canvas, dy=0, curl=0.0):
    """Big bushy tail curling up on the right, rusty with pale ochre rings."""
    es = []
    for i in range(20):
        t = i / 19
        x = 20.6 + 8.6 * t
        y = 28.8 - 4.0 * t - curl * 9 * t * t + dy
        r = 3.4 - 1.3 * t
        es.append((x, y, r, r * 0.92))
    c.shape(es, "fur", shade="furD")
    for k in (6, 12, 18):
        x, y, r, _ = es[k]
        c.recolor([(x, y, 0.55, r + 1)], "ring")


def draw_ears(c: Canvas, dy=0, twitch=0):
    for k, side in enumerate((-1, 1)):
        t = twitch if k == 1 else 0
        tip = (16 + side * 8.2, 1.2 + dy - t)
        base_in = (16 + side * 3.2, 5.0 + dy)
        base_out = (16 + side * 10.6, 8.4 + dy)
        c.poly([base_in, tip, base_out], "cream", shade="creamD")
        inner = [(16 + side * 4.8, 5.6 + dy), (16 + side * 8.0, 2.8 + dy - t), (16 + side * 9.4, 7.6 + dy)]
        c.poly(inner, "earIn", outline=False)


def draw_body(c: Canvas, dy=0):
    # head + body as one shape (rusty), then the black chest/belly
    c.shape([(16, 10.8 + dy, 9.6, 6.6), (16, 16.4 + dy, 7.0, 3.4), (16, 23.0 + dy, 7.4, 7.6)],
            "fur", shade="furD", light="furL")
    c.shape([(16, 19.4 + dy, 4.2, 2.8), (16, 24.4 + dy, 4.8, 5.2)], "belly", outline=False, shade=None)
    for fx in (11.5, 20.5):
        c.blob(fx, 30.4 + min(0, dy), 2.5, 1.3, "blk", shade="out")


def draw_face(c: Canvas, dy=0, eyes="open", mouth="smile", blush=True):
    oy = int(round(dy))
    # white cheek patches and eyebrow spots
    for side in (-1, 1):
        c.blob(16 + side * 7.0, 12.2 + dy, 2.4, 2.4, "cream", outline=False, shade="creamD")
        c.blob(16 + side * 4.6, 6.4 + dy, 1.5, 1.0, "cream", outline=False)
    # white muzzle
    c.blob(16, 13.2 + dy, 4.4, 3.0, "cream", outline=False, shade="creamD")
    # tear marks: from under each eye down to the muzzle corners
    for x, y in ((11, 10), (11, 11), (12, 12), (12, 13)):
        c.set(x, y + oy, "tear")
        c.set(mx(x), y + oy, "tear")
    # small black nose
    c.rect(15, 11 + oy, 16, 12 + oy, "nose")
    c.set(14, 11 + oy, "nose")
    c.set(17, 11 + oy, "nose")
    c.set(15, 11 + oy, "blkL")
    draw_mouth(c, mouth, oy)
    draw_eyes(c, eyes, oy)
    if blush:
        c.set(9, 13 + oy, "blush")
        c.set(22, 13 + oy, "blush")


def draw_eyes(c: Canvas, style, oy):
    y = 8 + oy
    for x in (11, 19):
        if style == "open":
            c.rect(x, y, x + 1, y + 1, "eye")
            c.set(x, y, "white")
        elif style == "sparkle":
            c.rect(x, y - 1, x + 1, y + 1, "eye")
            c.set(x, y - 1, "white")
            c.set(x + 1, y + 1, "white")
        elif style == "up":
            c.rect(x, y - 1, x + 1, y, "eye")
            c.set(x + 1, y - 1, "white")
        elif style == "closed":
            c.set(x - 1, y, "eye"); c.set(x, y + 1, "eye"); c.set(x + 1, y + 1, "eye"); c.set(x + 2, y, "eye")
        elif style == "happy":
            c.set(x - 1, y + 1, "eye"); c.set(x, y, "eye"); c.set(x + 1, y, "eye"); c.set(x + 2, y + 1, "eye")
        elif style == "blink":
            c.rect(x - 1, y + 1, x + 2, y + 1, "eye")
        elif style in ("left", "right"):
            ox = -1 if style == "left" else 1
            c.rect(x + ox, y, x + 1 + ox, y + 1, "eye")
            c.set(x + ox + (1 if ox > 0 else 0), y, "white")


def draw_mouth(c: Canvas, style, oy):
    y = 13 + oy
    c.set(15, y, "mouth"); c.set(16, y, "mouth")  # philtrum under the nose
    if style == "smile":
        c.set(14, y + 1, "mouth"); c.set(17, y + 1, "mouth")
    elif style == "calm":
        c.rect(14, y + 1, 17, y + 1, "mouth")
    elif style == "open":
        c.rect(14, y + 1, 17, y + 2, "mouth"); c.set(15, y + 2, "tongue"); c.set(16, y + 2, "tongue")
    elif style == "big":
        c.rect(13, y + 1, 18, y + 1, "mouth"); c.rect(14, y + 2, 17, y + 3, "mouth")
        c.set(15, y + 3, "tongue"); c.set(16, y + 3, "tongue")
    elif style == "o":
        c.rect(15, y + 1, 16, y + 2, "mouth")
    elif style == "sleep":
        c.set(15, y + 1, "mouth"); c.set(16, y + 1, "mouth")
    elif style == "chew":
        c.rect(14, y + 1, 17, y + 1, "mouth"); c.set(15, y + 2, "mouth")


def draw_arms(c: Canvas, style="hold", dy=0, lift=0.0, wave=0.0):
    k = dict(shade="out")
    L = lambda a, b, r=1.4: c.capsule((a[0], a[1] + dy), (b[0], b[1] + dy), r, "blk", **k)
    if style == "hold":
        c.blob(14.0, 20.6 + dy, 1.8, 1.3, "blkL", outline=False, shade="out")
        c.blob(18.0, 20.6 + dy, 1.8, 1.3, "blkL", outline=False, shade="out")
    elif style == "cup":
        L((10.4, 18.0), (6.6, 14.0))
        c.blob(18.0, 20.6 + dy, 1.8, 1.3, "blkL", outline=False, shade="out")
    elif style == "up":
        L((10.6, 18.0), (5.8, 13.0), 1.5); L((21.4, 18.0), (26.2, 13.0), 1.5)
    elif style == "wave":
        c.blob(14.0, 20.6 + dy, 1.8, 1.3, "blkL", outline=False, shade="out")
        L((21.4, 18.0), (26.4 + wave, 13.2 - abs(wave) * 0.4), 1.5)
    elif style == "bamboo":  # holds a bamboo shoot, raised to the mouth by `lift` (0 down … 1 at the mouth)
        top = (21.4 - 3.0 * lift, 10.0 - 1.0 * lift + dy)
        c.capsule((22.4 - 1.0 * lift, 22.0 + dy), top, 1.7, "bamboo", shade="bambooD")
        for t in (0.35, 0.7):
            x = 22.4 - 1.0 * lift + (top[0] - 22.4 + 1.0 * lift) * t
            y = 22.0 + dy + (top[1] - 22.0 - dy) * t
            c.set(x, y, "bambooD")
        c.blob(top[0] + 2.0, top[1] - 0.6, 2.2, 1.1, "leaf", shade="bambooD")
        L((21.4, 19.0), (21.6 - 1.4 * lift, 17.4 - 3.0 * lift))
        c.blob(14.0, 20.6 + dy, 1.8, 1.3, "blkL", outline=False, shade="out")
    elif style == "none":
        pass


def panda(eyes="open", mouth="smile", arms="hold", glow=False, dy=0, curl=0.0, blush=True, twitch=0,
          lift=0.0, wave=0.0, tail=True):
    c = canvas()
    if tail:
        draw_tail(c, dy=min(0, dy), curl=curl)
    draw_ears(c, dy, twitch)
    draw_body(c, dy)
    draw_face(c, dy, eyes, mouth, blush)
    draw_phones(c, cy=10.4 + dy, rx=10.4, ry=7.2, glow=glow)
    draw_arms(c, arms, dy, lift, wave)
    return c


# ---------------------------------------------------------------- side view (walking right)
def side_panda(phase=0.0, bob=0.0, eyes="open"):
    c = canvas()
    oy = bob
    # long ringed tail behind, slightly raised
    es = []
    for i in range(16):
        t = i / 15
        es.append((8.6 - 7.0 * t, 22.4 + oy - 1.2 * math.sin(t * 2.6), 2.7 - 0.9 * t, 2.5 - 0.8 * t))
    c.shape(es, "fur", shade="furD")
    for k in (4, 8, 12):
        x, y, r, _ = es[k]
        c.recolor([(x, y, 0.55, r + 1)], "ring")
    a = phase * 2 * math.pi

    def leg(x, k, near):
        sw = math.sin(a + k * math.pi) * 1.7
        lift = max(0.0, math.cos(a + k * math.pi)) * 1.0
        c.capsule((x, 25.0 + oy), (x + sw, 29.6 - lift), 1.25, "blk" if near else "blkL", shade="out")

    leg(11.5, 1, False); leg(21.0, 0, False)
    c.shape([(15.0, 23.0 + oy, 6.8, 3.8), (21.0, 22.6 + oy, 5.0, 3.6)], "fur", shade="furD", light="furL")
    c.shape([(16.0, 26.0 + oy, 5.6, 1.4)], "blk", outline=False)  # dark belly
    leg(13.5, 0, True); leg(23.0, 1, True)
    # head: round, with the white muzzle pointing right
    c.shape([(25.4, 18.8 + oy, 4.4, 4.0)], "fur", shade="furD", light="furL")
    c.poly([(22.8, 16.2 + oy), (23.6, 11.2 + oy), (26.4, 15.2 + oy)], "cream", shade="creamD")  # ear
    c.blob(28.6, 20.2 + oy, 2.0, 1.6, "cream", outline=False, shade="creamD")
    c.blob(25.4, 16.2 + oy, 1.0, 0.7, "cream", outline=False)
    o = int(round(oy))
    c.set(30, 19 + o, "nose"); c.set(30, 20 + o, "nose")
    c.set(26, 19 + o, "tear"); c.set(27, 20 + o, "tear")
    if eyes == "open":
        c.set(26, 17 + o, "eye"); c.set(27, 17 + o, "eye"); c.set(26, 18 + o, "eye"); c.set(27, 17 + o, "white")
    else:
        c.set(26, 18 + o, "eye"); c.set(27, 18 + o, "eye")
    draw_side_phones(c, 24.8, 18.8 + oy, r=4.8)
    return c


def curled_panda(eyes="closed", breathe=0, zz=True, peek=False):
    """Asleep, curled in a ball with the ringed tail wrapped over the nose (as red pandas do)."""
    c = canvas()
    b = breathe * 0.4
    c.shape([(15.0, 25.0 - b, 9.6, 5.6 + b)], "fur", shade="furD", light="furL")
    # head resting on the right, ear up
    c.poly([(19.6, 21.0), (21.0, 16.0), (23.6, 20.0)], "cream", shade="creamD")
    c.blob(22.4, 23.0, 4.4, 3.6, "fur", shade="furD", light="furL")
    c.blob(23.6, 24.2, 2.4, 1.6, "cream", outline=False, shade="creamD")
    if eyes == "closed":
        c.set(21, 22, "eye"); c.set(22, 22, "eye")
    else:
        c.rect(21, 21, 22, 22, "eye"); c.set(21, 21, "white")
    c.set(25, 24, "nose")
    # tail wrapped across the front
    es = [(6.0 + 15.0 * i / 14, 28.6 - 1.4 * math.sin(math.pi * i / 14) + (0.6 if peek else 0), 2.6 - 0.6 * i / 14,
           2.2 - 0.4 * i / 14) for i in range(15)]
    c.shape(es, "fur", shade="furD")
    for k in (3, 7, 11):
        x, y, r, _ = es[k]
        c.recolor([(x, y, 0.55, r + 1)], "ring")
    draw_side_phones(c, 22.2, 23.0, r=4.4)
    if zz:
        draw_zz(c, 22, 9)
    return c


# ---------------------------------------------------------------- dock activities
def juggle_frame(i, n=8):
    """Sitting up, tossing two little apples."""
    c = panda(eyes="up", mouth="smile", arms="up", curl=0.2)
    for k in range(2):
        t = ((i / n) + k * 0.5) % 1.0
        x = 6.0 + 20.0 * t
        y = 11.0 - 10.0 * math.sin(math.pi * t)
        c.blob(x, y, 2.2, 2.1, "apple", shade="appleD", light="appleL")
        c.set(x, y - 2.4, "leaf")
    return c


def groom_frame(i):
    """Washing the face with both front paws, like a cat."""
    c = panda(eyes="closed", mouth="calm", arms="none")
    d = (0, -1, 0, 1, 0, -1)[i % 6]
    for side in (-1, 1):
        x = 16 + side * 5.5
        c.capsule((16 + side * 7.0, 19.5), (x, 14.0 + d * side), 1.6, "blk", shade="out")
        c.blob(x - side * 0.4, 13.6 + d * side, 2.0, 1.8, "blkL", shade="out")
    return c


def dance_frame(i):
    c = panda(eyes="happy", mouth="big" if i % 4 == 0 else "smile", arms="up" if i % 2 == 0 else "wave",
              dy=-(i % 2), curl=0.5 * (i % 2), wave=1.5 if i % 4 == 1 else -1.5)
    draw_note(c, 2 if i % 4 < 2 else 25, 1 + (i % 2))
    return c


def frames():
    return {
        "idle": [panda(), panda(), panda(curl=0.15), panda(curl=0.15), panda(eyes="blink"), panda()],
        "listen": [panda(eyes="sparkle", mouth="o", arms="cup", glow=g, twitch=t)
                   for g, t in ((True, 0), (False, 0), (True, 1), (False, 0))],
        # nibbles a bamboo shoot: raises it, bites (frame 5 = the "tap" sound), lowers it
        "think": [panda(eyes="up", mouth=m, arms="bamboo", lift=l)
                  for l, m in ((0, "calm"), (0.3, "calm"), (0.6, "calm"), (0.9, "o"), (1.0, "o"),
                               (1.0, "chew"), (0.6, "chew"), (0.2, "calm"))],
        "talk": [panda(mouth="calm"), panda(mouth="o"), panda(mouth="open"), panda(mouth="big")],
        "happy": [panda(eyes="happy", mouth="big", arms="up", dy=d, curl=0.6) for d in (0, -1, -3, -3, -1, 0)],
        "wave": [panda(eyes="happy", mouth="smile", arms="wave", wave=w) for w in (0, 1.5, 0, -1.5)],
        "sleep": [panda(eyes="closed", mouth="sleep", dy=d) for d in (1, 1, 2, 2)],
        "walk": [side_panda(phase=k / 6, bob=-0.5 if k % 3 == 1 else 0) for k in range(6)],
        "look": [panda(eyes=e) for e in ("left", "left", "open", "right", "right", "open")],
        "juggle": [juggle_frame(k) for k in range(8)],
        "groom": [groom_frame(k) for k in range(6)],
        "dance": [dance_frame(k) for k in range(8)],
        "sleepBack": [curled_panda(breathe=b) for b in (0, 0, 1, 1)],
        "wake": [curled_panda(eyes="open", zz=False), curled_panda(eyes="open", breathe=1, zz=False),
                 panda(eyes="closed", mouth="big", arms="up"), panda(eyes="closed", mouth="big", arms="up"),
                 panda(eyes="blink"), panda()],
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    export_pack(frames(), root.parent / "Characters" / "red-panda", root / "preview" / "red-panda",
                "Pip · red panda (32x32, shown x5)")
    print("ok")
