#!/usr/bin/env python3
"""Fizyka sceny Formy — wzorzec dla lib/core/figure.dart (Scene): interpolacja klatek jak FigAnim.at,
rekwizyty (krzesło, ściana, drążek) w świecie, oparcie ciała o podłogę LUB krzesło, przypięcie podpory
(stopa, dłoń) w miejscu — bez „ślizgania” i przenikania. Plus kontrola fizyczności każdej klatki.

python3 tool/physics.py [id ...]     raport (kod wyjścia 1, gdy są błędy)
"""
import json
import math
import sys
from pathlib import Path

from check_motion import EXEMPT as _EX

# dłonie splecione za głową — łokcie na boki, w rzucie z boku wyglądają na „przeprost”
EXEMPT = dict(_EX, crunches="dłonie za głową", crunch_legs_up="dłonie za głową", sit_ups="dłonie za głową")
from figure import FORE, SHIN, THIGH, UPPER, full, joints, resolve, thickness

ROOT = Path(__file__).resolve().parent.parent

ANG = ("t", "h")
PAIR_ANG = ("an", "af", "ln", "lf")
LIN = ("fp", "lift", "x", "fold", "rot", "sp", "se", "tw")
SEAT_T = 0.05  # grubość siedziska (pod nim krzesło jest „puste”: nogi tylko w rogach)
LEG_W = 0.035  # nogi krzesła


def _ang(p, q, k):
    d = ((q - p + 540) % 360) - 180
    return p + d * k


def lerp(a, b, k):
    out = dict(a)
    for n in ANG:
        out[n] = _ang(a[n], b[n], k)
    for n in PAIR_ANG:
        out[n] = [_ang(a[n][i], b[n][i], k) for i in range(2)]
    for n in LIN:
        out[n] = a.get(n, 0) + (b.get(n, 0) - a.get(n, 0)) * k
    out["fq"] = [a["fq"][i] + (b["fq"][i] - a["fq"][i]) * k for i in range(2)]
    out["ab"] = [a["ab"][i] + (b["ab"][i] - a["ab"][i]) * k for i in range(4)]
    out["kr"] = [a["kr"][i] + (b["kr"][i] - a["kr"][i]) * k for i in range(2)]
    for n in ("view", "back", "kb"):
        out[n] = a.get(n) if k < 0.5 else b.get(n)
    return out


def at(keys, cycle, flow, seconds):
    """Jak FigAnim.at w lib/core/figure.dart."""
    n = len(keys)
    if n == 1:
        return keys[0]
    per = cycle / n
    t = seconds % cycle
    i = int(math.floor(t / per)) % n  # jak (t / per).floor() w Dart
    f = (t - i * per) / per
    if flow:
        p0, p1, p2, p3 = keys[(i - 1) % n], keys[i], keys[(i + 1) % n], keys[(i + 2) % n]
        a1, a2, a3 = lerp(p0, p1, f + 1), lerp(p1, p2, f), lerp(p2, p3, f - 1)
        return lerp(lerp(a1, a2, (f + 1) / 2), lerp(a2, a3, f / 2), f)
    hold = 0.22
    k = 0.0 if f < hold else (f - hold) / (1 - hold)
    e = 0.5 - math.cos(k * math.pi) / 2
    return lerp(keys[i], keys[(i + 1) % n], e)


# ------------------------------------------------------------------ scena

# Punkty, które mogą być podporą (kolejność = pierwszeństwo przy wyborze punktu przypiętego)
PIVOTS = ("toN", "toF", "anN", "anF", "haN", "haF", "knN", "knF", "hip", "neck", "head")
# Końce kończyn, które trzymamy w miejscu (dłoń, palce stopy) — dopasowanie kończyny (IK) co klatkę
ENDS = {"toN": ("hpN", "knN", "anN", THIGH, SHIN), "toF": ("hpF", "knF", "anF", THIGH, SHIN),
        "haN": ("shN", "elN", None, UPPER, FORE), "haF": ("shF", "elF", None, UPPER, FORE)}
LIMB_AB = {"haN": 0, "haF": 1, "toN": 2, "toF": 3}
EPS = 0.03


def _floor_drop(j, lift=0.0):
    low = max(v[1] + thickness(k) for k, v in j.items())
    return -low - lift


