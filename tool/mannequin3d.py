#!/usr/bin/env python3
"""Podgląd postaci 3D (ta sama geometria co lib/ui/figure3d.dart). python3 tool/mannequin3d.py out.png ids..."""
import json, math, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
from figure import grounded, resolve, SHOULDER_W, HIP_W

ROOT = Path(__file__).resolve().parent.parent
SKIN, SHIRT, SHORTS, SHOE, HAIR = (232,190,156), (255,106,61), (52,58,78), (240,242,246), (58,42,32)
ARM_UP, ARM_LO, LEG_UP, LEG_LO = (0.056,0.042), (0.042,0.030), (0.086,0.058), (0.060,0.036)

def lift(j, front):
    q = {}
    for k,(x,y) in j.items():
        z = 0
        if not front and k[-1] in "NF":
            arm = k[:2] in ("sh","el","ha")
            z = (1 if k[-1]=="N" else -1) * (SHOULDER_W if arm else HIP_W+0.01)
        q[k] = (x,y,z)
    if front:
        for sd in "NF":
            an, to = q["an"+sd], q["to"+sd]
            q["to"+sd] = (an[0]+(to[0]-an[0])*0.6, to[1], 0.12)
    return q

def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def add(a,b): return tuple(x+y for x,y in zip(a,b))
def mul(a,k): return tuple(x*k for x in a)
def lerp(a,b,t): return add(a, mul(sub(b,a),t))
def unit(a):
    l = math.sqrt(sum(x*x for x in a)) or 1
    return mul(a,1/l)
def cross(a,b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])

class Cam:
    def __init__(s, yaw, pitch, cx, dist=4.5):
        s.cy, s.sy, s.cp, s.sp, s.cx, s.d = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch), cx, dist
    def project(s, p):
        dx, dz = p[0]-s.cx, p[2]
        x1 = dx*s.cy + dz*s.sy; z1 = -dx*s.sy + dz*s.cy
        y2 = p[1]*s.cp + z1*s.sp; z2 = z1*s.cp - p[1]*s.sp
        k = s.d/(s.d-z2)
        return (x1*k, y2*k), z2, k

def body(q, breath=0):
    P = []
    hip, neck, head = q["hip"], q["neck"], q["head"]
    sp = lambda t: lerp(hip, neck, t)
    P += [(q["hpN"], q["hpF"], .105, .105, SHORTS, 0), (hip, sp(.22), .108, .104, SHORTS, .002),
          (sp(.18), sp(.5), .1, .098, SHIRT, 0), (sp(.48), sp(.82), .104, .118, SHIRT, 0)]
    c1 = add(sp(.86), mul(sub(q["shN"], neck), .62)); c2 = add(sp(.86), mul(sub(q["shF"], neck), .62))
    P += [(c1, c2, .085, .085, SHIRT, .001), (sp(.8), neck, .11, .075, SHIRT, 0), (neck, lerp(neck, head, .55), .042, .04, SKIN, -.002)]
    for sd in "NF":
        s0, el, ha = q["sh"+sd], q["el"+sd], q["ha"+sd]
        hp, kn, an, to = q["hp"+sd], q["kn"+sd], q["an"+sd], q["to"+sd]
        P += [(s0, s0, .062, .062, SHIRT, .004), (s0, el, *ARM_UP, SKIN, 0), (s0, lerp(s0, el, .38), .062, .052, SHIRT, .003),
              (el, ha, *ARM_LO, SKIN, 0)]
        hc = add(ha, mul(unit(sub(ha, el)), .03)); P.append((hc, hc, .04, .04, SKIN, .002))
        P += [(hp, kn, *LEG_UP, SKIN, 0), (hp, lerp(hp, kn, .45), .092, .08, SHORTS, .003), (kn, an, *LEG_LO, SKIN, 0)]
        fd = unit(sub(to, an)); P.append((sub(an, mul(fd, .035)), add(to, mul(fd, .01)), .046, .036, SHOE, .002))
    return P

def capsule_poly(a, b, ra, rb, n=8):
    ux, uy = b[0]-a[0], b[1]-a[1]; l = math.hypot(ux, uy) or 1; ux, uy = ux/l, uy/l
    if l < 1e-6: ux, uy = 0, -1
    nx, ny = -uy, ux; pts = []
    for i in range(n+1):
        t = math.pi/2 + math.pi*i/n; pts.append((a[0]+(ux*math.cos(t)+nx*math.sin(t))*ra, a[1]+(uy*math.cos(t)+ny*math.sin(t))*ra))
    for i in range(n+1):
        t = -math.pi/2 + math.pi*i/n; pts.append((b[0]+(ux*math.cos(t)+nx*math.sin(t))*rb, b[1]+(uy*math.cos(t)+ny*math.sin(t))*rb))
    return pts

def tint(c, z):
    t = max(0, min(1, (0.35 - z)/0.7)); return tuple(int(v*(1-0.28*t)) for v in c)

