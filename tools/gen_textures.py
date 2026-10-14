#!/usr/bin/env python3
"""Generate the procedural textures for Night Racer (road + building windows)."""
import os
import random
from PIL import Image, ImageDraw

import os
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")
os.makedirs(OUT, exist_ok=True)
random.seed(7)


def road_texture():
    W, H = 256, 512                      # 13 m wide, 18 m long
    img = Image.new("RGB", (W, H), (28, 29, 34))
    d = ImageDraw.Draw(img)

    # asphalt grain
    px = img.load()
    for y in range(H):
        for x in range(W):
            n = random.randint(-6, 6)
            r, g, b = px[x, y]
            px[x, y] = (max(0, r + n), max(0, g + n), max(0, b + n))

    # shoulders
    d.rectangle([0, 0, 7, H], fill=(34, 35, 40))
    d.rectangle([W - 8, 0, W - 1, H], fill=(34, 35, 40))

    # dashed lane dividers (3 dividers -> 4 lanes)
    for cx in (64, 128, 192):
        for cy in (0, 256):
            d.rectangle([cx - 3, cy + 0, cx + 3, cy + 127], fill=(214, 219, 228))

    # solid edge lines
    d.rectangle([12, 0, 17, H], fill=(200, 205, 215))
    d.rectangle([W - 18, 0, W - 13, H], fill=(200, 205, 215))

    img.save(os.path.join(OUT, "road.png"))


def building_texture():
    W, H = 128, 256
    img = Image.new("RGB", (W, H), (9, 10, 15))
    d = ImageDraw.Draw(img)

    for gy in range(10, H - 8, 16):
        for gx in range(10, W - 8, 16):
            if random.random() < 0.55:
                if random.random() < 0.5:
                    base = (255, 205, 130)
                else:
                    base = (140, 215, 255)
                k = random.uniform(0.45, 1.0)
                col = tuple(int(c * k) for c in base)
                d.rectangle([gx, gy, gx + 8, gy + 9], fill=col)

    img.save(os.path.join(OUT, "building.png"))


if __name__ == "__main__":
    road_texture()
    building_texture()
    for f in ("road.png", "building.png"):
        p = os.path.join(OUT, f)
        print(f, Image.open(p).size, os.path.getsize(p), "bytes")
