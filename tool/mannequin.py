#!/usr/bin/env python3
"""Postać „manekin” — kształty ciała z pozycji stawów (ten sam algorytm co lib/ui/figure_view.dart).

python3 tool/mannequin.py build/manekin.png squat pushups plank lunge ...
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from figure import grounded, resolve

ROOT = Path(__file__).resolve().parent.parent

# promienie (m): bliżej / dalej od tułowia
ARM_UP = (0.056, 0.042)
ARM_LO = (0.042, 0.030)
LEG_UP = (0.086, 0.058)
LEG_LO = (0.060, 0.036)
NECK_R = 0.038
HEAD_RX, HEAD_RY = 0.092, 0.108
# przekrój tułowia w widoku z boku: (t wzdłuż osi biodro→szyja, przód, tył)
SIDE_TORSO = [(-0.06, 0.09, 0.11), (0.15, 0.085, 0.095), (0.45, 0.085, 0.075), (0.72, 0.125, 0.085), (0.9, 0.11, 0.08),
              (1.0, 0.055, 0.05)]
# w widoku z przodu: (t, połowa szerokości)
FRONT_TORSO = [(-0.06, 0.15), (0.12, 0.14), (0.45, 0.115), (0.75, 0.15), (0.92, 0.175), (1.0, 0.08)]

COL = {
    "skin": ((232, 190, 156), (178, 134, 104)),
    "shirt": ((255, 106, 61), (186, 72, 40)),
    "shorts": ((52, 58, 78), (36, 40, 54)),
    "shoe": ((240, 242, 246), (160, 166, 178)),
    "hair": ((58, 42, 32), (58, 42, 32)),
}


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def norm(v):
    l = math.hypot(*v) or 1
    return (v[0] / l, v[1] / l)


def perp(v):
    return (-v[1], v[0])


def capsule(a, b, ra, rb):
    """Wielokąt zwężającej się kończyny + końce."""
    u = norm(sub(b, a))
    n = perp(u)
    pts = []
    steps = 6
    for i in range(steps + 1):  # półkole przy a
        ang = math.pi / 2 + math.pi * i / steps
        pts.append(add(a, (u[0] * math.cos(ang) + n[0] * math.sin(ang), u[1] * math.cos(ang) + n[1] * math.sin(ang)), ra))
    for i in range(steps + 1):  # półkole przy b
        ang = -math.pi / 2 + math.pi * i / steps
        pts.append(add(b, (u[0] * math.cos(ang) + n[0] * math.sin(ang), u[1] * math.cos(ang) + n[1] * math.sin(ang)), rb))
    return pts


def oval(c, u, rx, ry, n=20):
    """Elipsa o osi długiej wzdłuż u."""
    v = perp(u)
    return [add(add(c, u, rx * math.cos(2 * math.pi * i / n)), v, ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def torso_poly(j, pose):
    hip, neck = j["hip"], j["neck"]
    d = sub(neck, hip)
    L = math.hypot(*d) or 1
    u = norm(d)
    if pose["view"] == "front":
        n = perp(u)
        left = [add(add(hip, u, L * t), n, w) for t, w in FRONT_TORSO]
        right = [add(add(hip, u, L * t), n, -w) for t, w in reversed(FRONT_TORSO)]
        return left + right
    f = face_dir(pose["t"], pose["back"])
    front = [add(add(hip, u, L * t), f, fr) for t, fr, _ in SIDE_TORSO]
    back = [add(add(hip, u, L * t), f, -bk) for t, _, bk in reversed(SIDE_TORSO)]
    return front + back


def face_dir(angle, back):
    r = math.radians(angle)
    d = (math.sin(r), math.cos(r))
    f = (-d[1], d[0])
    return (-f[0], -f[1]) if back else f


def shorts_poly(j, pose):
    """Spodenki: miednica + górna część ud."""
    hip, neck = j["hip"], j["neck"]
    u = norm(sub(neck, hip))
    L = math.hypot(*sub(neck, hip))
    if pose["view"] == "front":
        n = perp(u)
        return [add(add(hip, u, L * 0.18), n, 0.145), add(add(hip, u, L * 0.18), n, -0.145),
                add(add(hip, u, -L * 0.08), n, -0.15), add(add(hip, u, -L * 0.08), n, 0.15)]
    f = face_dir(pose["t"], pose["back"])
    return [add(add(hip, u, L * 0.2), f, 0.088), add(add(hip, u, -0.07), f, 0.095),
            add(add(hip, u, -0.07), f, -0.115), add(add(hip, u, L * 0.2), f, -0.1)]


def foot_poly(j, side, back):
    """But z boku. n = strona grzbietu stopy (podeszwa po przeciwnej) — niezależnie od kąta stopy."""
    an, to = j[f"an{side}"], j[f"to{side}"]
    sv = sub(to, an)
    u = norm(sv)
    n = perp(u) if back else (-perp(u)[0], -perp(u)[1])
    pts = [(-0.35, -0.04), (-0.45, 0.01), (-0.2, 0.05), (0.6, 0.035), (1.25, 0.0), (1.1, -0.04), (0.0, -0.045)]
    return [add(add(an, sv, ks), n, kn) for ks, kn in pts]


def shapes(pose, anchor="ground"):
    """Lista (warstwa, kolor, wielokąt/elipsa) w kolejności rysowania."""
    j = grounded(pose, anchor)
    front = pose["view"] == "front"
    out = []

    def limb(side, far, upper, lower, a, b, c, sleeve, short):
        k = 1 if far else 0
        # górna część kończyny: rękaw/nogawka do połowy
        mid = lerp(j[a], j[b], 0.38 if sleeve else 0.45)
        out.append(("skin", k, capsule(j[a], j[b], *upper)))
        out.append(("skin", k, capsule(j[b], j[c], *lower)))
        if sleeve:
            out.append(("shirt", k, capsule(j[a], mid, upper[0] + 0.004, (upper[0] + upper[1]) / 2 + 0.004)))
        if short:
            out.append(("shorts", k, capsule(j[a], mid, upper[0] + 0.006, (upper[0] + upper[1]) / 2 + 0.006)))

    def arm(side, far):
        limb(side, far, ARM_UP, ARM_LO, f"sh{side}", f"el{side}", f"ha{side}", True, False)
        h = j[f"ha{side}"]
        u = norm(sub(h, j[f"el{side}"]))
        out.append(("skin", 1 if far else 0, ("ellipse", add(h, u, 0.035), 0.04)))

    def leg(side, far):
        limb(side, far, LEG_UP, LEG_LO, f"hp{side}", f"kn{side}", f"an{side}", False, True)
        if front:
            a, t = j[f"an{side}"], j[f"to{side}"]
            sd = norm(sub(a, j[f"kn{side}"]))
            # stopa na ziemi (goleń w dół) leży płasko; uniesiona — w poprzek goleni
            u = (1, 0) if sd[1] > 0.6 else perp(sd)
            out.append(("shoe", 0, oval(lerp(a, t, 0.4), u, 0.058, 0.034)))
        else:
            out.append(("shoe", 1 if far else 0, foot_poly(j, side, pose["back"])))

    if front:
        leg("F", False)
        leg("N", False)
    else:
        arm("F", True)
        leg("F", True)
    out.append(("shirt", 0, torso_poly(j, pose)))
    out.append(("shorts", 0, shorts_poly(j, pose)))
    # szyja i głowa
    out.append(("skin", 0, capsule(j["neck"], lerp(j["neck"], j["head"], 0.5), NECK_R, NECK_R)))
    out.append(("head", 0, j["head"]))
    if front:
        arm("F", False)
        arm("N", False)
    else:
        leg("N", False)
        arm("N", False)
    return j, out


def load():
    data = json.loads((ROOT / "assets" / "exercises.json").read_text())
    return data["poses"], {e["id"]: e for e in data["exercises"]}


def render(exs, out_path):
    lib, byid = load()
    S, cell = 150, 340
    cols = max(len(byid[i]["anim"]["k"]) for i in exs)
    img = Image.new("RGB", (cols * cell, len(exs) * cell), (15, 17, 21))
    d = ImageDraw.Draw(img, "RGBA")
    for r, eid in enumerate(exs):
        e = byid[eid]
        anchor = e["anim"].get("anchor", "ground")
        for c, k in enumerate(e["anim"]["k"]):
            pose = resolve(k, lib)
            draw(d, pose, anchor, c * cell + cell / 2, r * cell + cell - (5 if anchor == "hands" else 30), S)
    Path(out_path).parent.mkdir(exist_ok=True)
    img.save(out_path)
    print(out_path)


def sheet(prefix, per=40):
    """Arkusze kontrolne: każde ćwiczenie = 1. i środkowa klatka, podpis id."""
    lib, byid = load()
    ids = list(byid)
    S, cw, ch, blocks = 70, 165, 190, 4
    for n in range(0, len(ids), per):
        part = ids[n:n + per]
        rows = (len(part) + blocks - 1) // blocks
        img = Image.new("RGB", (blocks * 2 * cw, rows * ch), (15, 17, 21))
        d = ImageDraw.Draw(img, "RGBA")
        for i, eid in enumerate(part):
            e = byid[eid]
            keys = e["anim"]["k"]
            anchor = e["anim"].get("anchor", "ground")
            bx, by = (i % blocks) * 2 * cw, (i // blocks) * ch
            for c, k in enumerate([keys[0], keys[len(keys) // 2]]):
                draw(d, resolve(k, lib), anchor, bx + c * cw + cw / 2, by + ch - (4 if anchor == "hands" else 22), S)
            d.text((bx + 4, by + 2), eid, fill=(150, 160, 175))
            d.line([(bx, by), (bx, by + ch)], fill=(40, 44, 52))
        out = f"{prefix}{n // per + 1}.png"
        img.save(out)
        print(out)


def draw(d, pose, anchor, ox, oy, S):
    j, sh = shapes(pose, anchor)

    def P(p):
        return (ox + p[0] * S, oy + p[1] * S)

    if anchor != "hands":
        xs = [v[0] for v in j.values()]
        cx = (min(xs) + max(xs)) / 2
        w = (max(xs) - min(xs)) / 2 + 0.15
        d.ellipse([P((cx - w, -0.03)), P((cx + w, 0.03))], fill=(0, 0, 0, 90))
    for layer, far, geo in sh:
        if layer == "head":
            hx, hy = P(geo)
            rx, ry = 0.092 * S, 0.108 * S
            d.ellipse([hx - rx, hy - ry, hx + rx, hy + ry], fill=COL["skin"][0])
            # włosy: tył i czubek głowy (po stronie przeciwnej do twarzy)
            if pose["view"] == "front":
                d.chord([hx - rx, hy - ry, hx + rx, hy + ry * 0.6], 180, 360, fill=COL["hair"][0])
            else:
                f = face_dir(pose["h"], pose["back"])
                up = (math.sin(math.radians(pose["h"])), math.cos(math.radians(pose["h"])))
                hair = []
                for i in range(48):
                    th = 2 * math.pi * i / 48
                    v = (math.cos(th), math.sin(th))
                    if v[0] * up[0] + v[1] * up[1] - 0.75 * (v[0] * f[0] + v[1] * f[1]) > -0.2:
                        hair.append((hx + v[0] * rx * 1.04, hy + v[1] * ry * 1.04))
                if len(hair) > 2:
                    # kolejność łuku: obróć tak, by zacząć od przerwy
                    d.polygon(hair, fill=COL["hair"][0])
                ex = hx + f[0] * rx * 0.6 + up[0] * ry * 0.1
                ey = hy + f[1] * ry * 0.6 + up[1] * ry * 0.1
                d.ellipse([ex - 2.2, ey - 2.2, ex + 2.2, ey + 2.2], fill=(40, 30, 26))
                nx, ny = hx + f[0] * rx * 0.98 - up[0] * ry * 0.1, hy + f[1] * ry * 0.98 - up[1] * ry * 0.1
                d.ellipse([nx - 3.5, ny - 3.5, nx + 3.5, ny + 3.5], fill=COL["skin"][0])
            continue
        color = COL[layer][far]
        if isinstance(geo, tuple) and geo[0] == "ellipse":
            x, y = P(geo[1])
            rr = geo[2] * S
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=color)
        elif isinstance(geo, tuple) and geo[0] == "oval":
            x, y = P(geo[1])
            d.ellipse([x - geo[2] * S, y - geo[3] * S, x + geo[2] * S, y + geo[3] * S], fill=color)
        else:
            d.polygon([P(p) for p in geo], fill=color)
            if layer in ("skin", "shirt", "shorts") and len(geo) == 14:
                # połysk: węższa kapsuła przesunięta ku światłu (lewa-górna)
                cx = sum(p[0] for p in geo) / 14; cy = sum(p[1] for p in geo) / 14
                hl = [((p[0]-cx)*0.45+cx-0.012, (p[1]-cy)*0.82+cy-0.014) for p in geo]
                d.polygon([P(p) for p in hl], fill=(255, 255, 255, 34 if not far else 18))




if __name__ == "__main__":
    if sys.argv[1] == "--sheet":
        sheet(sys.argv[2])
    else:
        render(sys.argv[2:], sys.argv[1])