def draw(img, pose, anchor, box, yaw, pitch=0.2):
    W, H = box[2]-box[0], box[3]-box[1]
    j = grounded(pose, anchor); q = lift(j, pose["view"] == "front")
    cx = (min(v[0] for v in j.values()) + max(v[0] for v in j.values()))/2
    cam = Cam(yaw, pitch, cx)
    pts = [cam.project(v)[0] for v in q.values()]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    bw, bh = max(max(xs)-min(xs), 1.2)+.35, max(max(ys)-min(ys), 1.3)+.3
    s = min(W/bw, H/bh); ox = box[0] + W/2 - (min(xs)+max(xs))/2*s; oy = box[1] + H/2 - (min(ys)+max(ys))/2*s
    scr = lambda p: (ox+p[0]*s, oy+p[1]*s)
    d = ImageDraw.Draw(img, "RGBA")
    parts = body(q)
    if anchor != "hands":
        # podłoga + cienie
        fx = sum(q[k][0] for k in ("anN","anF","hip"))/3; fz = sum(q[k][2] for k in ("anN","anF","hip"))/3
        disk = [scr(cam.project((fx+math.cos(a)*1.25, 0, fz+math.sin(a)*1.25))[0]) for a in [i/48*math.tau for i in range(48)]]
        d.polygon(disk, fill=(35,39,51,200))
        sh = Image.new("RGBA", img.size, (0,0,0,0)); sd = ImageDraw.Draw(sh)
        for a,b,ra,rb,col,bias in parts:
            (pa,_,ka),(pb,_,kb) = cam.project((a[0],0,a[2])), cam.project((b[0],0,b[2]))
            sd.polygon(capsule_poly(scr(pa), scr(pb), ra*s*ka, rb*s*kb), fill=(0,0,0,70))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)))
        d = ImageDraw.Draw(img, "RGBA")
    items = [(( cam.project(a)[1]+cam.project(b)[1])/2 + bias, ("part", a,b,ra,rb,col)) for a,b,ra,rb,col,bias in parts]
    items.append((cam.project(q["head"])[1], ("head",)))
    items.sort(key=lambda t: t[0])
    for _, it in items:
        if it[0] == "head":
            head = q["head"]; up = unit(sub(head, q["neck"]))
            face = (0,0,1) if pose["view"]=="front" else ((-up[1], up[0], 0) if not pose["back"] else (up[1], -up[0], 0))
            (c, zc, k) = cam.project(head); c = scr(c); r = .1*s*k
            d.ellipse([c[0]-r,c[1]-r,c[0]+r,c[1]+r], fill=tint(SKIN, zc))
            def dirv(v):
                pp = scr(cam.project(add(head, mul(v, .1)))[0]); return ((pp[0]-c[0])/(.1*s*k), (pp[1]-c[1])/(.1*s*k))
            toward = max(-1, min(1, (cam.project(add(head, mul(face, .1)))[1]-zc)/.1))
            bf, bu = dirv(mul(face, -1)), dirv(up); w = .15 + .35*max(0, toward)
            hc = (c[0] + (bf[0]*.6 + bu[0]*w)*r, c[1] + (bf[1]*.6 + bu[1]*w)*r)
            m = Image.new("L", img.size, 0); ImageDraw.Draw(m).ellipse([c[0]-r*1.04,c[1]-r*1.04,c[0]+r*1.04,c[1]+r*1.04], fill=255)
            hl = Image.new("RGBA", img.size, (0,0,0,0)); ImageDraw.Draw(hl).ellipse([hc[0]-r,hc[1]-r,hc[0]+r,hc[1]+r], fill=HAIR+(255,))
            hl.putalpha(Image.fromarray(__import__("numpy").minimum(__import__("numpy").array(hl.getchannel("A")), __import__("numpy").array(m))))
            img.alpha_composite(hl); d = ImageDraw.Draw(img, "RGBA")
            side = unit(cross(up, face))
            nz = cam.project(sub(add(head, mul(face,.1)), mul(up,.012)))
            if nz[1] > zc+.01:
                n = scr(nz[0]); d.ellipse([n[0]-r*.2,n[1]-r*.2,n[0]+r*.2,n[1]+r*.2], fill=tint(SKIN, zc))
            for sg in (-1,1):
                e = cam.project(add(add(add(head, mul(face,.086)), mul(side,.036*sg)), mul(up,.012)))
                if e[1] > zc+.03:
                    p = scr(e[0]); rr = max(1.2, r*.1); d.ellipse([p[0]-rr,p[1]-rr,p[0]+rr,p[1]+rr], fill=(40,30,26))
            continue
        _, a,b,ra,rb,col = it
        (pa,za,ka),(pb,zb,kb) = cam.project(a), cam.project(b)
        d.polygon(capsule_poly(scr(pa), scr(pb), ra*s*ka, rb*s*kb), fill=tint(col, za), outline=None if col in (SHIRT, SHORTS) and ra > .08 else (0,0,0,60))

def main(out, ids):
    data = json.loads((ROOT/"assets"/"exercises.json").read_text()); lib = data["poses"]; by = {e["id"]: e for e in data["exercises"]}
    yaws = [0.0, 0.55, 1.2, 2.6]
    cell = 300
    rows = []
    for eid in ids:
        e = by[eid]
        for k in e["anim"]["k"][:2]:
            rows.append((e, k))
    img = Image.new("RGBA", (cell*len(yaws), cell*len(rows)), (15,17,21,255))
    for r,(e,k) in enumerate(rows):
        for c,yaw in enumerate(yaws):
            draw(img, resolve(k, lib), e["anim"].get("anchor","ground"), (c*cell, r*cell, (c+1)*cell, (r+1)*cell), yaw)
    img.convert("RGB").save(out); print(out)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
