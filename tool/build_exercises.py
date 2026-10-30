#!/usr/bin/env python3
"""Źródło bazy ćwiczeń Formy → assets/exercises.json.

Pozy opisują kąty szkieletu (patrz tool/figure.py). Tam, gdzie postać ma dotykać podłogi
dwoma punktami naraz (dłonie i stopy w podporze), kąt dobiera solver, żeby nic nie wisiało
w powietrzu ani nie wchodziło w podłogę.

Uruchom:  python3 tool/build_exercises.py && python3 tool/render_preview.py
"""
import json
from pathlib import Path

from figure import FOOT, SHIN, THIGH, full, grounded, joints

ROOT = Path(__file__).resolve().parent.parent


def solve(pose, setter, a, b, lo, hi, iters=60):
    """Dobiera parametr (setter(pose, v)) tak, by punkty a i b były na tej samej wysokości."""
    def f(v):
        p = dict(pose)
        setter(p, v)
        j = joints(full(p))
        return j[a][1] - j[b][1]

    flo, fhi = f(lo), f(hi)
    if flo * fhi > 0:
        raise SystemExit(f"solver: brak zmiany znaku dla {a}/{b} w [{lo},{hi}] ({flo:.3f}, {fhi:.3f})")
    for _ in range(iters):
        mid = (lo + hi) / 2
        fm = f(mid)
        if flo * fm <= 0:
            hi, fhi = mid, fm
        else:
            lo, flo = mid, fm
    p = dict(pose)
    setter(p, round((lo + hi) / 2, 1))
    return p


def set_body(p, t):
    """Ciało w jednej linii: tułów t, nogi przedłużają tułów."""
    p["t"] = t
    p["h"] = t + p.get("_dh", 0)
    p["ln"] = [t - 180, t - 180]
    p["lf"] = [t - 180, t - 180]


def set_t(p, t):
    p["t"] = t
    p["h"] = t + p.get("_dh", 0)


def set_legs(p, v):
    p["ln"] = [v, v]
    p["lf"] = [v, v]


def set_lf(p, v):
    p["lf"] = [v, v]


def set_arms_both(p, v):
    p["an"] = [v, v]
    p["af"] = [v, v]


def clean(p):
    return {k: v for k, v in p.items() if not k.startswith("_")}


P = {}

# ------------------------------------------------------------ stojące
P["stand"] = {}
P["stand_fwd"] = {"an": [90, 90], "af": [86, 86]}
P["stand_up"] = {"an": [172, 176], "af": [168, 172]}
P["jump_up"] = {"an": [168, 175], "af": [164, 170], "lift": 0.16, "ln": [4, 0], "lf": [-4, -2], "fp": -45}
P["squat_bot"] = {"t": 148, "an": [90, 90], "af": [86, 86], "ln": [80, -24], "lf": [77, -24]}
P["squat_mid"] = {"t": 162, "an": [70, 80], "af": [66, 76], "ln": [45, -20], "lf": [42, -20]}
P["squat_hands"] = solve({"t": 96, "h": 104, "ln": [86, -34], "lf": [84, -34]},
                         lambda p, v: (p.__setitem__("an", [v, v]), p.__setitem__("af", [v - 4, v - 4])),
                         "haN", "toN", 0, 89)
P["goblet_top"] = {"an": [15, 165], "af": [12, 162]}
P["goblet_bot"] = {"t": 150, "an": [30, 175], "af": [27, 172], "ln": [80, -24], "lf": [77, -24]}
P["calf_up"] = {"fp": -50, "an": [6, 10], "af": [-6, -2]}
P["high_knee"] = {"t": 176, "an": [-40, 25], "af": [45, 125], "ln": [100, 5], "lf": [0, 0], "fp": -25}
P["butt_kick"] = {"t": 176, "an": [-40, 25], "af": [45, 125], "ln": [-12, -165], "lf": [2, 0], "fp": -20}
P["march"] = {"an": [-25, 10], "af": [30, 60], "ln": [60, -5], "lf": [0, 0]}
P["lunge_down"] = {"t": 178, "an": [5, 5], "af": [-5, -5], "ln": [-25, -85], "lf": [80, -5]}
P["boxing_guard"] = {"t": 172, "an": [35, 155], "af": [30, 150], "ln": [12, -5], "lf": [-14, 0]}
P["boxing_punch"] = {"t": 168, "an": [88, 90], "af": [30, 150], "ln": [12, -5], "lf": [-14, 0]}
P["hinge"] = {"t": 102, "an": [0, 0], "af": [0, 0], "ln": [14, -6], "lf": [12, -6]}
P["hinge_hands_head"] = {"t": 100, "h": 106, "an": [140, -50], "af": [136, -54], "ln": [14, -6], "lf": [12, -6]}
P["stand_hands_head"] = {"an": [150, -40], "af": [146, -44]}
P["row_hang"] = {"t": 118, "an": [0, 0], "af": [0, 0], "ln": [28, -12], "lf": [26, -12]}
P["row_pull"] = {"t": 118, "an": [-110, 0], "af": [-106, 0], "ln": [28, -12], "lf": [26, -12]}
P["press_down"] = {"an": [70, 175], "af": [66, 172]}
P["press_up"] = {"an": [176, 178], "af": [173, 176]}
P["curl_up"] = {"an": [6, 160], "af": [4, 156]}
P["swing_back"] = {"t": 108, "an": [-18, -22], "af": [-20, -24], "ln": [22, -10], "lf": [20, -10]}
P["swing_up"] = {"t": 182, "an": [92, 92], "af": [90, 90], "ln": [2, 0], "lf": [-2, 0]}
P["band_row_out"] = {"an": [90, 90], "af": [86, 86], "ln": [10, 0], "lf": [-10, 0]}
P["band_row_in"] = {"an": [-28, 85], "af": [-32, 82], "ln": [10, 0], "lf": [-10, 0]}
P["quad_stretch"] = {"an": [-22, -14], "af": [20, 15], "ln": [-6, -170], "lf": [2, 0]}
P["arm_c0"] = {"an": [0, 0], "af": [0, 0]}
P["arm_c1"] = {"an": [90, 90], "af": [90, 90]}
P["arm_c2"] = {"an": [180, 180], "af": [180, 180]}
P["arm_c3"] = {"an": [270, 270], "af": [270, 270]}
P["fold"] = solve({"t": 12, "an": [30, 30], "af": [28, 28], "ln": [0, 0], "lf": [0, 0]},
                  set_arms_both, "haN", "toN", 0, 80)
