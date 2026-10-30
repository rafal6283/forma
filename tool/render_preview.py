#!/usr/bin/env python3
"""Podgląd wszystkich póz ćwiczeń (arkusz PNG) — do sprawdzenia animacji bez telefonu.

python3 tool/render_preview.py [wyjście.png] [id_ćwiczenia ...]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from figure import HEAD_R, grounded, resolve

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / "assets" / "exercises.json").read_text())
LIB = data["poses"]
CELL = 150
S = 62  # px na metr


def font(sz):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        try:
            return ImageFont.truetype(f, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def props_for(ex, first):
    out = []
    for pr in ex["anim"].get("props", []):
        if pr["type"] == "chair":
            pt = first[pr["at"]]
            x0 = pt[0] + pr.get("dx", 0) - pr["w"] / 2
            out.append(("chair", x0, pt[1], pr["w"]))
        elif pr["type"] == "wall":
            out.append(("wall", pr["x"]))
        elif pr["type"] == "bar":
            out.append(("bar", first["haN"][1]))
    return out


def draw_pose(dr, j, ox, oy, front, hold, props):
    def P(p):
        return (ox + p[0] * S, oy + p[1] * S)

    dr.line([ (ox - 70, oy), (ox + 70, oy)], fill=(120, 120, 120), width=1)
    for pr in props:
        if pr[0] == "chair":
            _, x0, top, w = pr
            dr.rectangle([P((x0, top)), P((x0 + w, 0))], outline=(150, 120, 80), width=2)
        elif pr[0] == "wall":
            dr.line([P((pr[1], 0)), P((pr[1], -2))], fill=(150, 120, 80), width=3)
        elif pr[0] == "bar":
            dr.line([P((-0.6, pr[1])), P((0.6, pr[1]))], fill=(150, 120, 80), width=3)
    far = (150, 170, 220)
    near = (30, 60, 160)
    if front:
        far = near
    for side, col in (("F", far), ("N", near)):
        if side == "N":
            dr.line([P(j["hip"]), P(j["neck"])], fill=(20, 20, 20), width=5)
            hx, hy = P(j["head"])
            r = HEAD_R * S
            dr.ellipse([hx - r, hy - r, hx + r, hy + r], outline=(20, 20, 20), width=3)
        if front:
            dr.line([P(j["shN"]), P(j["shF"])], fill=(20, 20, 20), width=4)
            dr.line([P(j["hpN"]), P(j["hpF"])], fill=(20, 20, 20), width=4)
        dr.line([P(j[f"hp{side}"]), P(j[f"kn{side}"]), P(j[f"an{side}"]), P(j[f"to{side}"])], fill=col, width=4)
        dr.line([P(j[f"sh{side}"]), P(j[f"el{side}"]), P(j[f"ha{side}"])], fill=col, width=4)
        if hold:
            x, y = P(j[f"ha{side}"])
            dr.rectangle([x - 5, y - 3, x + 5, y + 3], fill=(200, 60, 40))


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "poses.png"
    only = set(sys.argv[2:])
    exs = [e for e in data["exercises"] if not only or e["id"] in only]
    cols = max(len(e["anim"]["k"]) for e in exs)
    img = Image.new("RGB", (cols * CELL + 170, len(exs) * CELL), "white")
    dr = ImageDraw.Draw(img)
    f = font(13)
    for r, e in enumerate(exs):
        anchor = e["anim"].get("anchor", "ground")
        poses = [resolve(k, LIB) for k in e["anim"]["k"]]
        js = [grounded(p, anchor) for p in poses]
        props = props_for(e, js[0])
        dr.text((6, r * CELL + 6), f"{e['id']}\n{e['name']}", fill="black", font=f)
        for c, (p, j) in enumerate(zip(poses, js)):
            ox = 170 + c * CELL + CELL // 2
            oy = r * CELL + CELL - 14
            if anchor == "hands":
                oy = r * CELL + CELL - 4
            draw_pose(dr, j, ox, oy, p["view"] == "front", e.get("hold"), props)
            low = max(v[1] for v in j.values())
            dr.text((ox - 60, r * CELL + 4), f"min {low:+.2f}", fill=(160, 0, 0) if low > 0.02 else (90, 90, 90), font=font(10))
    out.parent.mkdir(exist_ok=True)
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
