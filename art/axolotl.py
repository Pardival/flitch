"""Axo, the axolotl: pixel-art generator for the `axolotl` character pack.

Axolotl reading, from photos (Wikimedia Commons, leucistic Ambystoma mexicanum):
- a very WIDE, flat head, wider than the body;
- three feathery external GILLS on each side of the head, deep pink-magenta;
- tiny black eyes set far apart, a wide, gentle smile;
- pale pink skin, four small limbs with thin fingers;
- a long tail with a fin that starts on the back.

    ../art/.venv/bin/python art/axolotl.py   # writes Characters/axolotl/sprites and art/preview/axolotl/sheet.png
"""
from __future__ import annotations

import math
from pathlib import Path

from pixel import Canvas, draw_note, draw_phones, draw_side_phones, draw_zz, export_pack

PAL = {
    "fur": (246, 186, 198),     # skin
    "furD": (222, 148, 166),
    "furL": (255, 216, 222),
    "belly": (253, 226, 228),
    "bellyD": (238, 200, 206),
    "gill": (214, 70, 130),
    "gillD": (168, 40, 98),
    "gillL": (244, 130, 176),
    "fin": (252, 214, 220),
    "mouth": (150, 58, 82),
    "bubble": (186, 230, 246),
    "bubbleL": (240, 252, 255),
    "bubbleD": (120, 182, 214),
}


def canvas() -> Canvas:
    return Canvas(PAL)


def mx(x):
    return 31 - x


# ---------------------------------------------------------------- front view
def draw_gills(c: Canvas, dy=0, sway=0.0, glow=False):
    """Three feathery stalks on each side of the head, fanning out."""
    for side in (-1, 1):
        for k, (ang, ln) in enumerate(((-38, 6.2), (-8, 6.6), (22, 5.6))):
            a = math.radians(ang + sway * (6 if k != 1 else -4))
            bx, by = 16 + side * 7.6, 9.6 + k * 2.4 + dy
            tx, ty = bx + side * ln * math.cos(a), by + ln * math.sin(a)
            c.capsule((bx, by), (tx, ty), 1.35, "gill", shade="gillD", outline_color="gillD")
            # fringe: little filaments along the stalk
            for t in (0.45, 0.7, 0.95):
                fx, fy = bx + (tx - bx) * t, by + (ty - by) * t
                c.set(fx, fy - 1.8, "gillL")
                c.set(fx, fy + 1.8, "gillL" if not glow else "white")


def draw_tail(c: Canvas, dy=0, curl=0.0):
    es = []
    for i in range(18):
        t = i / 17
        es.append((20.0 + 9.4 * t, 28.6 - 2.6 * t - curl * 8 * t * t + dy, 2.4 - 1.2 * t, 2.0 - 0.6 * t))
    c.shape(es, "fur", shade="furD")
    # pale fin along the top edge of the tail
    for i in range(3, 18, 2):
        x, y, r, ry = es[i]
        c.set(x, y - ry - 0.6, "fin")


def draw_body(c: Canvas, dy=0):
    c.shape([(16, 11.2 + dy, 10.4, 6.2), (16, 17.0 + dy, 6.6, 3.0), (16, 23.6 + dy, 6.6, 6.8)],
            "fur", shade="furD", light="furL")
    c.shape([(16, 24.4 + dy, 4.2, 5.2)], "belly", outline=False, shade="bellyD")
    # little hind feet with fingers
    for fx in (11.0, 21.0):
        c.blob(fx, 30.2 + min(0, dy), 2.4, 1.2, "fur", shade="furD")
        for t in (-1, 0, 1):
            c.set(fx + t * 1.2, 31 + min(0, dy), "out")


def draw_face(c: Canvas, dy=0, eyes="open", mouth="smile", blush=True):
    oy = int(round(dy))
    draw_eyes(c, eyes, oy)
    draw_mouth(c, mouth, oy)
    if blush:
        for x in (9, 10, 21, 22):
            c.set(x, 13 + oy, "blush")


def draw_eyes(c: Canvas, style, oy):
    y = 10 + oy
    for x in (10, 20):   # set far apart, like a real axolotl
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
        elif style in ("left", "right"):
            ox = -1 if style == "left" else 1
            c.rect(x + ox, y, x + 1 + ox, y + 1, "eye"); c.set(x + ox + (1 if ox > 0 else 0), y, "white")