P["step_on"] = {"an": [-15, 0], "af": [20, 15], "ln": [82, -8], "lf": [-4, 0]}
P["step_top"] = {"x": 0.42, "lift": 0.0, "an": [10, 10], "af": [-10, -5], "ln": [0, 0], "lf": [-14, -40], "_on": True}
P["split_top"] = {"t": 178, "an": [5, 5], "af": [-5, -5], "ln": [-35, -100], "lf": [25, -12]}
def _split_bot():
    """Tylna noga z IK: kostka zostaje na krześle, przednia stopa na podłodze."""
    import math
    top = joints(full(P["split_top"]))
    rel = (top["anN"][0] - top["anF"][0], top["anN"][1] - top["anF"][1])
    p = {"t": 172, "an": [5, 5], "af": [-5, -5], "lf": [82, -10], "ln": [0, 0]}
    j = joints(full(p))
    tx, ty = j["anF"][0] + rel[0] - j["hip"][0], j["anF"][1] + rel[1] - j["hip"][1]
    dist = min(math.hypot(tx, ty), THIGH + SHIN - 1e-3)
    base = math.degrees(math.atan2(tx, ty))  # kąt w konwencji figury
    cos_k = (THIGH ** 2 + dist ** 2 - SHIN ** 2) / (2 * THIGH * dist)
    off = math.degrees(math.acos(max(-1, min(1, cos_k))))
    cands = [base + off, base - off]
    thigh = max(cands, key=lambda a: math.cos(math.radians(a)))  # kolano niżej
    kx, ky = math.sin(math.radians(thigh)) * THIGH, math.cos(math.radians(thigh)) * THIGH
    shin = math.degrees(math.atan2(tx - kx, ty - ky))
    p["ln"] = [round(thigh, 1), round(shin, 1)]
    p["x"] = round(top["anF"][0] - j["anF"][0], 3)  # przednia stopa w tym samym miejscu
    return p


P["split_bot"] = _split_bot()
P["wall_sit"] = {"t": 180, "an": [10, 10], "af": [6, 6], "ln": [90, 0], "lf": [88, 0]}

# ------------------------------------------------------------ podpory
pu = solve({"an": [0, 0], "af": [0, 0], "_dh": 4}, set_body, "haN", "toN", 92, 130)
P["pushup_top"] = clean(pu)
pd = solve({"an": [-108, 8], "af": [-110, 8], "_dh": 3}, set_body, "haN", "toN", 88, 125)
P["pushup_bot"] = clean(pd)
kt = solve({"an": [0, 0], "af": [0, 0], "_dh": 4}, set_t, "haN", "knN", 92, 150)
kt = dict(kt)
kt["ln"] = [kt["t"] - 180, -95]
kt["lf"] = [kt["t"] - 180, -95]
P["kpush_top"] = clean(solve(kt, lambda p, v: (p.__setitem__("t", v), p.__setitem__("h", v + 4),
                                               p.__setitem__("ln", [v - 180, -95]),
                                               p.__setitem__("lf", [v - 180, -95])), "haN", "knN", 92, 150))
P["kpush_bot"] = clean(solve({"an": [-122, 12], "af": [-124, 12]},
                             lambda p, v: (p.__setitem__("t", v), p.__setitem__("h", v + 3),
                                           p.__setitem__("ln", [v - 180, -95]),
                                           p.__setitem__("lf", [v - 180, -95])), "haN", "knN", 85, 140))
P["plank"] = clean(solve({"an": [0, 90], "af": [0, 90], "_dh": 4}, set_body, "elN", "toN", 88, 120))
P["plank_b"] = dict(P["plank"], h=P["plank"]["t"] + 10)
tap = dict(P["pushup_top"])
tap["an"] = [35, -150]
P["tap"] = tap
mc = dict(P["pushup_top"])
mc["ln"] = [62, -55]
P["climber"] = mc
P["pike_top"] = clean(solve({"t": 40, "h": 30, "an": [42, 42], "af": [42, 42]}, set_legs, "haN", "toN", -10, -80))
P["pike_bot"] = clean(solve({"t": 30, "h": 20, "an": [-60, 30], "af": [-62, 30]}, set_legs, "haN", "toN", -5, -80))
P["dog"] = clean(solve({"t": 35, "h": 20, "an": [35, 35], "af": [35, 35]}, set_legs, "haN", "toN", -10, -80))

