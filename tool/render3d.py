#!/usr/bin/env python3
"""Realistyczna postać 3D — prototyp i podgląd (ta sama geometria co lib/ui/figure3d.dart).

python3 tool/render3d.py out.png [--yaw 0.55] id1 id2 ...      klatki kluczowe ćwiczeń z kilku kątów
python3 tool/render3d.py --sheet build/r3d_ ...                 arkusze kontrolne całego katalogu
"""
import json
import math
import sys
from pathlib import Path

import cairo

from figure import HIP_W, SHOULDER_W, grounded, resolve

ROOT = Path(__file__).resolve().parent.parent

SKIN = (0.91, 0.745, 0.612)
SHIRT = (1.0, 0.416, 0.239)
SHORTS = (0.204, 0.227, 0.306)
SHOE = (0.94, 0.95, 0.965)
SOLE = (0.25, 0.27, 0.32)
HAIR = (0.227, 0.165, 0.125)
EYE = (0.157, 0.118, 0.102)

# profile kończyn: (t, promień, wypukłość z przodu, wypukłość z tyłu)
ARM_UP = [(0, .056, 0, 0), (.35, .053, .009, .01), (.75, .045, .004, .003), (1, .04, 0, 0)]
ARM_LO = [(0, .043, 0, 0), (.22, .045, .005, .005), (1, .029, 0, 0)]
LEG_UP = [(0, .094, 0, 0), (.3, .089, .012, .007), (.75, .07, .005, .004), (1, .055, 0, 0)]
LEG_LO = [(0, .055, 0, 0), (.25, .052, .002, .019), (.62, .044, 0, .007), (1, .036, 0, 0)]
# przekroje tułowia: (t wzdłuż biodro→szyja, połowa szerokości, przód, tył)
TORSO = [(-0.1, .150, .088, .112), (0.12, .146, .086, .102), (0.42, .122, .084, .074),
         (0.70, .154, .118, .086), (0.86, .2, .094, .088), (1.0, .075, .05, .05)]
LIGHT = (-0.45, -0.89)