def _shift(j, dx, dy):
    return {k: (v[0] + dx, v[1] + dy) for k, v in j.items()}


def ik2(root, mid, target, l1, l2, back=False, arm=False):
    """Dwa odcinki od root do target. Zgięcie w stronę naturalną (kolano/łokieć zginają się, nie przeprostowują);
    gdy obie strony są możliwe — po tej samej stronie co w pozie. Zwraca (mid, koniec)."""
    dx, dy = target[0] - root[0], target[1] - root[1]
    d = math.hypot(dx, dy)
    d = min(max(d, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    base = math.atan2(dx, dy)  # kąt od pionu w dół, jak w figure.py
    phi = math.acos(max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    # kolano: zgięcie = udo „przed” goleń; łokieć odwrotnie (przedramię idzie do przodu)
    sgn = (-1 if back else 1) * (-1 if arm else 1)

    def sol(a):
        m = (root[0] + math.sin(a) * l1, root[1] + math.cos(a) * l1)
        tx, ty = target[0] - m[0], target[1] - m[1]
        n = math.hypot(tx, ty) or 1.0
        e = (m[0] + tx / n * l2, m[1] + ty / n * l2)
        flex = _rel_deg(math.degrees(a) - math.degrees(math.atan2(e[0] - m[0], e[1] - m[1]))) * sgn
        return m, e, flex

    s1, s2 = sol(base - phi), sol(base + phi)
    # zgięcie, nie przeprost; przy prawie prostej kończynie obie strony są „zgięciem” bliskim 0
    if s1[2] >= -1 and s2[2] < -1:
        return s1[:2]
    if s2[2] >= -1 and s1[2] < -1:
        return s2[:2]
    if s1[2] >= -1 and s2[2] >= -1:  # prawie prosta: lekko zgięta w stronę naturalną (bez losowości zaokrągleń)
        return (s1 if s1[2] >= s2[2] else s2)[:2]
    cross = dx * (mid[1] - root[1]) - dy * (mid[0] - root[0])
    return (s1 if cross > 0 else s2)[:2]


def _rel_deg(a):
    return (a + 180) % 360 - 180


def _phase(n, cycle, flow, seconds):
    """(klatka i, postęp 0…1 przejścia do następnej) — jak w FigAnim.at."""
    per = cycle / n
    t = seconds % cycle
    i = int(math.floor(t / per)) % n  # jak (t / per).floor() w Dart
    f = (t - i * per) / per
    if flow:
        return i, f
    hold = 0.22
    k = 0.0 if f < hold else (f - hold) / (1 - hold)
    return i, 0.5 - math.cos(k * math.pi) / 2


class Scene:
    """Świat ćwiczenia: rekwizyty z pierwszej klatki, jedna podpora przypięta w miejscu (x i y), dłonie i stopy
    opierające się w dwóch kolejnych klatkach trzymane na podporze (IK kończyny; gdy przestawiają się — krok
    łukiem nad podłogą), nic nie wchodzi w podłogę ani w krzesło."""

    def __init__(self, anim, lib):
        self.keys = [resolve(k, lib) for k in anim["k"]]
        self.cycle = anim.get("s", 2.0)
        self.flow = anim.get("flow", False)
        self.hands = anim.get("anchor") == "hands"
        self.fix = list(anim.get("fix", ()))
        raw = anim.get("props", [])
        self.has_chair = any(p.get("type") == "chair" for p in raw)
        first = self._floor_only(self.keys[0])
        self.props = []
        for p in raw:
            t = p.get("type")
            if t == "chair":
                pt = p.get("at", "haN")
                w = p.get("w", 0.4)
                x0 = first[pt][0] + p.get("dx", 0) - w / 2
                top = first[pt][1] + thickness(pt)  # punkt podparcia leży NA siedzisku, a nie w nim
                self.props.append(("chair", x0, x0 + w, top))
            elif t == "wall":
                if p.get("touch") == "back":
                    # ściana tuż za plecami (biodra, kark, głowa) w pierwszej klatce
                    x1 = min(first[k][0] - thickness(k) for k in ("hip", "neck", "head")) + p.get("dx", 0)
                    x = x1 - 0.04
                else:
                    x = first[p["at"]][0] + p.get("dx", 0) if "at" in p else p.get("x", -0.1)
                self.props.append(("wall", x, x + 0.04))
            elif t == "bar":
                self.props.append(("bar", first["haN"][1]))
        self.pivot, self.pin, self.world, self.ends, self.seg = None, None, [], {}, []
        # widok z przodu (pajacyki, przysiad sumo, deska bokiem): obie strony ruszają się symetrycznie —
        # bez przypinania jednej stopy, ciało tylko opada na podłogę
        front = all(k.get("view") == "front" for k in self.keys) and not anim.get("pin")
        if self.hands or anim.get("pin") == "none" or front:
            return
        dropped = [self._drop(joints(k), k) for k in self.keys]
        self.pinned_by_anim = bool(anim.get("pin"))
        if anim.get("pin"):
            self.pivot = anim["pin"]  # wskazany: opiera się w pierwszej klatce, w kolejnych trzymamy go w miejscu
        else:
            # podpora: punkt opierający się w każdej klatce, przy którym pozostałe takie punkty najmniej się przesuwają
            at = [p["at"] for p in raw if p.get("type") == "chair" and p.get("at")]
            # klatki w powietrzu (wyskok, lift) nie decydują o podporze
            ground = [j for j, k in zip(dropped, self.keys) if not k.get("lift")] or dropped
            always = [c for c in dict.fromkeys(["toN", "toF"] + at + list(PIVOTS))
                      if all(self._touching(j, c) for j in ground)]
            best = None
            for c in always:
                moved = 0.0
                for o in always:
                    xs = [j[o][0] - j[c][0] for j in ground]
                    moved += max(xs) - min(xs)
                if best is None or moved < best[0] - 1e-6:
                    best = (moved, c)
            if best:
                self.pivot = best[1]
                # deska: gdy stopy przestawiają się względem dłoni (wspinacz, wskok do przysiadu) — stoją dłonie
                hands = [c for c in ("haN", "haF") if c in always]
                if self.pivot in ("toN", "toF") and hands:
                    xs = [j[self.pivot][0] - j[hands[0]][0] for j in ground]
                    if max(xs) - min(xs) > 0.3:
                        self.pivot = hands[0]
        if not self.pivot:
            return
        self.pin = dropped[0][self.pivot]
        self.world = [self._pinned(j) for j in dropped]
        self._segment_pivots(dropped)
        side = all(k.get("view") != "front" for k in self.keys)
        if not side:
            return
        n = len(self.keys)
        for c, li in LIMB_AB.items():
            if all(c == p for p in self.seg) or any((k.get("ab") or [0] * 4)[li] for k in self.keys):
                continue
            if c[:2] == "to" and any((k.get("kr") or [0, 0])[0 if c[-1] == "N" else 1] for k in self.keys):
                continue
            if c in self.fix:
                flags = [True] * n
            else:
                # dłoń przy głowie (np. splecione za głową w brzuszkach) nie podpiera ciała
                flags = [not k.get("lift") and self._touching(j, c, 0.045) and not (c[:2] == "ha" and
                         math.hypot(j[c][0] - j["head"][0], j[c][1] - j["head"][1]) < 0.25)
                         for j, k in zip(self.world, self.keys)]
            if any(flags):
                self.ends[c] = self._anchors(c, flags)

    def _limb_change(self, c, a, b):
        """O ile stopni zmieniają się stawy kończyny c między pozami a i b (biodro+kolano / bark+łokieć)."""
        key = ("an" if c[-1] == "N" else "af") if c[:2] == "ha" else ("ln" if c[-1] == "N" else "lf")
        pa, pb = a[key], b[key]
        return (abs(_rel_deg((pa[0] - a["t"]) - (pb[0] - b["t"]))) +
                abs(_rel_deg((pa[0] - pa[1]) - (pb[0] - pb[1]))))

    def _segment_pivots(self, dropped):
        """Podpora w każdym przejściu. Domyślnie wspólna; gdy inna dłoń/stopa opiera się w obu klatkach, a jej
        stawy prawie się nie ruszają, podczas gdy kończyna podpory mocno pracuje (wyrzut nóg w burpee, wykrok) —
        stoi ta kończyna. Położenia klatek łączymy łańcuchowo; gdy cykl nie zamyka się (> 2 cm), wspólna podpora."""
        n = len(self.keys)
        self.seg = [self.pivot] * n
        if n < 2 or self.pinned_by_anim:
            return
        seg = list(self.seg)
        for i in range(n):
            b = (i + 1) % n
            ka, kb = self.keys[i], self.keys[b]
            if ka.get("lift") or kb.get("lift") or ka.get("view") == "front" or kb.get("view") == "front":
                continue
            cand = [c for c in ENDS if self._touching(dropped[i], c) and self._touching(dropped[b], c)]
            if not cand:
                continue
            pv = self.pivot
            if self._touching(dropped[i], pv) and self._touching(dropped[b], pv):
                if pv not in ENDS:
                    continue  # podpora na kolanach/biodrach/plecach zostaje
                base = self._limb_change(pv, ka, kb)
            else:
                base = 1e9
            c = min(cand, key=lambda c: self._limb_change(c, ka, kb))
            # przestawienie względem podpory > 30 cm: to nie drobna niezgodność póz, tylko prawdziwy przeskok
            rel = abs((dropped[b][c][0] - dropped[b][pv][0]) - (dropped[i][c][0] - dropped[i][pv][0]))
            # albo kończyna, która w ogóle nie pracuje (noga zakroczna w pompce spidermana)
            if base > 60 and (self._limb_change(c, ka, kb) < 0.5 * base and rel > 0.3 or
                              self._limb_change(c, ka, kb) < 15):
                seg[i] = c
        if seg == self.seg:
            return
        world = [self.world[0]]
        for i in range(n - 1):
            c = seg[i]
            world.append(_shift(dropped[i + 1], world[i][c][0] - dropped[i + 1][c][0], 0))
        c = seg[n - 1]
        if abs(world[n - 1][c][0] - world[0][c][0]) > 0.02:
            return
        self.seg, self.world = seg, world

    def _anchors(self, c, flags):
        """Punkt oparcia w każdej klatce (None = w powietrzu). Kolejne klatki z oparciem blisko siebie (< 15 cm)
        dzielą jeden punkt — dłoń/stopa stoi w miejscu, nawet gdy pozy kluczowe nie są idealnie zgrane."""
        n = len(flags)
        out = [None] * n
        if all(flags):
            starts = [0]
        else:
            starts = [i for i in range(n) if flags[i] and not flags[i - 1]]
        for st in starts:
            run, i = [], st
            while flags[i] and len(run) < n:
                run.append(i)
                i = (i + 1) % n
            base = self.world[st][c] if c not in self.fix else self.world[0][c]
            compact = c in self.fix or all(math.hypot(self.world[k][c][0] - base[0], self.world[k][c][1] - base[1]) < 0.15
                                           for k in run)
            for k in run:
                out[k] = base if compact else self.world[k][c]
        # w przejściach, w których c jest podporą, stoi dokładnie tam, gdzie przypięliśmy ciało
        for k, p in enumerate(self.seg):
            if p == c and out[k] is not None and out[(k + 1) % n] is not None:
                out[k] = out[(k + 1) % n] = self.world[k][c]
        return out

    def _pinned(self, j):
        """Przesunięcie całego ciała tak, by podpora była w miejscu z pierwszej klatki."""
        return _shift(j, self.pin[0] - j[self.pivot][0], self.pin[1] - j[self.pivot][1])

    # -- opuszczanie
    def _floor_only(self, pose):
        j = joints(pose)
        if self.hands:
            return _shift(j, 0, -2.3 - j["haN"][1])
        return _shift(j, 0, _floor_drop(j, pose.get("lift", 0)))

    def _support_y(self, k, x):
        """Wysokość powierzchni pod punktem (podłoga 0 albo siedzisko krzesła)."""
        y = 0.0
        for p in self.props:
            if p[0] == "chair" and p[1] - 0.01 <= x <= p[2] + 0.01:
                y = min(y, p[3])
        return y

    def _gap(self, j):
        return min(self._support_y(k, v[0]) - (v[1] + thickness(k)) for k, v in j.items())

    def _drop(self, j, pose):
        """Ciało opada pionowo, aż coś dotknie podłogi lub siedziska (lift tylko bez krzesła)."""
        if self.hands:
            return _shift(j, 0, -2.3 - j["haN"][1])
        lift = 0 if self.has_chair else pose.get("lift", 0)
        return _shift(j, 0, self._gap(j) - lift)

    def _touching(self, j, k, eps=EPS):
        v = j[k]
        return abs(self._support_y(k, v[0]) - (v[1] + thickness(k))) <= eps

    def target(self, c, i, e, raw=None):
        """Gdzie ma być dłoń/stopa c w przejściu klatka i → i+1 (postęp e); None = swobodnie (jak w pozie).
        raw: położenie z pozy — do płynnego oderwania od podpory i lądowania."""
        anc = self.ends.get(c)
        if not anc:
            return None
        n = len(anc)
        a, b = anc[i], anc[(i + 1) % n]
        if a is None and b is None:
            return None
        k = 0.5 - math.cos(math.pi * e) / 2
        if a is not None and b is not None:
            dist = math.hypot(b[0] - a[0], b[1] - a[1])
            x, y = a[0] + (b[0] - a[0]) * e, a[1] + (b[1] - a[1]) * e
            if dist > 0.03:  # przestawienie: krok łukiem zamiast sunięcia po podłodze
                y -= min(0.25, 0.4 * dist) * math.sin(math.pi * e)
            return x, y
        if raw is None:
            return a or b
        if a is not None:  # oderwanie: z punktu oparcia do ruchu z pozy
            x, y = a[0] + (raw[0] - a[0]) * k, a[1] + (raw[1] - a[1]) * k
            dist = abs(raw[0] - a[0])
        else:  # lądowanie
            x, y = raw[0] + (b[0] - raw[0]) * k, raw[1] + (b[1] - raw[1]) * k
            dist = abs(raw[0] - b[0])
        if dist > 0.03:  # przenoszenie nad podłogą, a nie szuranie
            y -= min(0.25, 0.4 * dist) * math.sin(math.pi * e)
        return x, y

    def frame_at(self, seconds):
        pose = at(self.keys, self.cycle, self.flow, seconds)
        j = joints(pose)
        if self.pivot is None:
            return pose, self._drop(j, pose)
        i, e = _phase(len(self.keys), self.cycle, self.flow, seconds)
        pv = self.seg[i]
        w = self.world[i][pv]
        j = _shift(j, w[0] - j[pv][0], w[1] - j[pv][1])
        lift = 0 if self.has_chair else pose.get("lift", 0)
        if lift:
            j = _shift(j, 0, -lift)
        elif self.ends and len(self.keys) > 1:
            j = dict(j)
            for c in self.ends:
                tgt = self.target(c, i, e, j[c]) if len(self.keys) > 1 else None
                if tgt is None:
                    continue
                root, mid, ank, l1, l2 = ENDS[c]
                if ank:  # stopa: palce na miejscu, stopa pod tym samym kątem co w pozie
                    fx, fy = j[c][0] - j[ank][0], j[c][1] - j[ank][1]
                    m, e2 = ik2(j[root], j[mid], (tgt[0] - fx, tgt[1] - fy), l1, l2, pose.get("back"))
                    j[mid], j[ank], j[c] = m, e2, (e2[0] + fx, e2[1] + fy)
                else:
                    m, e2 = ik2(j[root], j[mid], tgt, l1, l2, pose.get("back"), arm=True)
                    j[mid], j[c] = m, e2
            j = self._lift_free_limbs(j, pose, i, e)
        # nic nie może wejść w podłogę ani w siedzisko
        g = self._gap(j)
        if g < -0.002:
            j = _shift(j, 0, g)
        return pose, j

    def _lift_free_limbs(self, j, pose, i, e):
        """Noga lub ręka, która nie jest podporą, a w przejściu między klatkami weszłaby w podłogę/siedzisko:
        obracamy ją w biodrze/barku w górę o tyle, ile trzeba (reszta ciała bez zmian)."""
        j = dict(j)
        for c, (root, mid, ank, l1, l2) in ENDS.items():
            if c == (self.seg[i] if self.seg else self.pivot) or self._planted(c, i):
                continue
            li = LIMB_AB[c]
            if (pose.get("ab") or [0] * 4)[li] or (c[:2] == "to" and any(pose.get("kr") or [0, 0])):
                continue
            pts = [mid, ank, c] if ank else [mid, c]

            def pen(q):
                return max(q[k][1] + thickness(k) - self._support_y(k, q[k][0]) for k in pts)

            if pen(j) <= 0.003:
                continue
            r = j[root]

            def rot(q, deg):
                ca, sa = math.cos(math.radians(deg)), math.sin(math.radians(deg))
                out = dict(q)
                for k in pts:
                    x, y = q[k][0] - r[0], q[k][1] - r[1]
                    out[k] = (r[0] + x * ca - y * sa, r[1] + x * sa + y * ca)
                return out

            best = None
            for step in range(1, 121):
                for sg in (1, -1):
                    q = rot(j, sg * step)
                    if pen(q) <= -0.02:  # z zapasem — kończyna przechodzi nad podłogą, nie szoruje
                        best = q
                        break
                if best:
                    break
            if best:
                j = best
        return j

    def _planted(self, c, i):
        """Dłoń/stopa c opiera się w obu klatkach przejścia i → i+1."""
        anc = self.ends.get(c)
        return bool(anc) and anc[i] is not None and anc[(i + 1) % len(anc)] is not None

    def frame(self, pose):
        """Jedna poza bez fazy ruchu (tylko przypięcie i opuszczenie) — do ustawienia rekwizytów i podglądu."""
        j = joints(pose)
        if self.pivot is None:
            return self._drop(j, pose)
        return _shift(j, self.pin[0] - j[self.pivot][0], self.pin[1] - j[self.pivot][1])

    def samples(self, n=48):
        return [(i / n, self.frame_at(self.cycle * i / n)[1]) for i in range(n)]


# ------------------------------------------------------------------ kontrola

SEGS = [("hip", "neck", .1), ("neck", "head", .1), ("hpN", "knN", .07), ("knN", "anN", .05), ("hpF", "knF", .07),
        ("knF", "anF", .05), ("anN", "toN", .035), ("anF", "toF", .035), ("shN", "elN", .045), ("elN", "haN", .04),
        ("shF", "elF", .045), ("elF", "haF", .04)]


def _pts(j):
    for a, b, r in SEGS:
        for i in range(9):
            t = i / 8
            yield a, b, t, (j[a][0] + (j[b][0] - j[a][0]) * t, j[a][1] + (j[b][1] - j[a][1]) * t), r
    yield "head", "head", 0, j["head"], 0.1


def penetration(scene, j):
    """Najgłębsze wejście ciała w rekwizyt (m) i miejsce."""
    worst = (0.0, "")
    for p in scene.props:
        if p[0] == "chair":
            # miejsce oparcia (np. łopatki na krawędzi ławki) może się lekko „wcisnąć” — tkanki miękkie
            soft = j[scene.pivot] if scene.pivot and scene.pivot not in ("toN", "toF", "haN", "haF") else None
            # krzesło jak bryła od siedziska do podłogi (pod siedziskiem nie ma miejsca na ciało)
            x0, x1, top = p[1], p[2], p[3]
            for a, b, t, (x, y), r in _pts(j):
                d = min(x - (x0 - r), (x1 + r) - x, y - (top - r))
                if soft and math.hypot(x - soft[0], y - soft[1]) < 0.15:
                    d -= 0.04
                if d > worst[0]:
                    worst = (d, f"{a}-{b}@{t:.2f} w krześle")
        elif p[0] == "wall":
            x0, x1 = p[1], p[2]
            for a, b, t, (x, y), r in _pts(j):
                d = min(x - (x0 - r), (x1 + r) - x)
                if d > worst[0]:
                    worst = (d, f"{a}-{b}@{t:.2f} w ścianie")
    return worst


def check(ids=None, n=48, tol=0.025):
    data = json.loads((ROOT / "assets" / "exercises.json").read_text())
    out = []
    for e in data["exercises"]:
        if ids and e["id"] not in ids:
            continue
        sc = Scene(e["anim"], data["poses"])
        if not sc.props:
            continue
        worst = (0.0, "", 0)
        for f, j in sc.samples(n):
            d, where = penetration(sc, j)
            if d > worst[0]:
                worst = (d, where, f)
        if worst[0] > tol:
            out.append(f"{e['id']}: wchodzi w rekwizyt na {worst[0] * 100:.0f} cm ({worst[1]}, {worst[2]:.2f} cyklu)")
    return out


if __name__ == "__main__":
    probs = check(set(sys.argv[1:]) or None)
    for p in probs:
        print("BŁĄD", p)
    print(f"\n{len(probs)} problemów")
    sys.exit(1 if probs else 0)


# ------------------------------------------------------------------ kontrola całego ruchu (wszystkie ćwiczenia)

def _dir(a, b):
    return math.degrees(math.atan2(b[0] - a[0], b[1] - a[1]))


def _rel(a):
    a = (a + 180) % 360 - 180
    return 180 if a == -180 else a


def joint_angles(j, back):
    """Kąty zgięcia z położeń stawów (widok z boku): + = zgięcie, − = przeprost."""
    s = -1 if back else 1
    out = {}
    for sd in "NF":
        out["kolano" + sd] = _rel(_dir(j["hp" + sd], j["kn" + sd]) - _dir(j["kn" + sd], j["an" + sd])) * s
        out["łokieć" + sd] = _rel(_dir(j["el" + sd], j["ha" + sd]) - _dir(j["sh" + sd], j["el" + sd])) * s
    return out


def check_all(ids=None, n=48):
    data = json.loads((ROOT / "assets" / "exercises.json").read_text())
    rep = []
    for ex in data["exercises"]:
        if ids and ex["id"] not in ids:
            continue
        sc = Scene(ex["anim"], data["poses"])
        frames = [(f, sc.cycle * f) for f in (i / n for i in range(n))]
        worst = {}

        def note(kind, v, msg):
            if v > worst.get(kind, (0, ""))[0]:
                worst[kind] = (v, msg)

        prev = None
        for f, tsec in frames:
            pose, j = sc.frame_at(tsec)
            i, e = _phase(len(sc.keys), sc.cycle, sc.flow, tsec) if len(sc.keys) > 1 else (0, 0)
            d, where = penetration(sc, j) if sc.props else (0, "")
            note("rekwizyt", d, f"{where} ({f:.2f})")
            for c in sc.ends:
                tg = sc.target(c, i, e) if len(sc.keys) > 1 else None
                anc = sc.ends[c]
                if tg and anc[i] is not None and anc[(i + 1) % len(anc)] is not None:
                    note("kontakt", math.hypot(j[c][0] - tg[0], j[c][1] - tg[1]), f"{c} nie sięga podpory ({f:.2f})")
            side = pose.get("view") != "front" and not any(pose.get("ab") or []) and not any(pose.get("kr") or [])
            if side:
                for name, v in joint_angles(j, pose.get("back")).items():
                    if -150 < v < -10 and ex["id"] not in EXEMPT:  # przeprost (pełne zawinięcie ±180 to zgięcie)
                        note("przeprost", -v - 10, f"{name} {v:.0f}° ({f:.2f})")
            if not sc.hands and not pose.get("lift"):
                g = sc._gap(j)
                note("w powietrzu", g - 0.02, f"{g * 100:.0f} cm nad podłogą ({f:.2f})")
            if prev is not None and not sc.hands:
                for c in ("toN", "toF", "anN", "anF", "haN", "haF", "knN", "knF"):
                    if c == (sc.seg[i] if sc.seg else sc.pivot) or sc._planted(c, i):
                        continue
                    if sc._touching(prev, c, 0.015) and sc._touching(j, c, 0.015):
                        note("ślizg", abs(j[c][0] - prev[c][0]) - 0.01, f"{c} sunie po podłodze ({f:.2f})")
            prev = j
        lim = {"rekwizyt": 0.02, "kontakt": 0.03, "przeprost": 5, "w powietrzu": 0.01, "ślizg": 0.015}
        for k, (v, msg) in worst.items():
            if v > lim[k]:
                rep.append((ex["id"], k, v, msg))
    return rep


def reference(path, n=6):
    """Wzorcowe położenia stawów (physics.py) dla testu zgodności Dart ↔ Python (test/physics_test.dart)."""
    data = json.loads((ROOT / "assets" / "exercises.json").read_text())
    out = {}
    for ex in data["exercises"]:
        sc = Scene(ex["anim"], data["poses"])
        if sc.pivot is None and not sc.props:
            continue
        out[ex["id"]] = [[sc.cycle * i / n,
                          {k: [round(v[0], 5), round(v[1], 5)] for k, v in sc.frame_at(sc.cycle * i / n)[1].items()}]
                         for i in range(n)]
    Path(path).write_text(json.dumps(out, separators=(",", ":")))
    return len(out)