def draw_mouth(c: Canvas, style, oy):
    y = 13 + oy
    if style == "smile":            # the wide, gentle axolotl smile
        c.rect(12, y, 19, y, "mouth"); c.set(11, y - 1, "mouth"); c.set(20, y - 1, "mouth")
    elif style == "calm":
        c.rect(12, y, 19, y, "mouth")
    elif style == "o":
        c.rect(14, y, 17, y, "mouth"); c.rect(15, y + 1, 16, y + 1, "mouth")
    elif style == "open":
        c.rect(12, y, 19, y, "mouth"); c.rect(13, y + 1, 18, y + 1, "mouth"); c.rect(14, y + 1, 17, y + 1, "tongue")
    elif style == "big":
        c.rect(11, y - 1, 20, y - 1, "mouth"); c.rect(12, y, 19, y + 1, "mouth"); c.rect(14, y + 1, 17, y + 1, "tongue")
    elif style == "sleep":
        c.rect(14, y, 17, y, "mouth")


def draw_arms(c: Canvas, style="hold", dy=0, wave=0.0):
    L = lambda a, b, r=1.2: c.capsule((a[0], a[1] + dy), (b[0], b[1] + dy), r, "fur", shade="furD")

    def hand(x, y):
        c.blob(x, y + dy, 1.4, 1.1, "furL", shade="furD")

    if style == "hold":
        L((11.0, 19.0), (13.6, 21.4)); L((21.0, 19.0), (18.4, 21.4)); hand(14.4, 21.6); hand(17.6, 21.6)
    elif style == "cup":
        L((10.6, 18.6), (7.6, 13.4)); hand(7.4, 12.8); L((21.0, 19.0), (18.4, 21.4)); hand(17.6, 21.6)
    elif style == "up":
        L((10.6, 18.6), (6.2, 14.2)); L((21.4, 18.6), (25.8, 14.2)); hand(5.8, 13.6); hand(26.2, 13.6)
    elif style == "wave":
        L((11.0, 19.0), (13.6, 21.4)); hand(14.4, 21.6)
        L((21.4, 18.6), (26.0 + wave, 14.0 - abs(wave) * 0.4)); hand(26.4 + wave, 13.4 - abs(wave) * 0.4)
    elif style == "face":   # both hands rubbing the cheeks
        L((10.8, 18.8), (9.6, 15.6 + wave)); L((21.2, 18.8), (22.4, 15.6 - wave))
        hand(9.6, 15.0 + wave); hand(22.4, 15.0 - wave)
    elif style == "none":
        pass


def axo(eyes="open", mouth="smile", arms="hold", glow=False, dy=0, curl=0.0, blush=True, sway=0.0, wave=0.0):
    c = canvas()
    draw_tail(c, dy=min(0, dy), curl=curl)
    draw_gills(c, dy, sway, glow)
    draw_body(c, dy)
    draw_face(c, dy, eyes, mouth, blush)
    draw_phones(c, cy=10.4 + dy, rx=10.6, ry=6.8, cup_rx=1.8, cup_ry=2.6, cup_dx=10.4, glow=glow)
    draw_arms(c, arms, dy, wave)
    return c


def bubble(c: Canvas, x, y, r=1.6):
    c.blob(x, y, r, r, "bubble", shade="bubbleD", outline_color="bubbleD")
    c.set(x - r * 0.4, y - r * 0.4, "bubbleL")


# ---------------------------------------------------------------- side view (crawling right)
def side_axo(phase=0.0, eyes="open", flat=False):
    c = canvas()
    a = phase * 2 * math.pi
    # long finned tail, swaying
    es = []
    for i in range(16):
        t = i / 15
        es.append((10.0 - 8.4 * t, 25.0 + (0 if flat else math.sin(a + t * 3) * 0.9 * t), 2.2 - 0.9 * t,
                   2.0 - 0.6 * t))
    c.shape(es, "fur", shade="furD")
    for i in range(2, 16, 2):
        x, y, r, ry = es[i]
        c.set(x, y - ry - 0.6, "fin")
        c.set(x, y + ry + 0.4, "fin")

    def leg(x, k, near):
        sw = 0 if flat else math.sin(a + k * math.pi) * 1.4
        y1 = 28.6 if not flat else 27.4
        c.capsule((x, 26.0), (x + sw + (1.2 if flat else 0), y1), 0.9, "fur" if near else "furD", shade="furD")
        for t in (-0.8, 0.4):
            c.set(x + sw + t + (1.6 if flat else 0), y1 + 1, "out")

    leg(12.6, 1, False); leg(20.4, 0, False)
    c.shape([(15.0, 24.6, 6.2, 2.8), (21.6, 23.4, 4.6, 3.2)], "fur", shade="furD", light="furL")
    # dorsal fin starting on the back
    for x in range(8, 18):
        c.set(x, 21.4 + (0.3 if x < 12 else 0), "fin")
    c.shape([(16.0, 26.6, 4.4, 0.9)], "belly", outline=False)
    leg(14.4, 0, True); leg(22.2, 1, True)
    # gills behind the head
    for k, ang in enumerate((-70, -40, -10)):
        r = math.radians(ang + (0 if flat else math.sin(a) * 8))
        bx, by = 22.0, 20.0 + k * 1.6
        c.capsule((bx, by), (bx - 5.0 * math.cos(r) * 0.6, by + 5.0 * math.sin(r)), 1.2, "gill", shade="gillD",
                  outline_color="gillD")
    c.shape([(25.4, 22.4, 5.2, 3.8)], "fur", shade="furD", light="furL")
    if eyes == "open":
        c.rect(27, 21, 28, 21, "eye"); c.set(27, 21, "white")
    else:
        c.rect(27, 22, 28, 22, "eye")
    c.rect(26, 24, 29, 24, "mouth"); c.set(30, 23, "mouth")
    draw_side_phones(c, 24.8, 22.4, r=4.4)
    return c


