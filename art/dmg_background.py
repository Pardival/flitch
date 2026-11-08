"""DMG window background (660x400 @1x and @2x): the otter points from the app to Applications.

    python art/dmg_background.py   # writes art/dmg/background.png and background@2x.png
"""
from pathlib import Path

from PIL import Image, ImageDraw

import otter as o

ROOT = Path(__file__).resolve().parent


def background(scale: int) -> Image.Image:
    w, h = 660 * scale, 400 * scale
    im = Image.new("RGBA", (w, h), (246, 244, 240, 255))
    d = ImageDraw.Draw(im)
    # soft teal band at the bottom
    d.rectangle([0, h - 70 * scale, w, h], fill=(214, 238, 234, 255))
    # dotted arrow from the app (x=170) to Applications (x=490), at icon height (y=190)
    y = 190 * scale
    for x in range(250 * scale, 410 * scale, 14 * scale):
        d.rounded_rectangle([x, y - 2 * scale, x + 7 * scale, y + 2 * scale], radius=2 * scale, fill=(15, 159, 143, 255))
    d.polygon([(410 * scale, y - 9 * scale), (424 * scale, y), (410 * scale, y + 9 * scale)], fill=(15, 159, 143, 255))
    # the otter waving, sitting on the band
    sprite = o.otter(eyes="happy", mouth="smile", arms="wave", wave=1.5).image()
    s = 3 * scale
    sprite = sprite.resize((32 * s, 32 * s), Image.NEAREST)
    im.alpha_composite(sprite, (w // 2 - 16 * s, h - 70 * scale - 31 * s))
    return im


if __name__ == "__main__":
    out = ROOT / "dmg"
    out.mkdir(exist_ok=True)
    background(1).save(out / "background.png")
    background(2).save(out / "background@2x.png")
    print("ok")
