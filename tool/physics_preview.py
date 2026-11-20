#!/usr/bin/env python3
"""Podgląd klatek ze sceną fizyki (rekwizyty, przypięcie, opuszczanie): python3 tool/physics_preview.py out.png id..."""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import physics as P

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / "assets" / "exercises.json").read_text())
EX = {e["id"]: e for e in data["exercises"]}
S, W, H, N = 90, 230, 260, 6
F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)


def draw(dr, sc, j, ox, oy):
    T = lambda p: (ox + p[0] * S, oy + p[1] * S)
    dr.line([(ox - 110, oy), (ox + 110, oy)], fill=(140, 140, 140))
    for p in sc.props:
        if p[0] == "chair":
            dr.rectangle([T((p[1], p[3])), T((p[2], 0))], outline=(170, 120, 60), width=2)
            dr.rectangle([T((p[1], p[3])), T((p[2], p[3] + P.SEAT_T))], fill=(220, 190, 140))
        elif p[0] == "wall":
            dr.rectangle([T((p[1], -2.2)), T((p[2], 0))], fill=(200, 170, 120))
        elif p[0] == "bar":
            dr.line([T((-0.8, p[1])), T((0.8, p[1]))], fill=(170, 120, 60), width=3)
    for side, col in (("F", (150, 170, 220)), ("N", (30, 60, 160))):
        for a, b in (("hip", "neck"), ("neck", "sh" + side), ("sh" + side, "el" + side), ("el" + side, "ha" + side),
                     ("hip", "hp" + side), ("hp" + side, "kn" + side), ("kn" + side, "an" + side), ("an" + side, "to" + side)):
            w = 9 if a in ("hip",) and b == "neck" else 6
            dr.line([T(j[a]), T(j[b])], fill=col if b != "neck" else (40, 40, 40), width=w)
    h = T(j["head"]); r = 0.1 * S
    dr.ellipse([h[0] - r, h[1] - r, h[0] + r, h[1] + r], outline=(40, 40, 40), width=3)
    if sc.pivot:
        pv = T(j[sc.pivot]); dr.ellipse([pv[0] - 5, pv[1] - 5, pv[0] + 5, pv[1] + 5], fill=(220, 40, 40))
    for c in sc.ends:
        pv = T(j[c]); dr.ellipse([pv[0] - 4, pv[1] - 4, pv[0] + 4, pv[1] + 4], outline=(0, 160, 0), width=2)


ids = sys.argv[2:]
img = Image.new("RGB", (W * N, H * len(ids)), "white")
dr = ImageDraw.Draw(img)
for r, i in enumerate(ids):
    sc = P.Scene(EX[i]["anim"], data["poses"])
    j0 = sc.frame(sc.keys[0]); cx = sum(v[0] for v in j0.values()) / len(j0)
    for c in range(N):
        f = c / N
        j = sc.frame_at(sc.cycle * f)[1]
        draw(dr, sc, j, c * W + W / 2 - cx * S, r * H + H - 20 if not sc.hands else r * H + 30 - (-2.3) * S * 0 + 230)
        d, where = P.penetration(sc, j)
        dr.text((c * W + 4, r * H + 4), f"{i} {f:.2f}" + (f"  {d*100:.0f}cm" if d > 0.02 else ""), fill=(200, 0, 0) if d > 0.02 else (0, 0, 0), font=F)
img.save(sys.argv[1])
