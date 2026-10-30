#!/usr/bin/env python3
"""Mapa mięśni (przód i tył) — kształty wspólne z lib/ui/muscle_map.dart (assets/muscles.json).

Współrzędne prawej połowy ciała w polu 100 × 220 (oś x = 50); lewa połowa to odbicie.
python3 tool/muscle_map.py  → assets/muscles.json + build/muscles.png (podgląd)
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FRONT = {
    "shoulders": [(61, 38), (70, 37), (78, 42), (80, 52), (76, 58), (68, 54), (63, 46)],
    "chest": [(51, 39), (61, 38), (64, 46), (67, 54), (63, 61), (55, 64), (51, 63)],
    "biceps": [(70, 58), (77, 59), (80, 66), (80, 75), (76, 80), (71, 74), (69, 66)],
    "forearms": [(77, 82), (81, 77), (85, 86), (89, 100), (87, 108), (82, 108), (78, 96)],
    "abs": [(51, 66), (56, 65), (58, 74), (58, 90), (57, 101), (51, 105)],
    "obliques": [(57, 65), (63, 63), (66, 70), (67, 84), (64, 98), (58, 101), (59, 88), (59, 74)],
    "quads": [(56, 112), (63, 106), (69, 112), (70, 128), (68, 146), (64, 156), (57, 156), (55, 142), (56, 126)],
    "adductors": [(51, 110), (56, 112), (56, 126), (55, 140), (52, 144), (51, 130)],
    "calves": [(57, 166), (64, 164), (67, 176), (66, 192), (63, 204), (59, 204), (57, 190)],
}
BACK = {
    "traps": [(51, 28), (55, 30), (60, 36), (68, 40), (61, 45), (55, 52), (51, 56)],
    "shoulders": [(62, 40), (70, 38), (78, 42), (80, 52), (76, 58), (69, 54), (64, 47)],
    "upper_back": [(52, 57), (56, 52), (62, 46), (68, 51), (68, 59), (60, 64), (52, 66)],
    "lats": [(53, 68), (61, 65), (69, 60), (71, 68), (68, 82), (61, 92), (56, 90)],
    "lower_back": [(51, 70), (54, 70), (57, 91), (61, 94), (61, 103), (51, 106)],
    "triceps": [(70, 58), (77, 58), (81, 66), (81, 75), (77, 80), (71, 74), (69, 66)],
    "forearms": [(77, 82), (81, 77), (85, 86), (89, 100), (87, 108), (82, 108), (78, 96)],
    "abductors": [(62, 98), (68, 96), (71, 104), (70, 110), (64, 104)],
    "glutes": [(51, 108), (63, 102), (70, 112), (70, 124), (65, 130), (56, 131), (51, 128)],
    "hamstrings": [(53, 133), (63, 132), (69, 128), (70, 142), (66, 156), (58, 158), (54, 148)],
    "calves": [(56, 164), (64, 162), (68, 172), (68, 186), (64, 198), (59, 198), (56, 184)],
}
# części ciała bez mięśni (rysowane neutralnie)
OUTLINE = {
    "head": {"c": [50, 17], "r": 11},
    "neck": [(46, 27), (54, 27), (55, 35), (45, 35)],
    "hand": [(82, 108), (88, 108), (90, 118), (85, 122), (81, 116)],
    "knee": [(57, 156), (65, 156), (65, 166), (57, 166)],
    "foot": [(58, 204), (64, 204), (67, 212), (58, 213)],
    "pelvis_f": [(51, 104), (58, 101), (64, 99), (68, 108), (63, 106), (56, 112), (51, 110)],
}


def mirror(pts):
    return [(100 - x, y) for x, y in reversed(pts)]


def export():
    data = {
        "front": {k: v for k, v in FRONT.items()},
        "back": {k: v for k, v in BACK.items()},
        "outline": {k: v for k, v in OUTLINE.items()},
    }
    (ROOT / "assets" / "muscles.json").write_text(json.dumps(data, separators=(",", ":")))


def preview(load=None):
    from PIL import Image, ImageDraw

    load = load or {"chest": 1, "triceps": 0.6, "shoulders": 0.4, "abs": 0.2, "quads": 0.8, "glutes": 1, "lats": 0.5}
    S = 3
    img = Image.new("RGB", (220 * S, 230 * S), (24, 27, 34))
    d = ImageDraw.Draw(img)

    def col(v):
        if v <= 0:
            return (52, 57, 72)
        a = (255, 196, 75)
        b = (255, 106, 61)
        t = min(1, v)
        return tuple(int(52 + (a[i] + (b[i] - a[i]) * t - 52) * (0.45 + 0.55 * t)) for i in range(3))

    for ox, regions, extra in ((5, FRONT, ["pelvis_f"]), (115, BACK, [])):
        def P(p):
            return ((ox + p[0]) * S, (5 + p[1]) * S)

        o = OUTLINE
        c = o["head"]["c"]
        r = o["head"]["r"]
        d.ellipse([P((c[0] - r, c[1] - r)), P((c[0] + r, c[1] + r))], fill=(52, 57, 72))
        for k in ["neck", "hand", "knee", "foot", *extra]:
            pts = o[k]
            for poly in (pts, mirror(pts)):
                d.polygon([P(p) for p in poly], fill=(52, 57, 72))
        for k, pts in regions.items():
            for poly in (pts, mirror(pts)):
                d.polygon([P(p) for p in poly], fill=col(load.get(k, 0)), outline=(24, 27, 34))
    out = ROOT / "build" / "muscles.png"
    out.parent.mkdir(exist_ok=True)
    img.save(out)
    print(out)


if __name__ == "__main__":
    export()
    preview()