# czworakowanie: dłonie pod barkami, kolana pod biodrami
quad = solve({"an": [0, 0], "af": [0, 0], "ln": [0, -90], "lf": [0, -90]}, set_t, "haN", "knN", 92, 140)
P["quad"] = clean(quad)
P["cat"] = dict(P["quad"], h=quad["t"] - 55)
P["cow"] = dict(P["quad"], h=quad["t"] + 35)
P["donkey"] = dict(P["quad"], ln=[-105, 175])
P["birddog"] = dict(P["quad"], an=[92, 92], ln=[-92, -92])

# ------------------------------------------------------------ leżenie na plecach (głowa w prawo)
SUP = {"t": 90, "h": 90, "back": True, "an": [-88, -88], "af": [-90, -90]}
P["bridge_down"] = dict(SUP, ln=[-140, -32], lf=[-142, -32])
P["bridge_up"] = dict(SUP, t=66, h=86, an=[-78, -78], af=[-80, -80], ln=[-114, -30], lf=[-116, -30])
P["sbridge_down"] = dict(SUP, ln=[-140, -140], lf=[-142, -32])
P["sbridge_up"] = dict(SUP, t=66, h=86, an=[-78, -78], af=[-80, -80], ln=[-114, -114], lf=[-116, -30])
P["crunch_down"] = dict(SUP, an=[160, -30], af=[158, -32], ln=[-140, -32], lf=[-142, -32])
P["crunch_up"] = dict(SUP, t=118, h=124, an=[-118, -118], af=[-120, -120], ln=[-140, -32], lf=[-142, -32])
P["bike"] = dict(SUP, t=108, h=112, an=[150, -40], af=[148, -42], ln=[148, -95], lf=[-104, -104])
P["legs_low"] = dict(SUP, ln=[-96, -96], lf=[-97, -97])
P["legs_high"] = dict(SUP, ln=[-172, -172], lf=[-173, -173])
P["flutter"] = dict(SUP, t=100, h=106, ln=[-100, -100], lf=[-112, -112])
P["bug_base"] = dict(SUP, an=[180, 180], af=[178, 178], ln=[180, -90], lf=[178, -92])
P["bug_ext"] = dict(SUP, an=[96, 96], af=[178, 178], ln=[180, -90], lf=[-100, -100])
P["hollow"] = dict(SUP, t=100, h=108, an=[104, 104], af=[106, 106], ln=[-104, -104], lf=[-105, -105])
P["hollow_b"] = dict(P["hollow"], t=102, h=110, ln=[-106, -106], lf=[-107, -107])
P["knee_hug"] = dict(SUP, t=100, h=110, an=[150, -110], af=[148, -112], ln=[150, -120], lf=[148, -122])
P["supine_flat"] = dict(SUP, an=[100, 100], af=[100, 100], ln=[-92, -92], lf=[-92, -92])

# ------------------------------------------------------------ leżenie przodem
PRONE = {"t": 90, "h": 90, "ln": [-90, -90], "lf": [-90, -90]}
P["prone"] = dict(PRONE, an=[92, 92], af=[92, 92])
P["superman"] = dict(PRONE, t=100, h=106, an=[106, 106], af=[106, 106], ln=[-100, -100], lf=[-100, -100])
P["cobra_down"] = dict(PRONE, h=95, an=[-150, 20], af=[-152, 20])
P["cobra_up"] = clean(solve(dict(PRONE, t=128, h=140, an=[-20, 0], af=[-20, 0]),
                            lambda p, v: (p.__setitem__("an", [-20, v]), p.__setitem__("af", [-22, v])),
                            "haN", "hip", 0, 89))

# ------------------------------------------------------------ siad / klęk
P["sit_up"] = {"t": 180, "an": [95, 95], "af": [93, 93], "ln": [90, 90], "lf": [90, 90], "fp": 20}
P["sit_fold"] = {"t": 118, "h": 110, "an": [100, 100], "af": [98, 98], "ln": [90, 90], "lf": [90, 90], "fp": 20}
P["vsit_a"] = {"t": -150, "h": -158, "an": [70, 110], "af": [80, 140], "ln": [130, 62], "lf": [128, 60]}
P["vsit_b"] = {"t": -150, "h": -142, "an": [80, 140], "af": [70, 110], "ln": [130, 62], "lf": [128, 60]}
P["child"] = {"t": 70, "h": 60, "an": [92, 92], "af": [90, 90], "ln": [62, -90], "lf": [60, -90]}
P["kneel_lunge"] = clean(solve({"t": 180, "an": [172, 176], "af": [168, 172], "lf": [-18, -90]},
                               lambda p, v: p.__setitem__("ln", [v, 0]), "anN", "knF", 40, 120))
P["dip_up"] = {"t": 180, "an": [-16, -16], "af": [-18, -18], "ln": [86, 0], "lf": [84, 0]}
P["dip_down"] = {"t": 178, "an": [-58, 2], "af": [-60, 2], "ln": [70, 4], "lf": [68, 4]}
_it = {"an": [0, 0], "af": [0, 0], "_dh": 4}
set_body(_it, 130)
P["incline_top"] = clean(_it)
_top_j = joints(full(_it))
_hand_h = _top_j["haN"][1] - _top_j["toN"][1]  # wysokość dłoni (krzesła) nad stopami