# ------------------------------------------------------------------ wektory
def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def mul(a, k): return tuple(x * k for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def lerp(a, b, t): return add(a, mul(sub(b, a), t))
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    l = math.sqrt(dot(a, a))
    return mul(a, 1 / l) if l > 1e-9 else (0, -1, 0)[:len(a)]


def prof(p, t):
    """Interpolacja profilu (gładka)."""
    for (t0, *v0), (t1, *v1) in zip(p, p[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0) if t1 > t0 else 0
            f = f * f * (3 - 2 * f)
            return [a + (b - a) * f for a, b in zip(v0, v1)]
    return list(p[-1][1:])


def hull(pts):
    pts = sorted(set((round(x, 3), round(y, 3)) for x, y in pts))
    if len(pts) < 3:
        return pts

    def half(ps):
        h = []
        for p in ps:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (p[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(p)
        return h

    lo, up = half(pts), half(pts[::-1])
    return lo[:-1] + up[:-1]


# ------------------------------------------------------------------ szkielet 3D
def lift(j, pose):
    front = pose.get("view") == "front"
    q = {}
    for k, (x, y) in j.items():
        z = 0
        if not front and k[-1] in "NF":
            arm = k[:2] in ("sh", "el", "ha")
            z = (1 if k[-1] == "N" else -1) * (SHOULDER_W if arm else HIP_W + 0.01)
        q[k] = (x, y, z)
    if front:
        for sd in "NF":
            an, to = q["an" + sd], q["to" + sd]
            q["to" + sd] = (an[0] + (to[0] - an[0]) * 0.6, to[1], 0.12)
    # stawy barkowe nieco poniżej podstawy szyi (jak w ciele) — cała ręka przesunięta razem z barkiem
    u = unit(sub(q["neck"], q["hip"]))
    drop = mul(u, -0.055)
    for sd in "NF":
        for k in ("sh", "el", "ha"):
            q[k + sd] = add(q[k + sd], drop)
    return q


def anterior(d, pose):
    """Przód kończyny (prostopadle do niej): z boku w płaszczyźnie ruchu, z przodu — do widza."""
    if pose.get("view") == "front":
        f = (0, 0, 1)
        return unit(sub(f, mul(d, dot(f, d))))
    a = (d[1], -d[0], 0)
    return mul(a, -1) if pose.get("back") else a


class Cam:
    def __init__(s, yaw, pitch, cx, dist=4.5):
        s.cy, s.sy, s.cp, s.sp, s.cx, s.d = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch), cx, dist

    def project(s, p):
        dx, dz = p[0] - s.cx, p[2]
        x1 = dx * s.cy + dz * s.sy
        z1 = -dx * s.sy + dz * s.cy
        y2 = p[1] * s.cp + z1 * s.sp
        z2 = z1 * s.cp - p[1] * s.sp
        k = s.d / (s.d - z2)
        return (x1 * k, y2 * k), z2, k


# ------------------------------------------------------------------ rysowanie
class Painter:
    def __init__(s, ctx, cam, scale, off):
        s.c, s.cam, s.s, s.o = ctx, cam, scale, off

    def pr(s, p):
        (x, y), z, k = s.cam.project(p)
        return (s.o[0] + x * s.s, s.o[1] + y * s.s), z, k

    def poly(s, pts):
        c = s.c
        c.move_to(*pts[0])
        for p in pts[1:]:
            c.line_to(*p)
        c.close_path()

    def shade(s, col, a, b, r, ka=0.18, kd=0.32):
        u = unit(sub(b, a)) if a != b else (0, -1)
        n = (-u[1], u[0])
        if dot(n, LIGHT) < 0:
            n = mul(n, -1)
        m = mul(add(a, b), 0.5)
        g = cairo.LinearGradient(*add(m, mul(n, r)), *sub(m, mul(n, r)))
        g.add_color_stop_rgb(0, *[min(1, v + (1 - v) * ka) for v in col])
        g.add_color_stop_rgb(0.42, *col)
        g.add_color_stop_rgb(1, *[v * (1 - kd) for v in col])
        return g

    def tint(s, col, z):
        t = max(0, min(1, (0.35 - z) / 0.7))
        return tuple(v * (1 - 0.25 * t) for v in col)

    def fill(s, pts, col, a, b, r, edge=True):
        s.poly(pts)
        s.c.set_source(s.shade(col, a, b, r))
        s.c.fill_preserve()
        if edge:
            s.c.set_source_rgba(0, 0, 0, 0.22)
            s.c.set_line_width(1)
            s.c.stroke()
        else:
            s.c.new_path()

    # kończyna z profilem mięśni
    def limb_pts(s, a, b, profile, front, n=14, grow=0.0, t1=1.0, t0=0.0):
        pa, _, ka = s.pr(a)
        pb, _, kb = s.pr(b)
        u = unit(sub(pb, pa)) if math.dist(pa, pb) > 1e-6 else (0, -1)
        nrm = (-u[1], u[0])
        # przód kończyny w rzucie: która strona konturu jest „przednia” i jak bardzo ją widać
        fp, _, _ = s.pr(add(lerp(a, b, 0.5), mul(front, 0.1)))
        mp, _, km = s.pr(lerp(a, b, 0.5))
        fv = mul(sub(fp, mp), 1 / (0.1 * s.s * km))
        side = dot(fv, nrm)
        left, right = [], []
        for i in range(n + 1):
            t = t0 + (t1 - t0) * i / n
            r, bf, bb = prof(profile, t)
            k = ka + (kb - ka) * t
            c = lerp(pa, pb, t)
            rl = (r + grow + (bf if side > 0 else bb) * abs(side)) * s.s * k
            rr = (r + grow + (bb if side > 0 else bf) * abs(side)) * s.s * k
            left.append(add(c, mul(nrm, rl)))
            right.append(sub(c, mul(nrm, rr)))
        r0 = (prof(profile, t0)[0] + grow) * s.s * (ka + (kb - ka) * t0)
        r1 = (prof(profile, t1)[0] + grow) * s.s * (ka + (kb - ka) * t1)
        pe = lerp(pa, pb, t1)
        ps = lerp(pa, pb, t0)
        cap0 = [add(ps, add(mul(u, -r0 * math.sin(th)), mul(nrm, -r0 * math.cos(th)))) for th in
                [math.pi * i / 8 for i in range(1, 8)]]
        cap1 = [add(pe, add(mul(u, r1 * math.sin(th)), mul(nrm, r1 * math.cos(th)))) for th in
                [math.pi * i / 8 for i in range(1, 8)]]
        pts = left + cap1 + right[::-1] + cap0
        return pts, ps, pe, max(r0, r1)

    def limb(s, a, b, profile, front, col, z, grow=0.0, t1=1.0, edge=True, t0=0.0):
        pts, pa, pe, r = s.limb_pts(a, b, profile, front, grow=grow, t1=t1, t0=t0)
        s.fill(pts, s.tint(col, z), pa, pe, r * 1.2, edge)

    def ball(s, p, r, col, edge=True):
        c, z, k = s.pr(p)
        rr = r * s.s * k
        g = cairo.RadialGradient(c[0] + LIGHT[0] * rr * .45, c[1] + LIGHT[1] * rr * .45, 0, c[0], c[1], rr * 1.5)
        col = s.tint(col, z)
        g.add_color_stop_rgb(0, *[min(1, v + (1 - v) * .2) for v in col])
        g.add_color_stop_rgb(.45, *col)
        g.add_color_stop_rgb(1, *[v * .68 for v in col])
        s.c.arc(c[0], c[1], rr, 0, 2 * math.pi)
        s.c.set_source(g)
        s.c.fill_preserve()
        if edge:
            s.c.set_source_rgba(0, 0, 0, .22)
            s.c.set_line_width(1)
            s.c.stroke()
        else:
            s.c.new_path()

    # tułów z przekrojów
    def torso_frame(s, q, pose):
        hip, neck = q["hip"], q["neck"]
        u = unit(sub(neck, hip))
        lat = (1, 0, 0) if pose.get("view") == "front" else (0, 0, 1)
        lat = unit(sub(lat, mul(u, dot(lat, u))))
        if pose.get("view") == "front":
            f = unit(cross(lat, u))
            if f[2] < 0:
                f = mul(f, -1)
        else:
            f = (-u[1], u[0], 0)
            if pose.get("back"):
                f = mul(f, -1)
        return hip, neck, u, lat, f

    def section(s, q, pose, t, w, df, db, grow=0.0, n=16):
        hip, neck, u, lat, f = s.torso_frame(q, pose)
        L = math.dist(hip, neck)
        c = add(hip, mul(u, L * t))
        pts = []
        for i in range(n):
            th = 2 * math.pi * i / n
            ca, sa = math.cos(th), math.sin(th)
            d = (df if sa > 0 else db) + grow
            pts.append(s.pr(add(add(c, mul(lat, (w + grow) * ca)), mul(f, d * sa)))[0])
        return pts

    def torso(s, q, pose, z, breath=0.0):
        hip, neck = q["hip"], q["neck"]
        secs = [(t, w, df * (1 + 0.04 * breath if t > .5 else 1), db) for t, w, df, db in TORSO]
        # spodenki
        lo = [x for x in secs if x[0] <= 0.42]
        lo = [(t if t < 0.4 else 0.2, w, df, db) for t, w, df, db in lo]
        s._union(q, pose, lo, SHORTS, z, grow=0.006)
        hi = [x for x in secs if x[0] >= 0.12]
        hi[0] = (0.14,) + hi[0][1:]
        s._union(q, pose, hi, SHIRT, z)

    def _union(s, q, pose, secs, col, z, grow=0.0):
        rings = [s.section(q, pose, *x, grow=grow) for x in secs]
        c = s.c
        for a, b in zip(rings, rings[1:]):
            s.poly(hull(a + b))
        c.set_fill_rule(cairo.FILL_RULE_WINDING)
        ph, _, _ = s.pr(q["hip"])
        pn, _, _ = s.pr(q["neck"])
        # najpierw obrys (2 px), potem wypełnienie — zostaje tylko zewnętrzna krawędź
        path = c.copy_path()
        c.set_source_rgba(0, 0, 0, 0.2)
        c.set_line_width(2)
        c.stroke()
        c.append_path(path)
        c.set_source(s.shade(s.tint(col, z), ph, pn, 0.17 * s.s))
        c.fill()

    def head(s, q, pose):
        head = q["head"]
        up = unit(sub(head, q["neck"]))
        if pose.get("view") == "front":
            face = (0, 0, 1)
        else:
            face = (-up[1], up[0], 0)
            if pose.get("back"):
                face = mul(face, -1)
        side = unit(cross(up, face))
        (c, zc, k) = s.pr(head)
        r = .1 * s.s * k
        # żuchwa / broda
        s.ball(add(add(head, mul(face, .022)), mul(up, -.045)), .062, SKIN, edge=False)
        # uszy (po stronie widza)
        for sg in (-1, 1):
            e, ze, ke = s.pr(add(head, mul(side, .093 * sg)))
            if ze > zc + .02:
                s.c.save()
                s.c.translate(*e)
                s.c.scale(.55, 1)
                s.c.arc(0, 0, .03 * s.s * ke, 0, 2 * math.pi)
                s.c.restore()
                s.c.set_source_rgb(*s.tint([v * .92 for v in SKIN], ze))
                s.c.fill()
        s.ball(head, .1, SKIN)
        # włosy
        def dirv(v):
            pp, _, _ = s.pr(add(head, mul(v, .1)))
            return ((pp[0] - c[0]) / (.1 * s.s * k), (pp[1] - c[1]) / (.1 * s.s * k))
        toward = max(-1, min(1, (s.pr(add(head, mul(face, .1)))[1] - zc) / .1))
        bf, bu = dirv(mul(face, -1)), dirv(up)
        w = .15 + 1.25 * max(0, toward)
        hc = (c[0] + (bf[0] * .6 + bu[0] * w) * r, c[1] + (bf[1] * .6 + bu[1] * w) * r)
        s.c.save()
        s.c.arc(c[0], c[1], r * 1.04, 0, 2 * math.pi)
        s.c.clip()
        s.c.arc(hc[0], hc[1], r, 0, 2 * math.pi)
        s.c.set_source_rgb(*HAIR)
        s.c.fill()
        s.c.restore()
        n, zn, _ = s.pr(add(add(head, mul(face, .1)), mul(up, -.012)))
        if zn > zc + .01:
            s.c.arc(n[0], n[1], r * (.17 - .09 * max(0, toward)), 0, 2 * math.pi)
            s.c.set_source_rgb(*s.tint(SKIN, zc))
            s.c.fill()
        for sg in (-1, 1):
            e, ze, _ = s.pr(add(add(add(head, mul(face, .086)), mul(side, .034 * sg)), mul(up, .02)))
            if ze > zc + .03:
                s.c.arc(e[0], e[1], max(1.2, r * .1), 0, 2 * math.pi)
                s.c.set_source_rgb(*EYE)
                s.c.fill()

    def hand(s, el, ha, z):
        d = unit(sub(ha, el))
        s.ball(add(ha, mul(d, .02)), .036, SKIN)
        s.ball(add(ha, mul(d, .055)), .03, SKIN, edge=False)

    def shoe(s, an, to, z, front):
        d = unit(sub(to, an))
        heel = sub(an, mul(d, .04))
        tip = add(to, mul(d, .015))
        prof_ = [(0, .044, 0, 0), (.3, .046, 0, 0), (1, .034, 0, 0)]
        # podeszwa — przesunięta w dół
        down = (0, .012, 0)
        s.limb(add(heel, down), add(tip, down), [(0, .04, 0, 0), (1, .032, 0, 0)], front, SOLE, z, edge=False)
        s.limb(heel, tip, prof_, front, SHOE, z)


def draw(ctx, pose, anchor, box, yaw, pitch=0.2, floor=True, breath=0.0):
    W, H = box[2] - box[0], box[3] - box[1]
    j = grounded(pose, anchor)
    q = lift(j, pose)
    cx = (min(v[0] for v in j.values()) + max(v[0] for v in j.values())) / 2
    cam = Cam(yaw, pitch, cx)
    pts = [cam.project(v)[0] for v in q.values()]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    bw, bh = max(max(xs) - min(xs), 1.2) + .4, max(max(ys) - min(ys), 1.3) + .35
    s = min(W / bw, H / bh)
    off = (box[0] + W / 2 - (min(xs) + max(xs)) / 2 * s, box[1] + H / 2 - (min(ys) + max(ys)) / 2 * s)
    P = Painter(ctx, cam, s, off)

    if floor and anchor != "hands":
        fx = sum(q[k][0] for k in ("anN", "anF", "hip")) / 3
        fz = sum(q[k][2] for k in ("anN", "anF", "hip")) / 3
        disk = [P.pr((fx + math.cos(a) * 1.25, 0, fz + math.sin(a) * 1.25))[0] for a in [i / 48 * math.tau for i in range(48)]]
        P.poly(disk)
        ctx.set_source_rgba(0.14, 0.155, 0.2, 1)
        ctx.fill()
        for part in ("hip", "neck", "kn", "an", "ha", "el"):
            for sd in ("N", "F") if part in ("kn", "an", "ha", "el") else ("",):
                v = q[part + sd]
                c, _, k = P.pr((v[0], 0, v[2]))
                lift_ = max(0, -v[1])
                rr = (.13 if part in ("hip", "neck") else .06) * s * k * (1 + lift_ * .3)
                ctx.save()
                ctx.translate(*c)
                ctx.scale(1, .35)
                ctx.arc(0, 0, rr, 0, 2 * math.pi)
                ctx.restore()
                ctx.set_source_rgba(0, 0, 0, .22 * max(.2, 1 - lift_ * .6))
                ctx.fill()

    # elementy z głębią
    items = []

    def zof(*ps):
        return sum(cam.project(p)[1] for p in ps) / len(ps)

    front = pose.get("view") == "front"
    for sd in "NF":
        sh, el, ha = q["sh" + sd], q["el" + sd], q["ha" + sd]
        hp, kn, an, to = q["hp" + sd], q["kn" + sd], q["an" + sd], q["to" + sd]
        dA, dF = unit(sub(el, sh)), unit(sub(ha, el))
        dT, dS = unit(sub(kn, hp)), unit(sub(an, kn))
        fA, fF, fT, fS = anterior(dA, pose), anterior(dF, pose), anterior(dT, pose), anterior(dS, pose)
        zA, zF, zT, zS = zof(sh, el), zof(el, ha), zof(hp, kn), zof(kn, an)
        items += [
            (zS, lambda kn=kn, an=an, f=fS, z=zS: P.limb(kn, an, LEG_LO, f, SKIN, z)),
            (zT + .001, lambda hp=hp, kn=kn, f=fT, z=zT: (P.limb(hp, kn, LEG_UP, f, SKIN, z),
                                                          P.limb(hp, kn, LEG_UP, f, SHORTS, z, grow=.007, t1=.42))),
            (zof(an, to) + .002, lambda an=an, to=to, z=zof(an, to), f=fS: P.shoe(an, to, z, f)),
            (zF + .003, lambda el=el, ha=ha, f=fF, z=zF: (P.limb(el, ha, ARM_LO, f, SKIN, z), P.hand(el, ha, z))),
            (zA + .004, lambda sh=sh, el=el, f=fA, z=zA: (P.limb(sh, el, ARM_UP, f, SKIN, z),
                                                          P.limb(sh, el, ARM_UP, f, SHIRT, z, grow=.005, t1=.38))),
        ]
    zt = zof(q["hip"], q["neck"])
    items.append((zt, lambda: (P.limb(q["neck"], lerp(q["neck"], q["head"], .55), [(0, .046, 0, 0), (1, .04, 0, 0)],
                                      (0, 0, 1), SKIN, zt, edge=False), P.torso(q, pose, zt, breath))))
    items.append((zof(q["head"]) + .002, lambda: P.head(q, pose)))
    items.sort(key=lambda t: t[0])
    for _, f in items:
        f()


def load():
    data = json.loads((ROOT / "assets" / "exercises.json").read_text())
    return data["poses"], {e["id"]: e for e in data["exercises"]}


def render(out, ids, yaws=(0.0, 0.55, 1.4, 2.8), cell=300):
    lib, by = load()
    rows = [(by[i], k) for i in ids for k in by[i]["anim"]["k"][:2]]
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, cell * len(yaws), cell * len(rows))
    ctx = cairo.Context(surf)
    ctx.set_source_rgb(.06, .067, .082)
    ctx.paint()
    for r, (e, k) in enumerate(rows):
        for c, yaw in enumerate(yaws):
            draw(ctx, resolve(k, lib), e["anim"].get("anchor", "ground"), (c * cell, r * cell, (c + 1) * cell, (r + 1) * cell), yaw)
        ctx.set_source_rgb(.6, .63, .7)
        ctx.move_to(4, r * cell + 14)
        ctx.show_text(e["id"])
    surf.write_to_png(out)
    print(out)


def sheet(prefix, per=48, yaw=0.5):
    lib, by = load()
    ids = list(by)
    cw, ch, cols = 170, 190, 8
    for n in range(0, len(ids), per):
        part = ids[n:n + per]
        rows = (len(part) + cols // 2 - 1) // (cols // 2)
        surf = cairo.ImageSurface(cairo.FORMAT_RGB24, cols * cw, rows * ch)
        ctx = cairo.Context(surf)
        ctx.set_source_rgb(.06, .067, .082)
        ctx.paint()
        for i, eid in enumerate(part):
            e = by[eid]
            keys = e["anim"]["k"]
            bx, by_ = (i % (cols // 2)) * 2 * cw, (i // (cols // 2)) * ch
            for c, k in enumerate([keys[0], keys[len(keys) // 2]]):
                draw(ctx, resolve(k, lib), e["anim"].get("anchor", "ground"), (bx + c * cw, by_, bx + (c + 1) * cw, by_ + ch), yaw)
            ctx.set_source_rgb(.6, .63, .7)
            ctx.move_to(bx + 4, by_ + 12)
            ctx.show_text(eid)
        out = f"{prefix}{n // per + 1}.png"
        surf.write_to_png(out)
        print(out)


if __name__ == "__main__":
    if sys.argv[1] == "--sheet":
        sheet(sys.argv[2], yaw=float(sys.argv[3]) if len(sys.argv) > 3 else 0.5)
    else:
        render(sys.argv[1], sys.argv[2:])
