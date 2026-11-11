#!/usr/bin/env python3
"""Kontrola realistyczności ruchów: zakresy stawów, równowaga, prędkość zmian między klatkami.

python3 tool/check_motion.py            raport problemów (kod wyjścia 1, gdy są błędy)
"""
import json
import sys
from pathlib import Path

from figure import grounded, resolve, thickness

ROOT = Path(__file__).resolve().parent.parent


def rel(a):
    """Kąt do zakresu (-180, 180]."""
    a = (a + 180) % 360 - 180
    return 180 if a == -180 else a


# zakresy (stopnie) — z zapasem na styl animacji
# tułów to sztywny odcinek, więc zgięcie kręgosłupa „wchodzi” w kąt biodra — stąd szeroki zakres zgięcia
SIDE = {
    "biodro": (-55, 172),  # wyprost / zgięcie (udo względem tułowia)
    "kolano": (-8, 172),  # przeprost / zgięcie (|kąt| ≥ 172 = pełne zgięcie, też dopuszczalne)
    "bark": (-75, 180),  # wyprost ręki do tyłu / uniesienie (≤ −165 = uniesienie ponad 180°, dopuszczalne)
    "łokieć": (-8, 172),
    "szyja": (-65, 70),  # odgięcie / przygięcie głowy
}
FRONT = {
    "biodro": (-42, 95),  # przywiedzenie / odwiedzenie
    "kolano": (-110, 110),  # z przodu widać zgięcie kolan przy biodrach obróconych na zewnątrz (sumo)
    "bark": (-45, 180),
    "łokieć": (-172, 172),
    "szyja": (-45, 45),
}


def ok(name, v, lim):
    lo, hi = lim[name]
    if lo <= v <= hi:
        return True
    if name in ("kolano", "łokieć") and abs(v) >= 165:
        return True  # pełne zgięcie (zawinięcie przez ±180°)
    if name == "bark" and v <= -158:
        return True  # ręce za głową / nad głową nieco ponad 180°
    return False


def angles(p):
    """Kąty stawów względem segmentu wyżej (dodatnie = zgięcie / odwiedzenie)."""
    s = -1 if p.get("back") else 1
    t = p["t"]
    out = {}
    front = p.get("view") == "front"
    for sd, arm, leg in (("N", p["an"], p["ln"]), ("F", p["af"], p["lf"])):
        if front:
            # w widoku z przodu dodatnie kąty kończyn = na zewnątrz; tułów pochylony o (t − 180)
            tilt = rel(t - 180) * (1 if sd == "N" else -1)
            out["biodro" + sd] = rel(leg[0] - tilt)
            out["kolano" + sd] = rel(leg[0] - leg[1])
            out["bark" + sd] = rel(arm[0] - tilt)
            out["łokieć" + sd] = rel(arm[1] - arm[0])
        else:
            base = t - 180
            out["biodro" + sd] = rel(leg[0] - base) * s
            out["kolano" + sd] = rel(leg[0] - leg[1]) * s
            out["bark" + sd] = rel(arm[0] - base) * s
            out["łokieć" + sd] = rel(arm[1] - arm[0]) * s
    out["szyja"] = rel(p["h"] - t) * (-s if not front else 1)
    return out


MASS = {  # udział masy segmentów (środek odcinka)
    ("neck", "hip"): .46, ("head", "head"): .08,
    ("hpN", "knN"): .1, ("knN", "anN"): .05, ("hpF", "knF"): .1, ("knF", "anF"): .05,
    ("shN", "elN"): .03, ("elN", "haN"): .025, ("shF", "elF"): .03, ("elF", "haF"): .025,
}


SEGS = [("hip", "neck", .1), ("neck", "head", .1), ("hpN", "knN", .07), ("knN", "anN", .05), ("hpF", "knF", .07),
        ("knF", "anF", .05), ("anN", "toN", .04), ("anF", "toF", .04), ("shN", "elN", .045), ("elN", "haN", .04),
        ("shF", "elF", .045), ("elF", "haF", .04)]


def balance(j):
    """(środek masy x, zakres podparcia x) — podparcie: wszystkie części ciała dotykające podłogi."""
    cx = sum(m * (j[a][0] + j[b][0]) / 2 for (a, b), m in MASS.items()) / sum(MASS.values())
    sup = []
    for a, b, r in SEGS:
        for i in range(11):
            t = i / 10
            x = j[a][0] + (j[b][0] - j[a][0]) * t
            y = j[a][1] + (j[b][1] - j[a][1]) * t
            if y + r > -0.04:
                sup.append(x)
    return cx, (min(sup), max(sup)) if sup else None