def _incline_bot(p, t):
    set_body(p, t)


def _solve_incline():
    lo, hi = 100.0, 140.0
    for _ in range(60):
        mid = (lo + hi) / 2
        p = {"an": [-118, 18], "af": [-120, 18], "_dh": 3}
        set_body(p, mid)
        j = joints(full(p))
        if (j["haN"][1] - j["toN"][1]) - _hand_h > 0:
            lo = mid
        else:
            hi = mid
    p = {"an": [-118, 18], "af": [-120, 18], "_dh": 3}
    set_body(p, round((lo + hi) / 2, 1))
    return clean(p)


P["incline_bot"] = _solve_incline()

# ------------------------------------------------------------ zwis
P["hang"] = {"an": [180, 180], "af": [178, 178], "ln": [-4, -22], "lf": [-6, -24]}
P["pull_top"] = {"an": [18, 172], "af": [16, 170], "ln": [-4, -22], "lf": [-6, -24]}
P["hang_knees"] = {"an": [180, 180], "af": [178, 178], "ln": [92, 0], "lf": [90, 0]}

# ------------------------------------------------------------ widok z przodu
FR = {"view": "front"}
P["jack_in"] = dict(FR, an=[6, 4], af=[6, 4], ln=[2, 2], lf=[2, 2])
P["jack_out"] = dict(FR, an=[150, 162], af=[150, 162], ln=[18, 18], lf=[18, 18], lift=0.05)
P["sumo_top"] = dict(FR, an=[10, -120], af=[10, -120], ln=[20, 16], lf=[20, 16])
P["sumo_bot"] = dict(FR, an=[10, -120], af=[10, -120], ln=[66, 12], lf=[66, 12])
P["side_lunge"] = dict(FR, t=172, an=[10, -120], af=[10, -120], ln=[52, 0], lf=[36, 36])
P["front_stand"] = dict(FR, an=[10, -120], af=[10, -120], ln=[12, 12], lf=[12, 12])
P["skater"] = dict(FR, t=168, an=[-35, -30], af=[70, 75], ln=[22, -2], lf=[-28, -50])
P["side_bend"] = dict(FR, t=162, h=158, an=[20, 10], af=[160, 140], ln=[6, 6], lf=[6, 6])
P["pull_apart_in"] = dict(FR, an=[48, -92], af=[48, -92], ln=[8, 8], lf=[8, 8])
P["pull_apart_out"] = dict(FR, an=[92, 92], af=[92, 92], ln=[8, 8], lf=[8, 8])
P["lateral_up"] = dict(FR, an=[88, 90], af=[88, 90], ln=[6, 6], lf=[6, 6])
P["lateral_down"] = dict(FR, an=[12, 8], af=[12, 8], ln=[6, 6], lf=[6, 6])
def _sp(p, t):
    p["t"] = t
    p["h"] = t
    p["ln"] = [t - 180, t - 180]
    p["lf"] = [180 - t, 180 - t]


P["side_plank"] = clean(solve(dict(FR, an=[0, 92], af=[-6, -4]), _sp, "elN", "toN", 92, 140))
P["side_plank_up"] = dict(P["side_plank"], af=[-178, -178])
P["side_lying"] = dict(FR, t=90, h=96, an=[100, 180], af=[84, 84], ln=[-92, -92], lf=[92, 92])
P["side_lying_up"] = dict(P["side_lying"], lf=[128, 128])

for k, v in list(P.items()):
    P[k] = clean(v)

# wejście na krzesło: na górze stopa stoi na wysokości krzesła z pierwszej pozy
_chair_top = -grounded(P["step_on"])["toN"][1]
P["step_top"]["lift"] = round(_chair_top, 3)
_chair_x = grounded(P["step_on"])["anN"][0]
P["step_top"]["x"] = round(_chair_x, 3)

# ------------------------------------------------------------ ćwiczenia
# typ: warmup | cardio | strength | core | mobility | stretch
# eq: [] = bez sprzętu; db hantle, kb kettlebell, band guma, bar drążek, chair krzesło/ławka
# stress: kolana / plecy / nadgarstki / barki — pomijane przy zgłoszonych ograniczeniach
# s: sekundy na cykl animacji (≈ jedno powtórzenie)

def ex(id, name, typ, groups, lvl, met, keys, s=2.0, eq=(), impact=False, uni=False,
       stress=(), tips=(), hold=None, props=None, anchor=None, easier=None, harder=None, static=False):
    a = {"k": list(keys), "s": s}
    if anchor:
        a["anchor"] = anchor
    if props:
        a["props"] = props
    e = {"id": id, "name": name, "type": typ, "groups": list(groups), "lvl": lvl, "met": met,
         "eq": list(eq), "anim": a}
    if impact:
        e["impact"] = True
    if uni:
        e["uni"] = True
    if static:
        e["static"] = True
    if stress:
        e["stress"] = list(stress)
    if tips:
        e["tips"] = list(tips)
    if hold:
        e["hold"] = hold
    if easier:
        e["easier"] = easier
    if harder:
        e["harder"] = harder
    return e