def napping_axo(eyes="closed", breathe=0, zz=True):
    """Lying flat on the ground, chin down, gills relaxed."""
    c = side_axo(eyes=eyes, flat=True)
    if breathe:
        c = canvas().paste(c, 0, 0)
        c.set(16, 21, "fin")
    if zz:
        draw_zz(c, 22, 11 - breathe)
    return c


# ---------------------------------------------------------------- dock activities
def juggle_frame(i, n=8):
    """Bouncing two bubbles over the head."""
    c = axo(eyes="up", mouth="o", arms="up", curl=0.2, sway=math.sin(i / n * 2 * math.pi))
    for k in range(2):
        t = ((i / n) + k * 0.5) % 1.0
        bubble(c, 6.0 + 20.0 * t, 9.0 - 8.0 * math.sin(math.pi * t), 1.8)
    return c


def groom_frame(i):
    """Fluffing the gills: they wave while both hands rub the cheeks."""
    return axo(eyes="closed", mouth="calm", arms="face", sway=(0, 1, 0, -1, 0, 1)[i % 6],
               wave=(0, -1, 0, 1, 0, -1)[i % 6])


def dance_frame(i):
    c = axo(eyes="happy", mouth="big" if i % 4 == 0 else "smile", arms="up" if i % 2 == 0 else "wave",
            dy=-(i % 2), curl=0.5 * (i % 2), sway=1 if i % 2 else -1, wave=1.5 if i % 4 == 1 else -1.5)
    draw_note(c, 1 if i % 4 < 2 else 26, 1 + (i % 2))
    return c


def think_frame(i):
    """Blowing bubbles while thinking: one rises and pops on frame 5 (the "tap" sound)."""
    c = axo(eyes="up", mouth="o" if i < 5 else "calm", arms="hold")
    if i < 5:
        bubble(c, 17.0 + i * 0.6, 12.0 - i * 2.2, 0.9 + i * 0.25)
    elif i == 5:
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1), (0, -2), (0, 2), (-2, 0), (2, 0)):
            c.set(20 + dx, 1 + dy, "bubbleD")
    return c


def frames():
    return {
        "idle": [axo(sway=s) for s in (0, 0.5, 1, 0.5, 0, 0)][:4] + [axo(eyes="blink"), axo()],
        "listen": [axo(eyes="sparkle", mouth="o", arms="cup", glow=g, sway=s)
                   for g, s in ((True, 0), (False, 1), (True, 0), (False, -1))],
        "think": [think_frame(k) for k in range(8)],
        "talk": [axo(mouth="calm"), axo(mouth="o"), axo(mouth="open"), axo(mouth="big")],
        "happy": [axo(eyes="happy", mouth="big", arms="up", dy=d, curl=0.6, sway=1) for d in (0, -1, -3, -3, -1, 0)],
        "wave": [axo(eyes="happy", arms="wave", wave=w) for w in (0, 1.5, 0, -1.5)],
        "sleep": [axo(eyes="closed", mouth="sleep", dy=d, sway=-1) for d in (1, 1, 2, 2)],
        "walk": [side_axo(phase=k / 6) for k in range(6)],
        "look": [axo(eyes=e) for e in ("left", "left", "open", "right", "right", "open")],
        "juggle": [juggle_frame(k) for k in range(8)],
        "groom": [groom_frame(k) for k in range(6)],
        "dance": [dance_frame(k) for k in range(8)],
        "sleepBack": [napping_axo(breathe=b) for b in (0, 0, 1, 1)],
        "wake": [napping_axo(eyes="open", zz=False), side_axo(eyes="open"),
                 axo(eyes="closed", mouth="big", arms="up", sway=1), axo(eyes="closed", mouth="big", arms="up"),
                 axo(eyes="blink"), axo()],
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    export_pack(frames(), root.parent / "Characters" / "axolotl", root / "preview" / "axolotl",
                "Axo · axolotl (32x32, shown x5)")
    print("ok")