# świadome wyjątki: ruch poza płaszczyzną boczną (rotacja, odwiedzenie), który rzut 2D pokazuje „za daleko”
EXEMPT = {
    "butterfly": "siad, stopy razem — kolana na boki (rzut z przodu)",
    "band_dislocates": "przenoszenie gumy bokiem za plecy",
    "shoulder_stretch": "ręka w poprzek klatki",
    "t_pushup": "rotacja tułowia, ręka do sufitu",
    "thoracic_open": "rotacja tułowia, ręka do sufitu",
    "thread_needle": "rotacja tułowia, ręka do sufitu",
    "worlds_greatest": "rotacja tułowia, ręka do sufitu",
    "prone_w": "ramiona odwiedzone (W) — w rzucie z boku łokieć wydaje się przeprostowany",
    "ytw_raises": "ramiona odwiedzone (W) — w rzucie z boku łokieć wydaje się przeprostowany",
    "seated_tucks": "siad z oparciem na dłoniach za plecami",
    "pigeon": "wyprost biodra wspomagany odcinkiem lędźwiowym (sztywny tułów modelu)",
    "shoulder_stand": "świeca: broda przy mostku, dłonie podpierają plecy",
}


def check():
    data = json.loads((ROOT / "assets" / "exercises.json").read_text())
    lib = data["poses"]
    errors, warns = [], []
    for e in data["exercises"]:
        anim = e["anim"]
        keys = anim["k"]
        anchor = anim.get("anchor", "ground")
        props = {p.get("type") if isinstance(p, dict) else p for p in anim.get("props", [])}
        poses = [resolve(k, lib) for k in keys]
        for k, p in zip(keys, poses):
            lim = FRONT if p.get("view") == "front" else SIDE
            if p.get("view") == "front" and abs(rel(p["t"] - 180)) > 30:
                continue  # skłony w widoku z przodu: kąty w rzucie nic nie mówią o stawach
            for name, v in angles(p).items():
                lo, hi = lim[name.rstrip("NF")]
                if e["id"] not in EXEMPT and not ok(name.rstrip("NF"), v, lim):
                    errors.append(f"{e['id']}: {k} — {name} {v:.0f}° poza zakresem {lo}…{hi}")
            fp = p.get("fp", 0)
            if not -35 <= fp <= 90:
                errors.append(f"{e['id']}: {k} — stopa {fp}°")
            if anchor == "ground" and not props and p.get("view") != "front" and p.get("lift", 0) == 0:
                j = grounded(p, anchor)
                cx, sup = balance(j)
                # tylko pozycje stojące — przy leżeniu sztywny tułów i tak upraszcza ułożenie ciała
                if -j["hip"][1] >= 0.45 and not p.get("back") and sup and not sup[0] - 0.05 <= cx <= sup[1] + 0.05:
                    warns.append(f"{e['id']}: {k} — środek masy {cx:+.2f} poza podparciem "
                                 f"{sup[0]:+.2f}…{sup[1]:+.2f} (przewróciłby się)")
            if anchor == "hands":
                j = grounded(p, anchor)
                for f in ("anN", "anF", "toN", "toF"):
                    if j[f][1] > 0:
                        errors.append(f"{e['id']}: {k} — w zwisie stopy w podłodze")
        # podpory: kończyna, której kąty się nie zmieniły, nie powinna odrywać się od podłogi (ani w nią wchodzić)
        if anchor == "ground" and len(poses) > 1:
            gj = [grounded(p, anchor) for p in poses]
            for i in range(len(poses)):
                for i2 in range(len(poses)):
                    a, b = poses[i], poses[i2]
                    if i == i2 or a.get("lift", 0) or b.get("lift", 0) or a.get("view") != b.get("view"):
                        continue
                    for limb, ang, tip in (("rękaN", "an", "haN"), ("rękaF", "af", "haF"), ("nogaN", "ln", "toN"),
                                           ("nogaF", "lf", "toF")):
                        ya, yb = gj[i][tip][1] + thickness(tip), gj[i2][tip][1] + thickness(tip)
                        if ya > -0.02 and yb < -0.06 and a[ang] == b[ang] and a["t"] == b["t"]:
                            warns.append(f"{e['id']}: {keys[i2]} — {limb} unosi się nad podłogę ({-yb:.2f} m), "
                                         f"choć w {keys[i]} się opiera")
        # prędkość: zmiana kąta między kolejnymi klatkami w stosunku do czasu klatki
        if len(poses) > 1:
            dt = anim.get("s", 1.0)
            loop = poses + [poses[0]]
            for a, b, ka, kb in zip(loop, loop[1:], keys + [keys[0]], keys[1:] + [keys[0]]):
                aa, ab = angles(a), angles(b)
                for name in aa:
                    v = abs(rel(ab[name] - aa[name])) / dt
                    if v > 400:
                        warns.append(f"{e['id']}: {ka}→{kb} — {name} {v:.0f}°/s (za szybko)")
                dx = abs(a.get("x", 0) - b.get("x", 0)) / dt
                if dx > 1.5:
                    warns.append(f"{e['id']}: {ka}→{kb} — przesunięcie {dx:.1f} m/s")
    return errors, warns


if __name__ == "__main__":
    errs, warns = check()
    for x in errs:
        print("BŁĄD ", x)
    for x in warns:
        print("UWAGA", x)
    print(f"\n{len(errs)} błędów, {len(warns)} uwag")
    sys.exit(1 if errs else 0)