CHAIR_H = [{"type": "chair", "at": "haN", "w": 0.42, "dx": -0.12}]
E = [
    # --- rozgrzewka / kardio
    ex("jumping_jacks", "Pajacyki", "cardio", ["całe ciało"], 1, 8.0, ["jack_in", "jack_out"], 0.9,
       impact=True, stress=["kolana"], tips=["Ląduj miękko na przedniej części stopy", "Ręce prawie proste"],
       easier="step_jacks"),
    ex("step_jacks", "Pajacyki bez skoku", "warmup", ["całe ciało"], 1, 4.0,
       ["jack_in", dict(P["jack_out"], lift=0, ln=[2, 2], lf=[22, 22]), "jack_in",
        dict(P["jack_out"], lift=0, ln=[22, 22], lf=[2, 2])], 1.4,
       tips=["Na zmianę odstawiaj nogę w bok", "Ręce nad głowę przy każdym kroku"], harder="jumping_jacks"),
    ex("march", "Marsz w miejscu", "warmup", ["nogi"], 1, 3.5, ["march", "stand", "march~", "stand"], 1.2,
       tips=["Kolana do wysokości bioder", "Pracuj rękami jak przy marszu"], harder="high_knees"),
    ex("high_knees", "Wysokie kolana", "cardio", ["nogi", "brzuch"], 2, 8.0, ["high_knee", "high_knee~"], 0.6,
       impact=True, stress=["kolana"], tips=["Kolana co najmniej do bioder", "Tułów wyprostowany"],
       easier="march"),
    ex("butt_kicks", "Skip C (pięty do pośladków)", "cardio", ["nogi"], 2, 7.0, ["butt_kick", "butt_kick~"], 0.6,
       impact=True, stress=["kolana"], tips=["Pięty dotykają pośladków", "Biegnij na przedniej części stopy"]),
    ex("arm_circles", "Krążenia ramion", "warmup", ["barki"], 1, 2.8, ["arm_c0", "arm_c1", "arm_c2", "arm_c3"], 2.0,
       tips=["Duże, spokojne koła", "W połowie czasu zmień kierunek"]),
    ex("shadow_boxing", "Boks w miejscu", "cardio", ["barki", "ramiona", "brzuch"], 1, 6.0,
       ["boxing_guard", "boxing_punch", "boxing_guard", "boxing_punch~"], 1.0,
       tips=["Gardę trzymaj przy brodzie", "Skręcaj biodro przy ciosie"]),
    ex("mountain_climbers", "Wspinaczka", "cardio", ["brzuch", "barki", "nogi"], 2, 8.0,
       ["climber", "pushup_top", "climber~", "pushup_top"], 0.8, stress=["nadgarstki"],
       tips=["Biodra nisko, w linii z barkami", "Kolano energicznie do klatki"]),
    ex("burpees", "Burpees", "cardio", ["całe ciało"], 4, 10.0,
       ["stand", "squat_hands", "pushup_top", "squat_hands", "jump_up"], 3.0, impact=True,
       stress=["kolana", "nadgarstki"], tips=["Plecy proste przy przejściu do podporu", "Ląduj miękko"],
       easier="squat_thrust"),
    ex("squat_thrust", "Przysiad z wyrzutem nóg (bez skoku)", "cardio", ["całe ciało"], 2, 6.0,
       ["stand", "squat_hands", "pushup_top", "squat_hands"], 3.0, stress=["nadgarstki"],
       tips=["Nogi odstawiaj po jednej, jeśli trzeba", "Brzuch napięty w podporze"], harder="burpees"),
    ex("jump_squats", "Przysiady z wyskokiem", "cardio", ["nogi", "pośladki"], 3, 9.0,
       ["squat_bot", "jump_up", "stand"], 1.6, impact=True, stress=["kolana"],
       tips=["Wyląduj miękko i od razu zejdź do przysiadu", "Kolana nad palcami"], easier="squat"),
    ex("skaters", "Łyżwiarz", "cardio", ["nogi", "pośladki"], 3, 7.5, ["skater", "front_stand", "skater~", "front_stand"],
       1.4, impact=True, stress=["kolana"], tips=["Skacz w bok i ląduj na jednej nodze", "Biodro nisko"]),
    ex("inchworm", "Gąsienica", "warmup", ["całe ciało"], 2, 4.0, ["stand", "fold", "pushup_top", "fold"], 4.0,
       stress=["nadgarstki"], tips=["Dłońmi przejdź do podporu", "Kolana możesz lekko ugiąć"]),

    # --- nogi i pośladki
    ex("squat", "Przysiad", "strength", ["nogi", "pośladki"], 1, 5.0, ["stand_fwd", "squat_bot"], 2.6,
       stress=["kolana"], tips=["Ciężar na piętach", "Kolana w linii ze stopami", "Plecy proste"],
       harder="jump_squats"),
    ex("sumo_squat", "Przysiad sumo", "strength", ["nogi", "pośladki"], 1, 5.0, ["sumo_top", "sumo_bot"], 2.6,
       stress=["kolana"], tips=["Stopy szeroko, palce na zewnątrz", "Kolana wypychaj na boki"]),
    ex("reverse_lunge", "Wykroki w tył", "strength", ["nogi", "pośladki"], 2, 5.0,
       ["stand", "lunge_down", "stand", "lunge_down~"], 4.0, stress=["kolana"],
       tips=["Kolano przedniej nogi nad kostką", "Tylne kolano prawie dotyka podłogi"]),
    ex("side_lunge", "Wykroki w bok", "strength", ["nogi", "pośladki"], 2, 5.0,
       ["front_stand", "side_lunge", "front_stand", "side_lunge~"], 4.0, stress=["kolana"],
       tips=["Biodra w tył jak przy przysiadzie", "Druga noga prosta"]),
    ex("glute_bridge", "Mostek biodrowy", "strength", ["pośladki", "plecy"], 1, 3.5,
       ["bridge_down", "bridge_up"], 2.4, tips=["Wypchnij biodra, ściśnij pośladki", "Nie przeprostuj lędźwi"],
       harder="single_leg_bridge"),
    ex("single_leg_bridge", "Mostek na jednej nodze", "strength", ["pośladki", "plecy"], 3, 4.0,
       ["sbridge_down", "sbridge_up"], 2.4, uni=True,
       tips=["Biodra równo, nie przechylaj miednicy", "Wolna noga w linii z udem"], easier="glute_bridge"),
    ex("wall_sit", "Krzesełko przy ścianie", "strength", ["nogi"], 2, 4.0, ["wall_sit", dict(P["wall_sit"], h=182)],
       3.0, static=True, stress=["kolana"], props=[{"type": "wall", "x": -0.06}],
       tips=["Uda równolegle do podłogi", "Plecy płasko przy ścianie"]),
    ex("calf_raises", "Wspięcia na palce", "strength", ["nogi"], 1, 3.0, ["stand", "calf_up"], 1.8,
       tips=["Zatrzymaj się na górze na sekundę", "Opuszczaj powoli"]),
    ex("donkey_kicks", "Kopnięcia w tył w klęku", "strength", ["pośladki"], 1, 3.5, ["quad", "donkey"], 1.8, uni=True,
       stress=["nadgarstki"], tips=["Stopa wypycha sufit", "Nie wyginaj lędźwi"]),
    ex("good_morning", "Skłon „dzień dobry”", "strength", ["plecy", "pośladki"], 1, 3.5,
       ["stand_hands_head", "hinge_hands_head"], 2.8, stress=["plecy"],
       tips=["Biodra w tył, plecy proste", "Kolana lekko ugięte"]),
    ex("step_ups", "Wejścia na krzesło", "strength", ["nogi", "pośladki"], 2, 6.0, ["step_on", "step_top"], 2.4,
       uni=True, eq=["chair"], stress=["kolana"], props=[{"type": "chair", "at": "toN", "w": 0.4, "dx": -0.12}],
       tips=["Wchodź siłą nogi na krześle", "Stabilne krzesło przy ścianie"]),
    ex("split_squat", "Przysiad bułgarski", "strength", ["nogi", "pośladki"], 3, 6.0, ["split_top", "split_bot"],
       3.0, uni=True, eq=["chair"], stress=["kolana"],
       props=[{"type": "chair", "at": "toN", "w": 0.4, "dx": -0.1}],
       tips=["Tylna stopa na krześle", "Schodź pionowo w dół"]),
    ex("side_leg_raise", "Unoszenie nogi w leżeniu bokiem", "strength", ["pośladki"], 1, 3.0,
       ["side_lying", "side_lying_up"], 2.0, uni=True, tips=["Noga prosta, palce do przodu", "Nie odchylaj bioder"]),

    # --- góra ciała
    ex("pushups", "Pompki", "strength", ["klatka", "ramiona", "barki"], 3, 5.0, ["pushup_top", "pushup_bot"], 2.4,
       stress=["nadgarstki", "barki"], tips=["Ciało w jednej linii", "Łokcie ok. 45° od tułowia"],
       easier="knee_pushups"),
    ex("knee_pushups", "Pompki na kolanach", "strength", ["klatka", "ramiona"], 1, 3.8, ["kpush_top", "kpush_bot"], 2.4,
       stress=["nadgarstki"], tips=["Linia od kolan do głowy", "Klatka nisko nad podłogę"], harder="pushups"),
    ex("incline_pushups", "Pompki z rękami na krześle", "strength", ["klatka", "ramiona"], 1, 4.0,
       ["incline_top", "incline_bot"], 2.4, eq=["chair"], props=CHAIR_H,
       tips=["Krzesło oparte o ścianę", "Ciało proste jak deska"], harder="pushups"),
    ex("pike_pushups", "Pompki w pozycji V", "strength", ["barki", "ramiona"], 4, 5.0, ["pike_top", "pike_bot"], 2.6,
       stress=["nadgarstki", "barki"], tips=["Biodra wysoko", "Głowa schodzi między dłonie"], easier="pushups"),
    ex("triceps_dips", "Pompki w podporze tyłem", "strength", ["ramiona", "barki"], 2, 4.5, ["dip_up", "dip_down"],
       2.4, eq=["chair"], stress=["barki"], props=[{"type": "chair", "at": "haN", "w": 0.42, "dx": -0.2}],
       tips=["Łokcie do tyłu, nie na boki", "Plecy blisko krzesła"]),
    ex("shoulder_taps", "Deska z dotykaniem barków", "core", ["brzuch", "barki"], 2, 4.5,
       ["pushup_top", "tap", "pushup_top", "tap~"], 1.6, stress=["nadgarstki"],
       tips=["Biodra nieruchomo", "Stopy szerzej = łatwiej"]),
    ex("superman", "Superman", "strength", ["plecy"], 1, 3.0, ["prone", "superman"], 2.4,
       tips=["Unieś ręce i nogi jednocześnie", "Patrz w podłogę"]),

    # --- brzuch
    ex("plank", "Deska", "core", ["brzuch"], 1, 3.8, ["plank", "plank_b"], 3.0, static=True,
       tips=["Ciało w jednej linii", "Napnij pośladki i brzuch"]),
    ex("side_plank", "Deska bokiem", "core", ["brzuch"], 2, 3.8, ["side_plank", "side_plank_up"], 3.0,
       static=True, uni=True, stress=["barki"], tips=["Biodra wysoko", "Łokieć pod barkiem"]),
    ex("crunches", "Brzuszki", "core", ["brzuch"], 1, 3.8, ["crunch_down", "crunch_up"], 2.0,
       tips=["Unoś tylko łopatki", "Nie ciągnij głowy rękami"]),
    ex("bicycle", "Rowerek", "core", ["brzuch"], 2, 4.5, ["bike", "bike~"], 1.6,
       tips=["Łokieć do przeciwnego kolana", "Lędźwie przy podłodze"]),
    ex("leg_raises", "Unoszenie nóg", "core", ["brzuch"], 2, 4.0, ["legs_low", "legs_high"], 2.6, stress=["plecy"],
       tips=["Lędźwie dociśnięte do podłogi", "Opuszczaj powoli"]),
    ex("flutter_kicks", "Nożyce", "core", ["brzuch"], 2, 4.0, ["flutter", "flutter~"], 0.8, stress=["plecy"],
       tips=["Nogi nisko, ale nad podłogą", "Krótkie, szybkie ruchy"]),
    ex("dead_bug", "Martwy robak", "core", ["brzuch"], 1, 3.5, ["bug_base", "bug_ext", "bug_base", "bug_ext~"], 3.6,
       tips=["Lędźwie przyklejone do podłogi", "Wydech przy wyproście"]),
    ex("hollow_hold", "Łódka", "core", ["brzuch"], 3, 4.0, ["hollow", "hollow_b"], 3.0, static=True,
       stress=["plecy"], tips=["Lędźwie przy podłodze", "Ręce i nogi nisko = trudniej"]),
    ex("russian_twist", "Rosyjski skręt", "core", ["brzuch"], 2, 4.0, ["vsit_a", "vsit_b"], 1.4, stress=["plecy"],
       tips=["Skręcaj tułów, nie tylko ręce", "Stopy mogą zostać na podłodze"]),
    ex("bird_dog", "Bird-dog", "core", ["brzuch", "plecy"], 1, 3.0, ["quad", "birddog", "quad", "birddog~"], 3.6,
       stress=["nadgarstki"], tips=["Przeciwna ręka i noga", "Miednica nie opada na bok"]),

    # --- mobilność i rozciąganie
    ex("cat_cow", "Koci grzbiet", "mobility", ["plecy"], 1, 2.5, ["cat", "cow"], 4.0, stress=["nadgarstki"],
       tips=["Ruch płynny, z oddechem", "Wydech przy zaokrągleniu"]),
    ex("childs_pose", "Pozycja dziecka", "stretch", ["plecy"], 1, 2.0, ["child", dict(P["child"], t=72)], 5.0,
       static=True, tips=["Pośladki do pięt", "Oddychaj spokojnie"]),
    ex("cobra", "Kobra", "stretch", ["brzuch", "plecy"], 1, 2.3, ["cobra_down", "cobra_up"], 4.0, stress=["plecy"],
       tips=["Biodra na podłodze", "Barki daleko od uszu"]),
    ex("down_dog", "Pies z głową w dół", "stretch", ["nogi", "barki"], 1, 2.5, ["dog", dict(P["dog"], t=P["dog"]["t"] - 3)],
       4.0, static=True, stress=["nadgarstki"], tips=["Pięty w stronę podłogi", "Plecy długie"]),
    ex("hamstring_stretch", "Skłon w siadzie", "stretch", ["nogi", "plecy"], 1, 2.3, ["sit_up", "sit_fold"], 5.0,
       static=True, tips=["Pochylaj się z bioder", "Kolana lekko ugięte, jeśli ciągnie"]),
    ex("quad_stretch", "Rozciąganie przodu uda", "stretch", ["nogi"], 1, 2.3,
       ["quad_stretch", dict(P["quad_stretch"], t=178)], 5.0, static=True, uni=True,
       tips=["Kolana razem", "Możesz przytrzymać się ściany"]),
    ex("hip_flexor_stretch", "Rozciąganie zginaczy bioder", "stretch", ["nogi", "pośladki"], 1, 2.3,
       ["kneel_lunge", dict(P["kneel_lunge"], t=176)], 5.0, static=True, uni=True, stress=["kolana"],
       tips=["Pośladek tylnej nogi napięty", "Biodra lekko do przodu"]),
    ex("knee_hug", "Kolana do klatki", "stretch", ["plecy"], 1, 2.0, ["knee_hug", dict(P["knee_hug"], t=96)], 4.0,
       static=True, tips=["Rozluźnij kark", "Delikatnie kołysz się na boki"]),
    ex("side_bend", "Skłony boczne", "mobility", ["brzuch"], 1, 2.5,
       [dict(P["side_bend"], t=180, h=180, af=[90, 120]), "side_bend", dict(P["side_bend"], t=180, h=180, af=[90, 120]),
        "side_bend~"], 4.0, tips=["Nie pochylaj się do przodu", "Ręka sięga daleko w bok"]),
    ex("deep_squat_hold", "Głęboki przysiad z rozciąganiem", "mobility", ["nogi", "pośladki"], 2, 2.5,
       ["squat_bot", dict(P["squat_bot"], t=152)], 4.0, static=True, stress=["kolana"],
       tips=["Pięty na podłodze", "Łokciami rozpychaj kolana"]),

    # --- ze sprzętem
    ex("goblet_squat", "Przysiad goblet", "strength", ["nogi", "pośladki"], 2, 5.5, ["goblet_top", "goblet_bot"], 2.8,
       eq=["db|kb"], hold="db", stress=["kolana"], tips=["Ciężar przy klatce", "Łokcie między kolanami na dole"]),
    ex("db_row", "Wiosłowanie hantlami", "strength", ["plecy", "ramiona"], 2, 5.0, ["row_hang", "row_pull"], 2.4,
       eq=["db"], hold="db", stress=["plecy"], tips=["Plecy proste", "Łokcie prowadź blisko tułowia"]),
    ex("db_press", "Wyciskanie hantli nad głowę", "strength", ["barki", "ramiona"], 2, 5.0, ["press_down", "press_up"],
       2.4, eq=["db"], hold="db", stress=["barki"], tips=["Nie wyginaj lędźwi", "Wydech przy wyciskaniu"]),
    ex("db_curl", "Uginanie ramion z hantlami", "strength", ["ramiona"], 1, 3.5, ["stand", "curl_up"], 2.4,
       eq=["db"], hold="db", tips=["Łokcie przy tułowiu", "Opuszczaj powoli"]),
    ex("db_lateral", "Unoszenie hantli bokiem", "strength", ["barki"], 2, 3.5, ["lateral_down", "lateral_up"], 2.4,
       eq=["db"], hold="db", stress=["barki"], tips=["Do wysokości barków", "Lekko ugięte łokcie"]),
    ex("db_rdl", "Martwy ciąg rumuński z hantlami", "strength", ["plecy", "pośladki", "nogi"], 2, 5.0,
       ["stand", "hinge"], 3.0, eq=["db|kb"], hold="db", stress=["plecy"],
       tips=["Ciężar blisko nóg", "Biodra w tył, plecy proste"]),
    ex("kb_swing", "Swing kettlebell", "cardio", ["pośladki", "plecy", "całe ciało"], 3, 9.0,
       ["swing_back", "swing_up"], 1.4, eq=["kb"], hold="kb", stress=["plecy"],
       tips=["Ruch z bioder, nie z rąk", "Na górze ściśnij pośladki"]),
    ex("band_pull_apart", "Rozciąganie gumy", "strength", ["plecy", "barki"], 1, 3.0, ["pull_apart_in", "pull_apart_out"],
       2.0, eq=["band"], hold="band", tips=["Łopatki do siebie", "Ręce na wysokości barków"]),
    ex("band_row", "Wiosłowanie z gumą", "strength", ["plecy", "ramiona"], 1, 3.5, ["band_row_out", "band_row_in"], 2.2,
       eq=["band"], hold="band", tips=["Guma zaczepiona na wysokości pasa", "Łokcie do tyłu"]),
    ex("pullups", "Podciąganie na drążku", "strength", ["plecy", "ramiona"], 4, 8.0, ["hang", "pull_top"], 3.0,
       eq=["bar"], anchor="hands", props=[{"type": "bar"}], stress=["barki"],
       tips=["Pełny zwis na dole", "Broda nad drążek"]),
    ex("hanging_knee_raise", "Unoszenie kolan w zwisie", "core", ["brzuch"], 3, 4.5, ["hang", "hang_knees"], 2.4,
       eq=["bar"], anchor="hands", props=[{"type": "bar"}], tips=["Bez bujania", "Kolana do wysokości bioder"]),
]

ids = [e["id"] for e in E]
assert len(ids) == len(set(ids)), "zduplikowane id"
for e in E:
    for k in e["anim"]["k"]:
        if isinstance(k, str):
            assert k.rstrip("~") in P, f"{e['id']}: brak pozy {k}"
    for rel in ("easier", "harder"):
        if rel in e:
            assert e[rel] in ids, f"{e['id']}: {rel} → {e[rel]}"

# pozy bez wartości domyślnych, żeby JSON był krótszy
DEF = {"t": 180, "fp": 0, "lift": 0, "x": 0, "view": "side", "back": False}


def slim(p):
    return {k: v for k, v in p.items() if not (k in DEF and DEF[k] == v)}


out = {
    "version": 1,
    "poses": {k: slim(v) for k, v in P.items()},
    "exercises": [{**e, "anim": {**e["anim"], "k": [slim(k) if isinstance(k, dict) else k for k in e["anim"]["k"]]}}
                  for e in E],
}
dst = ROOT / "assets" / "exercises.json"
dst.parent.mkdir(exist_ok=True)
dst.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
print(f"{len(E)} ćwiczeń, {len(P)} póz → {dst.relative_to(ROOT)}")
