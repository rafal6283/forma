#!/usr/bin/env python3
"""Ikona Formy (assets/icon.png, 1024 px): postać w wyskoku na koralowym tle."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
N = 1024
S = 4  # nadpróbkowanie dla gładkich krawędzi

img = Image.new("RGB", (N * S, N * S))
d = ImageDraw.Draw(img)
top, bot = (255, 122, 72), (232, 64, 76)
for y in range(N * S):
    k = y / (N * S)
    d.line([(0, y), (N * S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * k) for i in range(3)))


def P(x, y):
    return (x * S, y * S)


W = 64 * S
white = (255, 255, 255)
# głowa
cx, cy, r = 560, 250, 78
d.ellipse([P(cx - r, cy - r), P(cx + r, cy + r)], fill=white)
# tułów, ręce w górę, nogi w wyskoku
lines = [
    [(530, 360), (470, 600)],  # tułów
    [(520, 400), (690, 250), (760, 130)],  # ręka przednia
    [(520, 400), (360, 300), (300, 170)],  # ręka tylna
    [(470, 600), (620, 700), (600, 870)],  # noga przednia
    [(470, 600), (360, 760), (230, 800)],  # noga tylna
]
for ln in lines:
    pts = [P(*p) for p in ln]
    d.line(pts, fill=white, width=W, joint="curve")
    for p in pts:
        d.ellipse([p[0] - W / 2, p[1] - W / 2, p[0] + W / 2, p[1] + W / 2], fill=white)

img = img.resize((N, N), Image.LANCZOS)
out = ROOT / "assets" / "icon.png"
img.save(out)
print(out)
