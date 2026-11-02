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
P["jump_up"] = {"an": [168, 175], "af": [164, 170], "lift": 0.16, "ln": [4, 0], "lf": [-4, -2], "fp": 45}
P["squat_bot"] = {"t": 148, "an": [90, 90], "af": [86, 86], "ln": [80, -24], "lf": [77, -24]}
P["squat_mid"] = {"t": 162, "an": [70, 80], "af": [66, 76], "ln": [45, -20], "lf": [42, -20]}
P["squat_hands"] = solve({"t": 96, "h": 104, "ln": [86, -34], "lf": [84, -34]},
                         lambda p, v: (p.__setitem__("an", [v, v]), p.__setitem__("af", [v - 4, v - 4])),
                         "haN", "toN", 0, 89)
P["goblet_top"] = {"an": [15, 165], "af": [12, 162]}
P["goblet_bot"] = {"t": 150, "an": [30, 175], "af": [27, 172], "ln": [80, -24], "lf": [77, -24]}
P["calf_up"] = {"fp": 50, "an": [6, 10], "af": [-6, -2]}
P["high_knee"] = {"t": 176, "an": [-40, 25], "af": [45, 125], "ln": [100, 5], "lf": [0, 0], "fp": 25}
P["butt_kick"] = {"t": 176, "an": [-40, 25], "af": [45, 125], "ln": [-12, -165], "lf": [2, 0], "fp": 20}
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


# ============================================================ v2: nowe pozy
P["lunge_fwd"] = dict(P["lunge_down"], x=0.32)
P["jump_mid"] = {"t": 178, "an": [40, 60], "af": [-30, 20], "ln": [40, -10], "lf": [-20, -40], "lift": 0.18}
P["squat_pulse"] = {"t": 152, "an": [90, 90], "af": [86, 86], "ln": [68, -22], "lf": [65, -22]}
P["squat_head"] = {"t": 150, "h": 156, "an": [150, -40], "af": [146, -44], "ln": [80, -24], "lf": [77, -24]}
P["cossack"] = dict(FR, t=168, an=[10, -120], af=[10, -120], ln=[78, -10], lf=[58, 58])
P["curtsy"] = dict(FR, t=176, an=[10, -120], af=[10, -120], ln=[30, -8], lf=[-30, -60])
P["sl_rdl"] = {"t": 96, "h": 100, "an": [0, 0], "af": [4, 4], "ln": [-84, -84], "lf": [6, -2]}
P["sl_calf"] = {"an": [6, 10], "af": [-6, -2], "ln": [-14, -70], "lf": [0, 0], "fp": 50}
P["sl_calf_down"] = {"an": [6, 10], "af": [-6, -2], "ln": [-14, -70], "lf": [0, 0]}
P["pistol_top"] = {"an": [90, 90], "af": [86, 86], "ln": [60, 60], "lf": [0, 0]}
P["pistol_bot"] = {"t": 140, "an": [90, 90], "af": [86, 86], "ln": [84, 84], "lf": [84, -26]}
P["box_squat"] = {"t": 150, "an": [90, 90], "af": [86, 86], "ln": [88, -8], "lf": [86, -8]}
P["thrust_down"] = {"t": 108, "h": 100, "back": True, "an": [-60, -60], "af": [-62, -62], "ln": [-100, 6], "lf": [-102, 6]}
P["thrust_up"] = {"t": 92, "h": 86, "back": True, "an": [-60, -60], "af": [-62, -62], "ln": [-96, 2], "lf": [-98, 2]}
P["thruster_bot"] = {"t": 150, "an": [40, 175], "af": [36, 172], "ln": [80, -24], "lf": [77, -24]}
P["band_press_in"] = {"an": [-35, 88], "af": [-38, 86], "ln": [10, 0], "lf": [-10, 0]}
P["triceps_up"] = {"an": [172, 176], "af": [170, 174]}
P["triceps_down"] = {"an": [172, -25], "af": [170, -28]}
P["kickback_bent"] = {"t": 112, "an": [-75, 5], "af": [-78, 5], "ln": [26, -12], "lf": [24, -12]}
P["kickback_ext"] = {"t": 112, "an": [-75, -75], "af": [-78, -78], "ln": [26, -12], "lf": [24, -12]}
P["front_raise"] = {"an": [88, 90], "af": [84, 86]}
P["kb_dl_bot"] = {"t": 130, "an": [0, 0], "af": [0, 0], "ln": [55, -20], "lf": [53, -20]}
P["renegade"] = dict(P["pushup_top"], an=[-115, 5])
P["press_one"] = {"an": [176, 178], "af": [8, 12]}
P["press_one_down"] = {"an": [70, 175], "af": [8, 12]}
P["chest_stretch"] = {"t": 182, "h": 186, "an": [-40, -40], "af": [-44, -44]}
P["arm_up_bent"] = {"an": [172, -25], "af": [-8, -4]}
P["wall_hands"] = solve({"t": 140, "an": [70, 70], "af": [68, 68], "ln": [8, 0], "lf": [-35, -35]},
                        lambda p, v: p.__setitem__("lf", [v, v]), "toF", "toN", -10, -60)
P["leg_swing_f"] = {"an": [-20, 10], "af": [30, 40], "ln": [70, 70], "lf": [0, 0]}
P["leg_swing_b"] = {"an": [30, 40], "af": [-20, 10], "ln": [-40, -40], "lf": [0, 0]}
P["knee_elbow"] = {"t": 168, "h": 160, "an": [150, -60], "af": [146, -64], "ln": [110, 5], "lf": [0, 0]}
P["jog"] = {"t": 178, "an": [-30, 40], "af": [35, 110], "ln": [55, -40], "lf": [-5, 0], "fp": 30}
P["tuck"] = {"an": [80, 60], "af": [76, 56], "ln": [140, 10], "lf": [136, 8], "lift": 0.35}
P["hop"] = {"an": [22, 70], "af": [18, 66], "ln": [3, 0], "lf": [-3, 0], "lift": 0.06, "fp": 40}
P["hop_down"] = {"an": [22, 70], "af": [18, 66], "ln": [3, 0], "lf": [-3, 0]}
P["punch_up"] = {"t": 176, "an": [176, 178], "af": [35, 155], "ln": [10, -4], "lf": [-12, 0]}
P["bear"] = clean(solve({"an": [0, 0], "af": [0, 0], "ln": [45, -60], "lf": [45, -60]}, set_t, "haN", "toN", 60, 150))
P["bear_step"] = dict(P["bear"], ln=[55, -60])
P["wgs"] = {"t": 118, "h": 112, "an": [5, 0], "af": [175, 178], "ln": [78, -10], "lf": [-60, -60]}
P["wgs_down"] = {"t": 118, "h": 112, "an": [5, 0], "af": [10, 5], "ln": [78, -10], "lf": [-60, -60]}
P["hip_l"] = dict(FR, t=172, h=176, an=[-20, -150], af=[-20, -150], ln=[8, 8], lf=[16, 16])
P["thoracic_open"] = dict(P["quad"], af=[180, 180], h=P["quad"]["t"] + 30)
P["sit_ups_up"] = {"t": 178, "h": 182, "back": True, "an": [90, 90], "af": [88, 88], "ln": [-140, -32], "lf": [-142, -32]}
P["v_flat"] = dict(SUP, an=[96, 96], af=[96, 96], ln=[-92, -92], lf=[-92, -92])
P["v_up"] = dict(SUP, t=140, h=150, an=[-125, -125], af=[-127, -127], ln=[-140, -140], lf=[-141, -141])
P["rev_crunch_a"] = dict(SUP, ln=[178, -92], lf=[176, -94])
P["rev_crunch_b"] = dict(SUP, t=80, h=88, ln=[140, -130], lf=[138, -132])
P["toe_touch_a"] = dict(SUP, an=[150, 150], af=[150, 150], ln=[-178, -178], lf=[-179, -179])
P["toe_touch_b"] = dict(SUP, t=125, h=135, an=[-170, -170], af=[-172, -172], ln=[-178, -178], lf=[-179, -179])
P["tuck_sit_out"] = {"t": -150, "h": -158, "an": [-60, -60], "af": [-62, -62], "ln": [112, 112], "lf": [110, 110]}
P["tuck_sit_in"] = {"t": -160, "h": -166, "an": [-60, -60], "af": [-62, -62], "ln": [150, 40], "lf": [148, 38]}
P["swimmer"] = dict(PRONE, t=96, h=100, an=[110, 110], af=[95, 95], ln=[-92, -92], lf=[-104, -104])
P["y_raise"] = dict(PRONE, t=96, h=100, an=[112, 112], af=[112, 112])
P["sphinx"] = dict(PRONE, t=112, h=125, an=[-5, 90], af=[-7, 90])
P["rev_plank"] = clean(solve({"back": True, "an": [-12, -12], "af": [-14, -14], "_dh": -6},
                             lambda p, v: (p.__setitem__("t", v), p.__setitem__("h", v - 6),
                                           p.__setitem__("ln", [v - 180, v - 180]), p.__setitem__("lf", [v - 180, v - 180])),
                             "haN", "anN", 92, 140))
P["floor_press_down"] = dict(SUP, an=[-92, 180], af=[-94, 178], ln=[-140, -32], lf=[-142, -32])
P["floor_press_up"] = dict(SUP, an=[180, 180], af=[178, 178], ln=[-140, -32], lf=[-142, -32])
P["pullover_down"] = dict(SUP, an=[96, 96], af=[98, 98], ln=[-140, -32], lf=[-142, -32])
P["breath"] = dict(SUP, an=[150, -40], af=[-90, -90], ln=[-140, -32], lf=[-142, -32])
P["breath_b"] = dict(P["breath"], h=92)
P["bridge_hold"] = P["bridge_up"]
P["butterfly"] = dict(FR, t=180, an=[30, 40], af=[30, 40], ln=[100, -130], lf=[100, -130])
P["butterfly_b"] = dict(P["butterfly"], t=178, ln=[104, -128], lf=[104, -128])
P["wall_w"] = dict(FR, an=[100, 175], af=[100, 175], ln=[6, 6], lf=[6, 6])
P["wall_y"] = dict(FR, an=[155, 165], af=[155, 165], ln=[6, 6], lf=[6, 6])
P["dislocate_up"] = {"an": [178, 178], "af": [176, 176]}
P["dislocate_back"] = {"an": [-110, -110], "af": [-112, -112]}
P["shoulder_x"] = dict(FR, an=[-95, -92], af=[55, -150], ln=[6, 6], lf=[6, 6])
P["shuffle_a"] = dict(FR, t=180, an=[30, 80], af=[30, 80], ln=[30, -10], lf=[30, -10])
P["shuffle_b"] = dict(FR, t=180, x=0.25, an=[30, 80], af=[30, 80], ln=[18, -6], lf=[18, -6], lift=0.05)
P["star"] = dict(FR, an=[135, 140], af=[135, 140], ln=[30, 30], lf=[30, 30], lift=0.25)
P["squat_jack_in"] = dict(FR, an=[10, -120], af=[10, -120], ln=[6, 6], lf=[6, 6], lift=0.1)
P["band_walk"] = dict(FR, t=180, an=[10, -120], af=[10, -120], ln=[28, -6], lf=[28, -6])
P["band_walk_b"] = dict(FR, t=180, x=0.12, an=[10, -120], af=[10, -120], ln=[14, -4], lf=[38, -8])
P["hang_hold"] = P["hang"]
P["chin_top"] = dict(P["pull_top"], an=[25, 168], af=[23, 166])
P["dec_push_top"] = {"an": [0, 0], "af": [0, 0], "t": 76, "h": 80, "ln": [-104, -104], "lf": [-104, -104]}
P["dec_push_bot"] = {"an": [-115, 10], "af": [-117, 10], "t": 70, "h": 74, "ln": [-110, -110], "lf": [-110, -110]}
P["side_plank_low"] = dict(P["side_plank"], t=P["side_plank"]["t"] - 8, h=P["side_plank"]["t"] - 8,
                           ln=[P["side_plank"]["t"] - 188] * 2, lf=[188 - P["side_plank"]["t"]] * 2)
P["calf_wall"] = {"t": 158, "an": [60, 60], "af": [58, 58], "ln": [30, -15], "lf": [-30, -30]}
P["fold_hold"] = P["fold"]


# ------------------------------------------------------------ v2: plecy / ramiona / barki
P["angel_down"] = dict(PRONE, t=95, h=98, an=[-82, -82], af=[-84, -84])
P["angel_up"] = dict(PRONE, t=97, h=100, an=[100, 100], af=[102, 102])
P["prone_w"] = dict(PRONE, t=97, h=100, an=[-118, 95], af=[-120, 93])
P["prone_pull"] = dict(PRONE, t=98, h=102, an=[-60, 110], af=[-62, 110])
P["door_lean"] = {"t": -160, "h": -164, "an": [92, 92], "af": [90, 90], "ln": [20, 20], "lf": [20, 20], "x": -0.1}
P["door_pull"] = {"t": -172, "h": -176, "an": [-20, 95], "af": [-22, 93], "ln": [8, 8], "lf": [8, 8], "x": 0.05}
P["inv_row_down"] = {"t": 112, "h": 108, "back": True, "an": [180, 180], "af": [178, 178], "ln": [-68, -68], "lf": [-68, -68]}
P["inv_row_up"] = dict(P["inv_row_down"], t=126, h=122, ln=[-54, -54], lf=[-54, -54], an=[150, 205], af=[148, 203])
P["tabletop_down"] = {"t": 150, "h": 140, "back": True, "an": [-25, -25], "af": [-27, -27], "ln": [-120, 10], "lf": [-122, 10]}
P["tabletop_up"] = clean(solve({"back": True, "an": [-6, -6], "af": [-8, -8], "ln": [-90, 0], "lf": [-92, 0]},
                               lambda p, v: (p.__setitem__("t", v), p.__setitem__("h", v - 8)), "haN", "anN", 80, 130))
P["floor_dip_up"] = {"t": 160, "h": 160, "back": True, "an": [-25, -25], "af": [-27, -27], "ln": [-110, 15], "lf": [-112, 15]}
P["floor_dip_down"] = {"t": 150, "h": 150, "back": True, "an": [-70, 30], "af": [-72, 30], "ln": [-100, 25], "lf": [-102, 25]}
P["plank_dog"] = clean(solve({"t": 55, "h": 40, "an": [55, 55], "af": [55, 55]}, set_legs, "haN", "toN", -20, -80))
P["scap_squeeze"] = {"an": [-20, 90], "af": [-22, 88]}
P["scap_open"] = {"an": [20, 90], "af": [18, 88]}
P["small_circ_a"] = dict(FR, an=[88, 88], af=[88, 88], ln=[6, 6], lf=[6, 6])
P["small_circ_b"] = dict(FR, an=[96, 96], af=[96, 96], ln=[6, 6], lf=[6, 6])
P["pushdown_up"] = {"an": [4, 150], "af": [2, 148]}
P["pushdown_down"] = {"an": [4, 4], "af": [2, 2]}
P["pulldown_up"] = {"an": [168, 175], "af": [166, 173]}
P["pulldown_down"] = {"an": [30, 168], "af": [28, 166]}
P["face_pull"] = {"an": [100, -170], "af": [98, -172]}
P["skull_up"] = dict(SUP, an=[172, 172], af=[170, 170], ln=[-140, -32], lf=[-142, -32])
P["skull_down"] = dict(SUP, an=[160, 60], af=[158, 58], ln=[-140, -32], lf=[-142, -32])
P["one_arm_row_a"] = {"t": 108, "an": [0, 0], "af": [30, 30], "ln": [-30, -10], "lf": [40, -15]}
P["one_arm_row_b"] = {"t": 108, "an": [-115, 0], "af": [30, 30], "ln": [-30, -10], "lf": [40, -15]}
P["scap_pull"] = dict(P["hang"], an=[178, 178], af=[176, 176], lift=0)
P["hang_legs_up"] = {"an": [180, 180], "af": [178, 178], "ln": [100, 100], "lf": [98, 98]}
P["neg_top"] = P["pull_top"]
P["arnold_down"] = {"an": [20, 170], "af": [18, 168]}
P["upright_hold"] = {"an": [10, 10], "af": [8, 8]}
P["db_shrug_up"] = {"an": [4, 4], "af": [2, 2], "h": 186}
P["reverse_fly_a"] = {"t": 100, "h": 104, "an": [5, 5], "af": [5, 5], "ln": [18, -8], "lf": [16, -8]}
P["reverse_fly_b"] = {"t": 100, "h": 104, "an": [-70, -70], "af": [-72, -72], "ln": [18, -8], "lf": [16, -8]}


# ------------------------------------------------------------ v3: brakujące ćwiczenia z Fitify
P["bridge_march"] = dict(P["bridge_up"], ln=[-172, -95])
P["squat_punch"] = dict(P["squat_bot"], an=[88, 90], af=[30, 150])
P["knee_up"] = {"an": [10, 10], "af": [-10, -5], "ln": [100, 5], "lf": [0, 0]}
P["chair_pose"] = {"t": 158, "h": 162, "an": [165, 170], "af": [162, 168], "ln": [58, -22], "lf": [56, -22]}
P["sumo_jump"] = dict(P["sumo_top"], lift=0.2, x=0.3)
P["frog_air"] = dict(P["jump_up"], x=0.4, lift=0.28)
P["atg_bot"] = {"t": 174, "an": [10, 10], "af": [-8, -8], "ln": [-28, -70], "lf": [72, -40]}
P["atg_top"] = {"t": 178, "an": [10, 10], "af": [-8, -8], "ln": [-14, -20], "lf": [45, -30]}
P["leg_curl"] = {"an": [-30, 60], "af": [-32, 58], "ln": [-8, -130], "lf": [0, 0]}
P["donkey_straight"] = dict(P["quad"], ln=[-100, -100])
P["hydrant"] = dict(P["quad"], ln=[-45, -95])
P["inner_base"] = dict(P["side_lying"], lf=[150, 40])
P["inner_up"] = dict(P["side_lying"], lf=[150, 40], ln=[-72, -72])
P["side_leg_out"] = dict(FR, an=[10, -120], af=[10, -120], ln=[42, 42], lf=[4, 4])
P["supine_march"] = dict(P["bridge_down"], ln=[178, -92])
P["alt_leg_up"] = dict(P["legs_low"], ln=[-168, -168])
P["circle_a"] = dict(SUP, ln=[-176, -176], lf=[-92, -92])
P["circle_b"] = dict(SUP, ln=[-150, -150], lf=[-92, -92])
P["circle_c"] = dict(SUP, ln=[-128, -128], lf=[-92, -92])
P["circle_d"] = dict(SUP, ln=[-152, -152], lf=[-92, -92])
P["crunch_tt_down"] = dict(SUP, an=[160, -30], af=[158, -32], ln=[178, -90], lf=[176, -92])
P["crunch_tt_up"] = dict(SUP, t=120, h=126, an=[-130, -130], af=[-132, -132], ln=[178, -90], lf=[176, -92])
P["side_crunch_up"] = dict(P["side_lying"], t=114, h=120, af=[150, -40])
P["side_crunch_down"] = dict(P["side_lying"], af=[150, -40])
P["heel_a"] = dict(SUP, t=110, h=116, an=[-80, -80], af=[-82, -82], ln=[-140, -32], lf=[-142, -32])
P["heel_b"] = dict(SUP, t=108, h=114, an=[-96, -96], af=[-98, -98], ln=[-140, -32], lf=[-142, -32])
P["rollup_top"] = {"t": -132, "h": -122, "back": True, "an": [-100, -100], "af": [-102, -102], "ln": [-90, -90], "lf": [-90, -90]}
P["ball_up"] = dict(P["tuck_sit_in"], an=[30, 10], af=[28, 8])
P["ball_back"] = dict(P["tuck_sit_in"], t=-112, h=-118, an=[30, 10], af=[28, 8], ln=[175, 45], lf=[173, 43])
P["hundred_a"] = dict(SUP, t=112, h=120, an=[-78, -78], af=[-80, -80], ln=[-130, -130], lf=[-131, -131])
P["hundred_b"] = dict(P["hundred_a"], an=[-90, -90], af=[-92, -92])
P["teaser_low"] = {"t": -112, "h": -116, "an": [100, 100], "af": [98, 98], "ln": [100, 100], "lf": [100, 100]}
P["teaser_up"] = {"t": -145, "h": -150, "an": [118, 118], "af": [116, 116], "ln": [132, 132], "lf": [132, 132]}
P["twist_a"] = dict(FR, an=[90, 90], af=[25, -110], ln=[10, 10], lf=[10, 10])
P["twist_b"] = dict(FR, an=[25, -110], af=[90, 90], ln=[10, 10], lf=[10, 10])
P["lumbar_side"] = dict(P["bridge_down"], ln=[-115, -55], lf=[-117, -55])
P["plank_reach"] = dict(P["plank"], an=[95, 95])
P["two_point"] = dict(P["pushup_top"], an=[95, 95], lf=[P["pushup_top"]["t"] - 172] * 2)
P["plank_hips"] = dict(P["pushup_top"], t=P["pushup_top"]["t"] + 6, h=P["pushup_top"]["t"] + 10,
                       ln=[P["pushup_top"]["t"] - 168] * 2, lf=[P["pushup_top"]["t"] - 168] * 2)
P["plank_leg"] = dict(P["plank"], ln=[P["plank"]["t"] - 168] * 2)
P["scap_low"] = dict(P["pushup_top"], t=P["pushup_top"]["t"] - 3, h=P["pushup_top"]["t"])
P["rev_plank_kick"] = dict(P["rev_plank"], ln=[P["rev_plank"]["t"] - 160] * 2)
P["crab_step"] = dict(P["tabletop_up"], ln=[-70, 0])
P["side_plank_knee"] = dict(P["side_plank"], ln=[P["side_plank"]["ln"][0], P["side_plank"]["ln"][0] + 80],
                            lf=[P["side_plank"]["lf"][0], P["side_plank"]["lf"][0] - 80])
P["side_plank_leg"] = dict(P["side_plank"], lf=[115, 115])
P["prone_t"] = dict(PRONE, t=92, h=94, an=[84, 84], af=[86, 86])
P["prone_t_up"] = dict(PRONE, t=96, h=100, an=[96, 96], af=[98, 98])
P["wall_push_top"] = {"t": 152, "h": 156, "an": [72, 72], "af": [70, 70], "ln": [-28, -28], "lf": [-28, -28]}
P["wall_push_bot"] = {"t": 148, "h": 152, "an": [-15, 100], "af": [-17, 98], "ln": [-32, -32], "lf": [-32, -32]}
P["up_dog"] = clean(solve({"t": 140, "h": 150, "ln": [-90, -90], "lf": [-90, -90]},
                          lambda p, v: (p.__setitem__("an", [v, v]), p.__setitem__("af", [v, v])), "haN", "toN", 0, 80))
P["crawl_a"] = {"t": 112, "h": 116, "an": [160, 165], "af": [-40, -30], "ln": [18, -8], "lf": [16, -8]}
P["clap_air"] = dict(P["pushup_top"], lift=0.12, an=[-20, 30], af=[-22, 28])
P["spider"] = dict(P["pushup_bot"], ln=[55, -60])
P["t_rot"] = dict(P["pushup_top"], af=[180, 180], h=P["pushup_top"]["t"] + 30)
P["hs_top"] = {"t": 4, "h": 0, "an": [2, 2], "af": [0, 0], "ln": [178, 178], "lf": [176, 176]}
P["hs_bot"] = {"t": 10, "h": 4, "an": [-60, 40], "af": [-62, 38], "ln": [178, 178], "lf": [176, 176]}
P["cross_climb"] = dict(P["pushup_top"], ln=[72, -40])
P["step_touch"] = dict(FR, x=0.18, an=[150, 160], af=[150, 160], ln=[18, 4], lf=[-4, -4])
P["front_kick"] = {"an": [10, 10], "af": [95, 95], "ln": [86, 86], "lf": [0, 0]}
P["hop_one"] = {"an": [20, 60], "af": [18, 58], "ln": [-10, -70], "lf": [0, 0], "fp": 30}
P["hop_one_up"] = dict(P["hop_one"], lift=0.1)
P["feet_hop_a"] = dict(FR, an=[20, 40], af=[20, 40], ln=[3, 3], lf=[3, 3])
P["feet_hop_b"] = dict(P["feet_hop_a"], x=0.3, lift=0.12)
P["roll_kneel"] = clean(solve({"t": 100, "h": 106, "ln": [0, -92], "lf": [0, -92]},
                              lambda p, v: (p.__setitem__("an", [v, v]), p.__setitem__("af", [v, v])), "haN", "knN", 0, 80))
P["roll_out"] = clean(solve({"t": 98, "h": 102, "ln": [-82, -92], "lf": [-82, -92]},
                            lambda p, v: (p.__setitem__("an", [v, v]), p.__setitem__("af", [v, v])), "haN", "knN", 40, 89))
P["pigeon"] = {"t": 178, "an": [10, 10], "af": [-8, -8], "ln": [-88, -90], "lf": [80, -70]}
P["pigeon_low"] = {"t": 112, "h": 104, "an": [80, 80], "af": [78, 78], "ln": [-88, -90], "lf": [80, -70]}
P["thread"] = dict(P["quad"], t=P["quad"]["t"] - 18, h=P["quad"]["t"] - 30, an=[-80, -80])
P["lying_ham"] = dict(SUP, an=[-150, -150], af=[-152, -152], ln=[-178, -178], lf=[-92, -92])
P["wide_fold"] = dict(FR, t=22, h=10, an=[4, 4], af=[4, 4], ln=[30, 30], lf=[30, 30])
P["knee_circ_a"] = {"t": 150, "an": [45, 10], "af": [43, 8], "ln": [40, -30], "lf": [38, -30]}
P["knee_circ_b"] = {"t": 152, "an": [42, 8], "af": [40, 6], "ln": [30, -24], "lf": [28, -24]}
P["shoulder_up"] = {"t": 180, "h": 184, "an": [-6, -4], "af": [-8, -6]}
P["neck_l"] = dict(FR, h=158, an=[8, 4], af=[8, 4], ln=[6, 6], lf=[6, 6])
P["warrior2"] = dict(FR, an=[90, 90], af=[90, 90], ln=[58, 0], lf=[42, 42])
P["triangle"] = dict(FR, t=128, h=128, an=[0, 0], af=[180, 180], ln=[36, 36], lf=[36, 36])
P["windmill"] = dict(FR, t=32, h=30, an=[-25, -25], af=[175, 175], ln=[30, 30], lf=[30, 30])
P["backbend"] = {"t": -164, "h": -150, "an": [-165, -165], "af": [-163, -163], "ln": [8, 0], "lf": [6, 0]}
P["upper_back"] = {"t": 172, "h": 150, "an": [96, 150], "af": [94, 148]}
P["wrist_a"] = {"an": [90, 70], "af": [88, 68]}
P["wrist_b"] = {"an": [90, 110], "af": [88, 108]}
P["ankle_a"] = {"an": [10, 10], "af": [-8, -8], "ln": [30, -10], "lf": [0, 0], "fp": 30}
P["ankle_b"] = dict(P["ankle_a"], fp=-30)
P["plow"] = dict(SUP, t=40, h=88, an=[-90, -90], af=[-92, -92], ln=[100, 100], lf=[100, 100])
P["candle"] = dict(SUP, t=14, h=88, an=[-90, -40], af=[-92, -42], ln=[176, 176], lf=[176, 176])
P["fish"] = dict(SUP, t=104, h=60, an=[-92, -92], af=[-94, -94], ln=[-92, -92], lf=[-92, -92])
P["mountain"] = {"an": [4, 4], "af": [-4, -4], "ln": [1, 0], "lf": [-1, 0]}

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

# mięśnie (mapa po treningu): główne przed „|”, pomocnicze po nim
MUSCLES = ["chest", "shoulders", "biceps", "triceps", "forearms", "abs", "obliques", "traps", "upper_back",
           "lats", "lower_back", "glutes", "abductors", "adductors", "quads", "hamstrings", "calves"]
MUSCLE_GROUP = {
    "chest": "klatka", "shoulders": "barki", "biceps": "ramiona", "triceps": "ramiona", "forearms": "ramiona",
    "abs": "brzuch", "obliques": "brzuch", "traps": "plecy", "upper_back": "plecy", "lats": "plecy",
    "lower_back": "plecy", "glutes": "pośladki", "abductors": "pośladki", "adductors": "nogi", "quads": "nogi",
    "hamstrings": "nogi", "calves": "nogi",
}


def parse_m(spec):
    prim, _, sec = spec.partition("|")
    out = {}
    for w in prim.split():
        assert w in MUSCLES, f"nieznany mięsień {w}"
        out[w] = 1.0
    for w in sec.split():
        assert w in MUSCLES, f"nieznany mięsień {w}"
        out.setdefault(w, 0.5)
    return out


def ex(id, name, typ, groups, lvl, met, keys, s=2.0, eq=(), impact=False, uni=False,
       stress=(), tips=(), hold=None, props=None, anchor=None, easier=None, harder=None, static=False, m=None):
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
    if m:
        e["m"] = parse_m(m)
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


# ============================================================ v2: mięśnie dotychczasowych ćwiczeń
M_OLD = {
    "jumping_jacks": "calves quads shoulders | glutes abductors", "step_jacks": "shoulders calves | quads",
    "march": "quads | abs calves", "high_knees": "quads abs | calves glutes", "butt_kicks": "hamstrings calves | quads",
    "arm_circles": "shoulders | upper_back", "shadow_boxing": "shoulders | triceps obliques",
    "mountain_climbers": "abs shoulders | quads chest", "burpees": "quads chest shoulders | glutes triceps abs",
    "squat_thrust": "quads shoulders | abs glutes", "jump_squats": "quads glutes | calves hamstrings",
    "skaters": "glutes abductors quads | calves", "inchworm": "hamstrings shoulders | abs chest",
    "squat": "quads glutes | hamstrings lower_back", "sumo_squat": "quads glutes adductors | hamstrings",
    "reverse_lunge": "quads glutes | hamstrings calves", "side_lunge": "quads adductors glutes | abductors",
    "glute_bridge": "glutes | hamstrings lower_back", "single_leg_bridge": "glutes hamstrings | lower_back abs",
    "wall_sit": "quads | glutes", "calf_raises": "calves", "donkey_kicks": "glutes | hamstrings",
    "good_morning": "hamstrings lower_back | glutes", "step_ups": "quads glutes | calves",
    "split_squat": "quads glutes | hamstrings", "side_leg_raise": "abductors | glutes",
    "pushups": "chest triceps | shoulders abs", "knee_pushups": "chest triceps | shoulders",
    "incline_pushups": "chest | triceps shoulders", "pike_pushups": "shoulders triceps | chest traps",
    "triceps_dips": "triceps | chest shoulders", "shoulder_taps": "abs shoulders | obliques chest",
    "superman": "lower_back | glutes upper_back", "plank": "abs | shoulders glutes",
    "side_plank": "obliques | abs abductors shoulders", "crunches": "abs", "bicycle": "abs obliques",
    "leg_raises": "abs | quads", "flutter_kicks": "abs | quads", "dead_bug": "abs | obliques",
    "hollow_hold": "abs | quads", "russian_twist": "obliques abs", "bird_dog": "lower_back abs | glutes shoulders",
    "cat_cow": "lower_back | abs", "childs_pose": "lower_back lats", "cobra": "abs | lower_back",
    "down_dog": "hamstrings calves shoulders", "hamstring_stretch": "hamstrings lower_back", "quad_stretch": "quads",
    "hip_flexor_stretch": "quads | abs", "knee_hug": "lower_back glutes", "side_bend": "obliques | lats",
    "deep_squat_hold": "adductors glutes | calves", "goblet_squat": "quads glutes | abs",
    "db_row": "lats upper_back | biceps forearms", "db_press": "shoulders triceps | traps", "db_curl": "biceps | forearms",
    "db_lateral": "shoulders | traps", "db_rdl": "hamstrings glutes lower_back | forearms",
    "kb_swing": "glutes hamstrings | lower_back shoulders forearms", "band_pull_apart": "upper_back shoulders | traps",
    "band_row": "upper_back lats | biceps", "pullups": "lats biceps | upper_back forearms",
    "hanging_knee_raise": "abs | forearms lats",
}
for e in E:
    e["m"] = parse_m(M_OLD[e["id"]])

CHAIR_FEET = [{"type": "chair", "at": "toN", "w": 0.42, "dx": -0.1}]
BAR = [{"type": "bar"}]
WALL_H = [{"type": "wall", "at": "haN", "dx": 0.04}]

# ============================================================ v2: nowe ćwiczenia
E += [
    # --- nogi i pośladki
    ex("forward_lunge", "Wykroki w przód", "strength", [], 2, 5.0, ["stand", "lunge_fwd", "stand", "lunge_fwd~"], 4.0,
       stress=["kolana"], m="quads glutes | hamstrings calves", tips=["Duży krok, tułów prosto", "Odepchnij się przednią piętą"]),
    ex("jump_lunge", "Wykroki z przeskokiem", "cardio", [], 4, 9.0, ["lunge_down", "jump_mid", "lunge_down~", "jump_mid"], 2.0,
       impact=True, stress=["kolana"], m="quads glutes | calves hamstrings", easier="reverse_lunge",
       tips=["Zmieniaj nogi w powietrzu", "Ląduj miękko, kolano nie uderza w podłogę"]),
    ex("curtsy_lunge", "Wykrok skrzyżny", "strength", [], 2, 5.0, ["front_stand", "curtsy", "front_stand", "curtsy~"], 4.0,
       stress=["kolana"], m="glutes abductors quads | adductors", tips=["Noga cofa się skośnie za drugą", "Biodra przodem"]),
    ex("squat_pulse", "Przysiad z pulsowaniem", "strength", [], 2, 5.5, ["squat_bot", "squat_pulse"], 0.9,
       stress=["kolana"], m="quads glutes", tips=["Krótkie ruchy na dole", "Nie wstawaj do końca"]),
    ex("prisoner_squat", "Przysiad z rękami za głową", "strength", [], 2, 5.0, ["stand_hands_head", "squat_head"], 2.6,
       stress=["kolana"], m="quads glutes | upper_back lower_back", tips=["Łokcie szeroko", "Klatka do góry"]),
    ex("cossack_squat", "Przysiad kozacki", "strength", [], 3, 5.0, ["front_stand", "cossack", "front_stand", "cossack~"], 4.0,
       stress=["kolana"], m="adductors quads glutes | hamstrings", tips=["Druga noga prosta, palce w górę", "Pięta na podłodze"]),
    ex("sl_rdl", "Martwy ciąg na jednej nodze", "strength", [], 3, 4.5, ["stand", "sl_rdl"], 3.2, uni=True,
       m="hamstrings glutes | lower_back abductors", tips=["Biodra równo", "Ciało i noga jak jedna linia"]),
    ex("sl_calf_raise", "Wspięcia na jednej nodze", "strength", [], 2, 3.5, ["sl_calf_down", "sl_calf"], 1.8, uni=True,
       m="calves", easier="calf_raises", tips=["Pełny zakres ruchu", "Przytrzymaj się ściany"]),
    ex("pistol_squat", "Przysiad na jednej nodze", "strength", [], 5, 6.0, ["pistol_top", "pistol_bot"], 3.6, uni=True,
       stress=["kolana"], m="quads glutes | abs hamstrings", easier="box_squat",
       tips=["Wolna noga prosto przed sobą", "Na początek z krzesłem za plecami"]),
    ex("box_squat", "Przysiad do krzesła", "strength", [], 1, 4.5, ["box_squat", "stand_fwd"], 2.8, eq=["chair"],
       props=[{"type": "chair", "at": "hip", "w": 0.42, "dx": -0.14}], m="quads glutes | hamstrings",
       harder="squat", tips=["Dotknij krzesła pośladkami i wstań", "Nie siadaj całym ciężarem"]),
    ex("hip_thrust", "Hip thrust z plecami na krześle", "strength", [], 2, 4.5, ["thrust_down", "thrust_up"], 2.6,
       eq=["chair"], props=[{"type": "chair", "at": "neck", "w": 0.42, "dx": 0.16}], m="glutes | hamstrings quads",
       tips=["Łopatki na krawędzi krzesła", "Na górze ściśnij pośladki"]),
    ex("band_walk", "Chód bokiem z gumą", "strength", [], 2, 4.0, ["band_walk", "band_walk_b"], 1.4, eq=["band"],
       m="abductors glutes | quads", tips=["Guma nad kolanami", "Kolana na zewnątrz, biodra nisko"]),
    ex("band_bridge", "Mostek z gumą nad kolanami", "strength", [], 2, 4.0, ["bridge_down", "bridge_up"], 2.4, eq=["band"],
       m="glutes abductors | hamstrings", tips=["Rozpychaj gumę kolanami", "Przytrzymaj na górze"]),
    ex("bridge_hold", "Mostek — utrzymanie", "strength", [], 1, 3.5, ["bridge_hold", dict(P["bridge_up"], t=64)], 3.0,
       static=True, m="glutes | hamstrings lower_back", tips=["Biodra wysoko", "Oddychaj spokojnie"]),
    ex("db_lunge", "Wykroki z hantlami", "strength", [], 3, 6.0, ["stand", "lunge_down", "stand", "lunge_down~"], 4.0,
       eq=["db"], hold="db", stress=["kolana"], m="quads glutes | hamstrings forearms",
       tips=["Ręce luźno wzdłuż ciała", "Tułów pionowo"]),
    ex("db_sumo", "Przysiad sumo z hantlem", "strength", [], 2, 5.5, ["sumo_top", "sumo_bot"], 2.8, eq=["db|kb"], hold="kb",
       stress=["kolana"], m="adductors quads glutes", tips=["Ciężar zwisa między nogami", "Kolana na zewnątrz"]),
    ex("db_step_up", "Wejścia na krzesło z hantlami", "strength", [], 3, 6.5, ["step_on", "step_top"], 2.4, uni=True,
       eq=["db", "chair"], hold="db", stress=["kolana"], props=[{"type": "chair", "at": "toN", "w": 0.4, "dx": -0.12}],
       m="quads glutes | calves forearms", tips=["Stabilne krzesło", "Wchodź siłą nogi na krześle"]),
    ex("kb_deadlift", "Martwy ciąg z kettlebell", "strength", [], 2, 5.0, ["kb_dl_bot", "stand"], 2.8, eq=["kb|db"],
       hold="kb", stress=["plecy"], m="glutes hamstrings lower_back | quads forearms traps",
       tips=["Plecy proste", "Ciężar między stopami"]),
    ex("db_calf_raise", "Wspięcia z hantlami", "strength", [], 2, 4.0, ["stand", "calf_up"], 1.8, eq=["db"], hold="db",
       m="calves | forearms", tips=["Pauza na górze", "Opuszczaj wolno"]),

    # --- plecy (bez sprzętu)
    ex("reverse_angels", "Odwrotne anioły", "strength", [], 1, 3.0, ["angel_down", "angel_up"], 3.0,
       m="upper_back traps | shoulders lower_back", tips=["Ręce nad podłogą przez cały ruch", "Łopatki ściągnięte"]),
    ex("prone_w", "Unoszenie rąk W w leżeniu", "strength", [], 1, 3.0, ["prone", "prone_w"], 2.4,
       m="upper_back traps | shoulders", tips=["Łokcie do bioder", "Kciuki do góry"]),
    ex("prone_y", "Unoszenie rąk Y w leżeniu", "strength", [], 1, 3.0, ["prone", "y_raise"], 2.4,
       m="traps upper_back | shoulders lower_back", tips=["Ręce w literę Y", "Głowa w przedłużeniu tułowia"]),
    ex("superman_pull", "Superman z przyciąganiem łokci", "strength", [], 2, 3.5, ["superman", "prone_pull"], 2.4,
       m="lats upper_back lower_back | biceps glutes", tips=["Jak podciąganie w leżeniu", "Klatka uniesiona"]),
    ex("swimmers", "Pływanie w leżeniu", "strength", [], 2, 3.5, ["swimmer", "swimmer~"], 1.2,
       m="lower_back glutes | upper_back shoulders", tips=["Przeciwna ręka i noga", "Szybkie, krótkie ruchy"]),
    ex("door_row", "Wiosłowanie przy framudze", "strength", [], 2, 4.0, ["door_lean", "door_pull"], 2.6,
       props=WALL_H, m="lats upper_back biceps | forearms abs", harder="inverted_row",
       tips=["Złap mocno framugę lub poręcz", "Im bardziej odchylony, tym trudniej"]),
    ex("tabletop", "Unoszenie bioder w podporze tyłem", "strength", [], 2, 4.0, ["tabletop_down", "tabletop_up"], 2.6,
       stress=["nadgarstki"], m="glutes shoulders | triceps lower_back hamstrings",
       tips=["Dłonie palcami do stóp", "Biodra do linii stołu"]),
    ex("reverse_plank", "Deska tyłem", "core", [], 3, 4.0, ["rev_plank", dict(P["rev_plank"], t=P["rev_plank"]["t"] + 1)], 3.0,
       static=True, stress=["nadgarstki", "barki"], m="glutes lower_back shoulders | hamstrings triceps",
       tips=["Ciało w jednej linii", "Pięty w podłogę"]),
    ex("scap_squeeze", "Ściąganie łopatek", "mobility", [], 1, 2.5, ["scap_open", "scap_squeeze"], 2.4,
       m="upper_back traps", tips=["Łokcie do tyłu, łopatki razem", "Barki nisko"]),
    ex("plank_up_down", "Deska — wejścia na dłonie", "strength", [], 3, 5.5, ["plank", "pushup_top", "plank", "pushup_top"],
       3.2, stress=["nadgarstki"], m="triceps shoulders abs | chest", tips=["Biodra nieruchomo", "Zmieniaj rękę prowadzącą"]),
    ex("plank_to_dog", "Deska do psa", "strength", [], 2, 4.5, ["pushup_top", "plank_dog"], 2.6, stress=["nadgarstki"],
       m="shoulders abs | hamstrings triceps", tips=["Biodra wysoko do góry", "Wróć do prostej deski"]),
    ex("bear_crawl", "Chód niedźwiedzia w miejscu", "cardio", [], 2, 6.0, ["bear", "bear_step", "bear", "bear_step~"], 1.4,
       stress=["nadgarstki"], m="shoulders quads abs | triceps", tips=["Kolana tuż nad podłogą", "Plecy płasko"]),
    ex("small_arm_circles", "Małe krążenia ramion w bok", "strength", [], 1, 3.0, ["small_circ_a", "small_circ_b"], 0.8,
       m="shoulders | traps", tips=["Ręce na wysokości barków", "Małe, szybkie koła"]),
    ex("wall_angels", "Anioły przy ścianie", "mobility", [], 1, 2.5, ["wall_w", "wall_y"], 3.0,
       m="upper_back shoulders | traps", tips=["Plecy i łokcie przy ścianie", "Powoli w górę i w dół"]),
    ex("floor_dips", "Pompki tyłem na podłodze", "strength", [], 1, 4.0, ["floor_dip_up", "floor_dip_down"], 2.4,
       stress=["nadgarstki", "barki"], m="triceps | shoulders chest", harder="triceps_dips",
       tips=["Dłonie za biodrami, palce do stóp", "Zginaj łokcie do tyłu"]),
    ex("diamond_pushups", "Pompki diamentowe", "strength", [], 4, 5.0, ["pushup_top", "pushup_bot"], 2.6,
       stress=["nadgarstki"], m="triceps chest | shoulders", easier="knee_pushups",
       tips=["Dłonie razem pod klatką", "Łokcie blisko tułowia"]),
    ex("wide_pushups", "Pompki szerokie", "strength", [], 3, 5.0, ["pushup_top", "pushup_bot"], 2.4,
       stress=["nadgarstki", "barki"], m="chest | shoulders triceps", tips=["Dłonie szerzej niż barki", "Klatka nisko"]),
    ex("decline_pushups", "Pompki z nogami na krześle", "strength", [], 4, 5.5, ["dec_push_top", "dec_push_bot"], 2.6,
       eq=["chair"], props=CHAIR_FEET, stress=["nadgarstki", "barki"], m="chest shoulders triceps | abs",
       tips=["Ciało w jednej linii", "Głowa w przedłużeniu kręgosłupa"]),
    ex("high_plank", "Podpór przodem", "core", [], 1, 3.8, ["pushup_top", dict(P["pushup_top"], h=P["pushup_top"]["t"] + 10)],
       3.0, static=True, stress=["nadgarstki"], m="abs shoulders | chest triceps", tips=["Dłonie pod barkami", "Brzuch napięty"]),
    ex("kpush_narrow", "Pompki na kolanach wąsko", "strength", [], 2, 4.0, ["kpush_top", "kpush_bot"], 2.4,
       stress=["nadgarstki"], m="triceps | chest shoulders", harder="diamond_pushups",
       tips=["Dłonie blisko siebie", "Łokcie przy żebrach"]),
    ex("punch_up", "Ciosy w górę", "cardio", [], 1, 6.0, ["punch_up", "punch_up~"], 0.7,
       m="shoulders | triceps abs", tips=["Szybko i energicznie", "Brzuch napięty"]),

    # --- plecy / ramiona / barki ze sprzętem
    ex("inverted_row", "Podciąganie australijskie", "strength", [], 3, 5.0, ["inv_row_down", "inv_row_up"], 2.6,
       eq=["bar"], props=BAR, m="lats upper_back biceps | forearms abs", easier="door_row",
       tips=["Niski drążek lub krawędź mocnego stołu", "Klatka do drążka"]),
    ex("chin_ups", "Podciąganie podchwytem", "strength", [], 4, 8.0, ["hang", "chin_top"], 3.0, eq=["bar"],
       anchor="hands", props=BAR, stress=["barki"], m="biceps lats | upper_back forearms",
       tips=["Dłonie przodem do siebie", "Kontrolowane opuszczanie"]),
    ex("dead_hang", "Zwis na drążku", "strength", [], 2, 3.0, ["hang_hold", dict(P["hang"], ln=[-2, -18])], 3.0,
       eq=["bar"], anchor="hands", props=BAR, static=True, m="forearms lats | shoulders",
       tips=["Barki aktywne, nie zapadaj się", "Dobre na kręgosłup"]),
    ex("scap_pulls", "Ściąganie łopatek w zwisie", "strength", [], 2, 3.5, ["hang", dict(P["hang"], h=184, lift=0.06)], 2.0,
       eq=["bar"], anchor="hands", props=BAR, m="lats traps upper_back | forearms",
       tips=["Ręce proste, ruch tylko łopatkami", "Wstęp do podciągania"]),
    ex("negative_pullups", "Opuszczanie z podciągnięcia", "strength", [], 3, 6.0, ["neg_top", "hang"], 4.0, eq=["bar"],
       anchor="hands", props=BAR, stress=["barki"], m="lats biceps | upper_back forearms", harder="pullups",
       tips=["Wskocz na górę, opuszczaj 3–5 s", "Bez spadania na koniec"]),
    ex("hanging_leg_raise", "Unoszenie nóg w zwisie", "core", [], 4, 5.0, ["hang", "hang_legs_up"], 2.8, eq=["bar"],
       anchor="hands", props=BAR, m="abs | forearms lats", easier="hanging_knee_raise",
       tips=["Nogi proste do poziomu", "Bez bujania"]),
    ex("db_one_arm_row", "Wiosłowanie jednorącz z oparciem", "strength", [], 2, 4.5, ["one_arm_row_a", "one_arm_row_b"], 2.4,
       uni=True, eq=["db"], hold="db1", m="lats upper_back | biceps forearms",
       tips=["Druga ręka na kolanie lub krześle", "Łokieć do biodra"]),
    ex("db_reverse_fly", "Odwrotne rozpiętki z hantlami", "strength", [], 2, 4.0, ["reverse_fly_a", "reverse_fly_b"], 2.4,
       eq=["db"], hold="db", stress=["plecy"], m="shoulders upper_back | traps", tips=["Lekki ciężar", "Unoś ręce szeroko na boki"]),
    ex("db_shrug", "Wzruszanie barkami z hantlami", "strength", [], 1, 3.0, ["stand", "db_shrug_up"], 1.8, eq=["db"],
       hold="db", m="traps | forearms", tips=["Barki do uszu", "Bez krążenia"]),
    ex("renegade_row", "Wiosłowanie w podporze", "strength", [], 4, 6.0, ["pushup_top", "renegade", "pushup_top", "renegade~"],
       3.0, eq=["db"], hold="db", stress=["nadgarstki"], m="lats abs | upper_back biceps shoulders",
       tips=["Stopy szeroko", "Biodra nie skręcają"]),
    ex("db_pullover", "Przenoszenie hantla w leżeniu", "strength", [], 2, 4.0, ["floor_press_up", "pullover_down"], 3.0,
       eq=["db"], hold="db", stress=["barki"], m="lats chest | triceps", tips=["Lekko ugięte łokcie", "Lędźwie przy podłodze"]),
    ex("db_hammer_curl", "Uginanie młotkowe", "strength", [], 1, 3.5, ["stand", "curl_up"], 2.4, eq=["db"], hold="db",
       m="biceps forearms", tips=["Kciuki do góry", "Łokcie nieruchomo"]),
    ex("db_triceps_ext", "Wyprosty ramion nad głową", "strength", [], 2, 3.5, ["triceps_up", "triceps_down"], 2.4,
       eq=["db"], hold="db", stress=["barki"], m="triceps", tips=["Łokcie blisko głowy", "Brzuch napięty"]),
    ex("db_kickback", "Prostowanie ramion w opadzie", "strength", [], 1, 3.5, ["kickback_bent", "kickback_ext"], 2.0,
       eq=["db"], hold="db", m="triceps | upper_back", tips=["Ramię przy tułowiu", "Ruch tylko w łokciu"]),
    ex("db_skull_crusher", "Francuskie wyciskanie leżąc", "strength", [], 2, 3.5, ["skull_up", "skull_down"], 2.6,
       eq=["db"], hold="db", m="triceps", tips=["Łokcie wskazują sufit", "Opuszczaj obok głowy"]),
    ex("db_floor_press", "Wyciskanie hantli leżąc", "strength", [], 2, 4.5, ["floor_press_down", "floor_press_up"], 2.4,
       eq=["db"], hold="db", m="chest triceps | shoulders", tips=["Łokcie lekko dotykają podłogi", "Wydech przy wypychaniu"]),
    ex("db_front_raise", "Unoszenie hantli przodem", "strength", [], 2, 3.5, ["stand", "front_raise"], 2.4, eq=["db"],
       hold="db", stress=["barki"], m="shoulders | traps", tips=["Do wysokości barków", "Bez bujania tułowiem"]),
    ex("db_arnold", "Wyciskanie Arnolda", "strength", [], 3, 5.0, ["arnold_down", "press_up"], 2.8, eq=["db"], hold="db",
       stress=["barki"], m="shoulders triceps | traps", tips=["Obracaj dłonie w trakcie ruchu", "Lędźwie neutralnie"]),
    ex("db_thruster", "Przysiad z wyciskaniem", "cardio", [], 3, 8.0, ["thruster_bot", "press_up"], 2.4, eq=["db"],
       hold="db", stress=["kolana", "barki"], m="quads shoulders glutes | triceps abs",
       tips=["Wypchnij ciężar biodrami", "Jeden płynny ruch"]),
    ex("kb_press", "Wyciskanie kettlebell jednorącz", "strength", [], 2, 4.5, ["press_one_down", "press_one"], 2.4,
       uni=True, eq=["kb|db"], hold="kb", stress=["barki"], m="shoulders triceps | abs",
       tips=["Nadgarstek prosto", "Pośladki napięte"]),
    ex("band_chest_press", "Wyciskanie z gumą", "strength", [], 1, 3.5, ["band_press_in", "band_row_out"], 2.2,
       eq=["band"], hold="band", m="chest | triceps shoulders", tips=["Guma zaczepiona za plecami", "Ręce prosto przed siebie"]),
    ex("band_curl", "Uginanie ramion z gumą", "strength", [], 1, 3.0, ["stand", "curl_up"], 2.2, eq=["band"], hold="band",
       m="biceps | forearms", tips=["Stań na gumie", "Łokcie przy tułowiu"]),
    ex("band_press", "Wyciskanie gumy nad głowę", "strength", [], 1, 3.5, ["press_down", "press_up"], 2.4, eq=["band"],
       hold="band", m="shoulders triceps", tips=["Stań na gumie", "Nie wyginaj lędźwi"]),
    ex("band_pushdown", "Prostowanie ramion z gumą", "strength", [], 1, 3.0, ["pushdown_up", "pushdown_down"], 2.0,
       eq=["band"], hold="band", m="triceps", tips=["Guma zaczepiona wysoko", "Łokcie przy bokach"]),
    ex("band_pulldown", "Ściąganie gumy w dół", "strength", [], 1, 3.5, ["pulldown_up", "pulldown_down"], 2.4,
       eq=["band"], hold="band", m="lats | biceps upper_back", tips=["Guma zaczepiona wysoko", "Łokcie do żeber"]),
    ex("band_face_pull", "Przyciąganie gumy do twarzy", "strength", [], 2, 3.5, ["band_row_out", "face_pull"], 2.2,
       eq=["band"], hold="band", m="shoulders upper_back | traps", tips=["Guma na wysokości twarzy", "Łokcie wysoko"]),
    ex("band_dislocates", "Przeprosty z gumą", "mobility", [], 1, 2.5, ["dislocate_up", "dislocate_back", "dislocate_up", "stand"],
       4.0, eq=["band"], hold="band", m="shoulders | chest upper_back", tips=["Szeroki chwyt", "Ręce proste"]),

    # --- brzuch
    ex("v_ups", "Scyzoryki", "core", [], 4, 5.0, ["v_flat", "v_up"], 2.4, stress=["plecy"], m="abs | quads",
       easier="crunches", tips=["Ręce i nogi spotykają się w górze", "Opuszczaj powoli"]),
    ex("reverse_crunch", "Odwrotne brzuszki", "core", [], 2, 4.0, ["rev_crunch_a", "rev_crunch_b"], 2.2, m="abs",
       tips=["Unieś biodra od podłogi", "Bez zamachu nogami"]),
    ex("toe_touches", "Dotykanie palców stóp", "core", [], 2, 4.0, ["toe_touch_a", "toe_touch_b"], 1.8, m="abs",
       tips=["Nogi pionowo", "Sięgaj dłońmi do palców"]),
    ex("sit_ups", "Siady z leżenia", "core", [], 3, 5.0, ["crunch_down", "sit_ups_up"], 2.6, stress=["plecy"],
       m="abs | quads", tips=["Stopy na podłodze", "Rolluj kręgosłup"]),
    ex("seated_tucks", "Przyciąganie kolan w siadzie", "core", [], 3, 4.5, ["tuck_sit_out", "tuck_sit_in"], 1.8,
       m="abs | quads", tips=["Odchyl się lekko", "Stopy nad podłogą"]),
    ex("side_plank_dips", "Opuszczanie bioder w desce bokiem", "core", [], 3, 4.0, ["side_plank", "side_plank_low"], 2.0,
       uni=True, stress=["barki"], m="obliques | abs abductors", tips=["Łokieć pod barkiem", "Pełny zakres ruchu"]),
    ex("knee_to_elbow", "Kolano do łokcia w staniu", "cardio", [], 1, 4.5, ["stand_hands_head", "knee_elbow",
                                                                         "stand_hands_head", "knee_elbow~"], 1.6,
       m="abs obliques | quads", tips=["Skręć tułów do kolana", "Plecy proste"]),
    ex("kb_russian_twist", "Rosyjski skręt z ciężarem", "core", [], 3, 4.5, ["vsit_a", "vsit_b"], 1.6, eq=["kb|db"],
       hold="kb", stress=["plecy"], m="obliques abs", easier="russian_twist", tips=["Ciężar przy klatce", "Skręcaj tułów"]),

    # --- kardio
    ex("jog_in_place", "Bieg w miejscu", "cardio", [], 1, 7.0, ["jog", "jog~"], 0.6, impact=True,
       m="quads calves | hamstrings", tips=["Lekko na palcach", "Pracuj rękami"]),
    ex("star_jumps", "Gwiazdki", "cardio", [], 3, 9.0, ["squat_jack_in", "star"], 1.2, impact=True, stress=["kolana"],
       m="quads calves shoulders | glutes", tips=["Wyskocz jak najwyżej", "Ląduj na ugiętych nogach"]),
    ex("tuck_jumps", "Wyskoki z kolanami do klatki", "cardio", [], 4, 10.0, ["squat_pulse", "tuck"], 1.2, impact=True,
       stress=["kolana"], m="quads calves | abs glutes", tips=["Kolana wysoko", "Miękkie lądowanie"]),
    ex("jump_rope", "Skakanka bez skakanki", "cardio", [], 2, 9.0, ["hop_down", "hop"], 0.45, impact=True,
       m="calves | shoulders quads", tips=["Małe skoki na palcach", "Kręć nadgarstkami"]),
    ex("lateral_shuffle", "Przeskoki w bok", "cardio", [], 2, 7.0, ["shuffle_a", "shuffle_b", "shuffle_a", "shuffle_b~"], 1.4,
       impact=True, m="quads abductors | calves glutes", tips=["Nisko na nogach", "Szybkie kroki"]),

    # --- mobilność i rozciąganie
    ex("worlds_greatest", "Najlepsze rozciąganie świata", "mobility", [], 2, 3.0, ["wgs_down", "wgs"], 4.0, uni=True,
       m="quads hamstrings | obliques upper_back", tips=["Głęboki wykrok", "Ręka w górę, wzrok za dłonią"]),
    ex("hip_circles", "Krążenia bioder", "warmup", [], 1, 2.5, ["hip_l", "front_stand", "hip_l~", "front_stand"], 3.0,
       m="glutes lower_back | obliques", tips=["Ręce na biodrach", "Duże koła"]),
    ex("leg_swings", "Wymachy nóg", "warmup", [], 1, 3.0, ["leg_swing_f", "leg_swing_b"], 1.4, uni=True,
       m="hamstrings | quads glutes", tips=["Przytrzymaj się ściany", "Rozluźniona noga"]),
    ex("thoracic_open", "Otwieranie klatki w klęku", "mobility", [], 1, 2.5, ["quad", "thoracic_open"], 3.0, uni=True,
       stress=["nadgarstki"], m="upper_back | chest obliques", tips=["Wzrok za ręką", "Biodra nieruchomo"]),
    ex("butterfly", "Motyl", "stretch", [], 1, 2.0, ["butterfly", "butterfly_b"], 4.0, static=True, m="adductors",
       tips=["Stopy razem", "Kolana opadają swobodnie"]),
    ex("calf_stretch", "Rozciąganie łydki przy ścianie", "stretch", [], 1, 2.0, ["calf_wall", dict(P["calf_wall"], t=156)],
       4.0, static=True, uni=True, props=[{"type": "wall", "x": 0.82}], m="calves", tips=["Tylna pięta w podłogę", "Noga prosta"]),
    ex("chest_stretch", "Rozciąganie klatki", "stretch", [], 1, 2.0, ["chest_stretch", dict(P["chest_stretch"], t=183)], 4.0,
       static=True, m="chest shoulders", tips=["Dłonie splecione za plecami", "Łopatki razem"]),
    ex("triceps_stretch", "Rozciąganie tricepsa", "stretch", [], 1, 2.0, ["arm_up_bent", dict(P["arm_up_bent"], h=176)], 4.0,
       static=True, uni=True, m="triceps | lats", tips=["Łokieć przy głowie", "Druga ręka delikatnie dociska"]),
    ex("shoulder_stretch", "Rozciąganie barku", "stretch", [], 1, 2.0, ["shoulder_x", dict(P["shoulder_x"], h=176)], 4.0,
       static=True, uni=True, m="shoulders | upper_back", tips=["Ręka przez klatkę", "Bark nisko"]),
    ex("standing_fold", "Skłon w staniu", "stretch", [], 1, 2.0, ["fold_hold", dict(P["fold"], t=10)], 5.0, static=True,
       m="hamstrings lower_back | calves", tips=["Kolana lekko ugięte", "Głowa luźno"]),
    ex("sphinx", "Sfinks", "stretch", [], 1, 2.0, ["sphinx", dict(P["sphinx"], t=114)], 4.0, static=True,
       m="abs | lower_back", tips=["Łokcie pod barkami", "Biodra na podłodze"]),
    ex("figure_four", "Rozciąganie pośladka w leżeniu", "stretch", [], 1, 2.0, ["knee_hug", dict(P["knee_hug"], t=98)], 4.0,
       static=True, uni=True, m="glutes | lower_back", tips=["Kostka na kolanie drugiej nogi", "Przyciągnij nogę do siebie"]),
    ex("breathing", "Oddychanie przeponowe", "stretch", [], 1, 1.5, ["breath", "breath_b"], 6.0, static=True, m="abs",
       tips=["Wdech nosem — brzuch rośnie", "Długi wydech ustami"]),
]


# ============================================================ v3: brakujące ruchy z Fitify
E += [
    # --- nogi i pośladki
    ex("bridge_march", "Marsz w mostku", "strength", [], 2, 4.0, ["bridge_up", "bridge_march", "bridge_up", "bridge_march~"], 2.6,
       m="glutes hamstrings | abs lower_back", tips=["Biodra nie opadają przy unoszeniu nogi", "Wolno i pod kontrolą"]),
    ex("punch_squat", "Przysiad z ciosami", "cardio", [], 2, 6.5, ["squat_bot", "squat_punch", "squat_bot", "squat_punch~"], 1.6,
       stress=["kolana"], m="quads glutes shoulders | abs", tips=["Zostań nisko w przysiadzie", "Ciosy szybkie, brzuch napięty"]),
    ex("squat_reach", "Przysiad z wyprostem w górę", "strength", [], 1, 5.0, ["squat_bot", "stand_up"], 2.4, stress=["kolana"],
       m="quads glutes | shoulders calves", tips=["Wstając sięgnij rękami do sufitu", "Możesz wspiąć się na palce"]),
    ex("squat_knee", "Przysiad z unoszeniem kolana", "strength", [], 2, 6.0, ["squat_bot", "knee_up", "squat_bot", "knee_up~"],
       2.8, stress=["kolana"], m="quads glutes abs | hamstrings", tips=["Po wstaniu kolano do pasa", "Utrzymaj równowagę"]),
    ex("toe_touch_squat", "Przysiad z dotknięciem palców", "strength", [], 2, 5.0, ["squat_hands", "stand_up"], 2.6,
       stress=["kolana", "plecy"], m="quads glutes | hamstrings shoulders", tips=["Dłonie do palców stóp na dole", "Wyprostuj się z rękami w górze"]),
    ex("chair_pose", "Pozycja krzesła", "strength", [], 2, 3.5, ["chair_pose", dict(P["chair_pose"], t=157)], 3.0, static=True,
       stress=["kolana"], m="quads glutes | shoulders lower_back", tips=["Biodra w tył, ręce w górę", "Ciężar na piętach"]),
    ex("lateral_jump_squat", "Przysiad z przeskokiem w bok", "cardio", [], 3, 8.5, ["sumo_bot", "sumo_jump", "sumo_bot~", "sumo_jump~"],
       1.8, impact=True, stress=["kolana"], m="quads glutes abductors | calves", tips=["Skacz w bok z przysiadu", "Ląduj od razu w przysiadzie"]),
    ex("frog_jumps", "Żabie skoki", "cardio", [], 4, 9.0, ["squat_hands", "frog_air"], 1.6, impact=True, stress=["kolana"],
       m="quads glutes | calves hamstrings", tips=["Dłonie do podłogi, potem skok do przodu", "Miękkie lądowanie"]),
    ex("chair_pistol", "Przysiad na jednej nodze do krzesła", "strength", [], 3, 5.5, ["pistol_bot", "pistol_top"], 3.4,
       uni=True, eq=["chair"], props=[{"type": "chair", "at": "hip", "w": 0.42, "dx": -0.16}], stress=["kolana"],
       m="quads glutes | abs", harder="pistol_squat", tips=["Siadaj na krzesło na jednej nodze", "Wstań bez odpychania rękami"]),
    ex("atg_split_squat", "Przysiad wykroczny z przednią stopą wyżej", "strength", [], 3, 5.5, ["atg_top", "atg_bot"], 3.0,
       uni=True, eq=["chair"], props=[{"type": "chair", "at": "toF", "w": 0.36, "dx": 0.0}], stress=["kolana"],
       m="quads glutes | hamstrings adductors", tips=["Kolano wychodzi daleko przed palce", "Tył uda na łydce na dole"]),
    ex("lunge_knee_drive", "Wykrok z wyjściem kolana", "strength", [], 2, 6.0, ["lunge_down", "knee_up"], 2.4, uni=True,
       stress=["kolana"], m="quads glutes | abs calves", tips=["Z wykroku od razu kolano w górę", "Stabilna noga podporowa"]),
    ex("leg_curl_standing", "Uginanie nogi w tył w staniu", "warmup", [], 1, 3.5, ["stand", "leg_curl", "stand", "leg_curl~"], 1.4,
       m="hamstrings | glutes", tips=["Pięta do pośladka", "Kolana obok siebie"]),
    ex("donkey_straight", "Wymachy prostej nogi w klęku", "strength", [], 2, 3.5, ["quad", "donkey_straight"], 1.8, uni=True,
       stress=["nadgarstki"], m="glutes | hamstrings lower_back", tips=["Noga prosta, stopa napięta", "Nie wyginaj lędźwi"]),
    ex("fire_hydrant", "Odwodzenie nogi w klęku podpartym", "strength", [], 1, 3.5, ["quad", "hydrant"], 1.8, uni=True,
       stress=["nadgarstki"], m="abductors glutes", tips=["Kolano w bok na wysokość biodra", "Miednica nieruchoma"]),
    ex("inner_thigh_raise", "Przywodzenie nogi w leżeniu bokiem", "strength", [], 1, 3.0, ["inner_base", "inner_up"], 1.8, uni=True,
       m="adductors", tips=["Górna noga ugięta przed dolną", "Unoś dolną, prostą nogę"]),
    ex("side_leg_standing", "Odwodzenie nogi w staniu", "warmup", [], 1, 3.0, ["front_stand", "side_leg_out"], 1.6, uni=True,
       m="abductors | glutes", tips=["Tułów prosto", "Palce stopy do przodu"]),

    # --- brzuch i pilates
    ex("supine_march", "Marsz w leżeniu", "core", [], 1, 3.0, ["bridge_down", "supine_march", "bridge_down", "supine_march~"], 2.4,
       m="abs | quads", harder="dead_bug", tips=["Lędźwie przy podłodze", "Kolano nad biodro"]),
    ex("alt_leg_raise", "Naprzemienne unoszenie nóg", "core", [], 1, 3.5, ["legs_low", "alt_leg_up", "legs_low", "alt_leg_up~"], 2.4,
       m="abs | quads", harder="leg_raises", tips=["Nogi proste", "Druga noga nisko nad podłogą"]),
    ex("leg_circles", "Krążenia nogą w leżeniu", "core", [], 2, 3.5, ["circle_a", "circle_b", "circle_c", "circle_d"], 3.2, uni=True,
       m="abs | quads adductors", tips=["Małe koła, miednica nieruchomo", "W połowie zmień kierunek"]),
    ex("crunch_legs_up", "Brzuszki z nogami w górze", "core", [], 2, 4.0, ["crunch_tt_down", "crunch_tt_up"], 2.0, m="abs",
       tips=["Kolana nad biodrami przez cały czas", "Ręce sięgają do kolan"]),
    ex("side_crunch", "Skłony boczne w leżeniu", "core", [], 2, 3.5, ["side_crunch_down", "side_crunch_up"], 2.0, uni=True,
       m="obliques | abs", tips=["Leż na boku, unoś tułów bokiem", "Ruch krótki, kontrolowany"]),
    ex("heel_taps", "Dotykanie pięt", "core", [], 1, 3.5, ["heel_a", "heel_b"], 1.0, m="obliques abs",
       tips=["Łopatki nad podłogą", "Na zmianę dłoń do pięty"]),
    ex("roll_up", "Rolowanie z leżenia do skłonu", "core", [], 3, 4.0, ["v_flat", "rollup_top"], 4.0, stress=["plecy"],
       m="abs | hamstrings", tips=["Kręg po kręgu w górę i w dół", "Bez szarpania"]),
    ex("rolling_ball", "Turlanie w kłębku", "core", [], 2, 3.5, ["ball_up", "ball_back"], 2.0, m="abs | lower_back",
       tips=["Zwiń się w kulkę", "Wróć do siadu bez dotykania stopami podłogi"]),
    ex("hundred", "Setka", "core", [], 3, 4.5, ["hundred_a", "hundred_b"], 0.5, m="abs | quads shoulders",
       tips=["Pompuj prostymi rękami", "5 wdechów, 5 wydechów"]),
    ex("teaser", "Teaser", "core", [], 4, 4.5, ["teaser_low", "teaser_up"], 3.0, stress=["plecy"], m="abs | quads",
       easier="v_ups", tips=["Ręce równolegle do nóg", "Balans na kości ogonowej"]),
    ex("v_sit_hold", "Utrzymanie siadu V", "core", [], 3, 4.0, ["teaser_up", dict(P["teaser_up"], t=-146)], 3.0, static=True,
       stress=["plecy"], m="abs | quads", tips=["Plecy proste", "Nogi ugięte = łatwiej"]),
    ex("torso_twist", "Skręty tułowia w staniu", "warmup", [], 1, 3.0, ["twist_a", "twist_b"], 1.6, m="obliques | upper_back",
       tips=["Biodra przodem", "Ręce luźno za ruchem"]),
    ex("lumbar_rotation", "Skręty bioder w leżeniu", "mobility", [], 1, 2.5, ["bridge_down", "lumbar_side", "bridge_down", "lumbar_side~"],
       4.0, m="obliques lower_back", tips=["Kolana razem opadają na bok", "Łopatki na podłodze"]),
    ex("plank_reach", "Deska z sięganiem ręką", "core", [], 2, 4.0, ["plank", "plank_reach", "plank", "plank_reach~"], 2.4,
       m="abs shoulders | obliques", tips=["Biodra nie skręcają", "Ręka prosto przed siebie"]),
    ex("two_point_plank", "Podpór na ręce i nodze", "core", [], 3, 4.0, ["pushup_top", "two_point", "pushup_top", "two_point~"], 3.0,
       stress=["nadgarstki"], m="abs lower_back shoulders | glutes", tips=["Przeciwna ręka i noga", "Utrzymaj 2–3 s"]),
    ex("plank_jacks", "Pajacyki w desce", "cardio", [], 2, 7.0, ["pushup_top", "plank_hips"], 0.8, impact=True,
       stress=["nadgarstki"], m="abs shoulders | abductors calves", tips=["Stopy skaczą na boki", "Biodra nisko"]),
    ex("plank_jump_in", "Doskoki do rąk z deski", "cardio", [], 3, 8.0, ["pushup_top", "squat_hands"], 1.4, impact=True,
       stress=["nadgarstki", "kolana"], m="abs quads shoulders", tips=["Stopy wskakują pod dłonie", "Wróć do prostej deski"]),
    ex("plank_leg_raise", "Deska z unoszeniem nogi", "core", [], 2, 4.0, ["plank", "plank_leg", "plank", "plank_leg~"], 2.4,
       m="abs glutes | lower_back", tips=["Noga prosta, nie wyżej niż biodro", "Biodra nieruchomo"]),
    ex("scap_pushup", "Pompki łopatkowe", "strength", [], 1, 3.5, ["pushup_top", "scap_low"], 1.6, stress=["nadgarstki"],
       m="upper_back shoulders | chest", tips=["Łokcie proste", "Łopatki razem i od siebie"]),
    ex("reverse_plank_kick", "Deska tyłem z wymachem", "core", [], 3, 4.5, ["rev_plank", "rev_plank_kick", "rev_plank", "rev_plank_kick~"],
       2.4, stress=["nadgarstki", "barki"], m="glutes lower_back shoulders | hamstrings", tips=["Biodra wysoko", "Noga prosta do góry"]),
    ex("crab_walk", "Chód kraba", "cardio", [], 2, 5.0, ["tabletop_up", "crab_step", "tabletop_up", "crab_step~"], 1.4,
       stress=["nadgarstki"], m="triceps glutes shoulders | quads", tips=["Biodra wysoko", "Małe kroki"]),
    ex("side_plank_knee", "Deska bokiem na kolanach", "core", [], 1, 3.5, ["side_plank_knee", dict(P["side_plank_knee"], t=P["side_plank_knee"]["t"] + 1)],
       3.0, static=True, uni=True, m="obliques | abs abductors", harder="side_plank", tips=["Kolana ugięte", "Biodra w górę"]),
    ex("side_plank_leg", "Deska bokiem z unoszeniem nogi", "core", [], 3, 4.0, ["side_plank", "side_plank_leg"], 2.0, uni=True,
       stress=["barki"], m="obliques abductors | glutes abs", tips=["Górna noga prosta", "Biodra wysoko"]),
    ex("ab_rollout", "Kółko do brzucha", "core", [], 4, 5.0, ["roll_kneel", "roll_out"], 3.0, eq=["wheel"], stress=["plecy"],
       m="abs | lats shoulders", tips=["Plecy nie zapadają się", "Wróć siłą brzucha"]),

    # --- plecy, ramiona, barki
    ex("prone_t", "Unoszenie rąk T w leżeniu", "strength", [], 1, 3.0, ["prone_t", "prone_t_up"], 2.4,
       m="upper_back traps | shoulders", tips=["Ręce w bok jak litera T", "Kciuki do sufitu"]),
    ex("wall_pushup", "Pompki przy ścianie", "strength", [], 1, 3.0, ["wall_push_top", "wall_push_bot"], 2.2,
       props=[{"type": "wall", "at": "haN", "dx": 0.03}], m="chest triceps | shoulders", harder="incline_pushups",
       tips=["Ciało proste jak deska", "Klatka do ściany"]),
    ex("hindu_pushup", "Pompki hinduskie", "strength", [], 4, 6.0, ["dog", "pushup_bot", "up_dog"], 3.6,
       stress=["nadgarstki", "barki", "plecy"], m="chest shoulders triceps | lower_back abs",
       tips=["Z psa w dół płynnym łukiem", "Wróć przez pozycję kobry"]),
    ex("swim_strokes", "Kraul w opadzie tułowia", "strength", [], 1, 4.0, ["crawl_a", "crawl_a~"], 1.4, stress=["plecy"],
       m="shoulders upper_back | lats", tips=["Plecy proste w opadzie", "Duże ruchy rękami"]),
    ex("pallof_press", "Wypychanie gumy przed siebie (Pallof)", "core", [], 2, 3.5, ["band_press_in", "band_row_out"], 3.0,
       uni=True, eq=["band"], hold="band", m="obliques abs | shoulders", tips=["Guma zaczepiona z boku", "Nie daj się obrócić"]),
    ex("clap_pushup", "Pompki z klaśnięciem", "strength", [], 5, 8.0, ["pushup_bot", "clap_air"], 1.6, impact=True,
       stress=["nadgarstki", "barki"], m="chest triceps | shoulders", easier="pushups",
       tips=["Wybij się mocno", "Ląduj na ugiętych łokciach"]),
    ex("spiderman_pushup", "Pompki Spidermana", "strength", [], 4, 6.0, ["pushup_top", "spider", "pushup_top", "spider~"], 2.8,
       stress=["nadgarstki"], m="chest triceps obliques | abs shoulders", tips=["Kolano do łokcia przy zejściu", "Biodra nisko"]),
    ex("pushup_tap", "Pompka z dotknięciem barku", "strength", [], 3, 6.0, ["pushup_top", "pushup_bot", "pushup_top", "tap",
                                                                           "pushup_top", "pushup_bot", "pushup_top", "tap~"], 6.0,
       stress=["nadgarstki"], m="chest triceps abs | shoulders", tips=["Po pompce dotknij przeciwnego barku", "Biodra stabilne"]),
    ex("t_pushup", "Pompka z obrotem", "strength", [], 3, 6.0, ["pushup_top", "pushup_bot", "pushup_top", "t_rot"], 3.6,
       stress=["nadgarstki"], m="chest obliques shoulders | triceps", tips=["Po pompce otwórz się do deski bokiem", "Wzrok za ręką"]),
    ex("handstand_pushup", "Pompki w staniu na rękach przy ścianie", "strength", [], 5, 8.0, ["hs_top", "hs_bot"], 3.0,
       props=[{"type": "wall", "at": "toN", "dx": -0.08}], stress=["nadgarstki", "barki"], m="shoulders triceps | traps",
       easier="pike_pushups", tips=["Tylko przy ścianie i na miękkim podłożu", "Głowa schodzi między dłonie"]),

    # --- kardio
    ex("cross_climber", "Wspinaczka skośna", "cardio", [], 3, 8.0, ["pushup_top", "cross_climb", "pushup_top", "cross_climb~"], 0.9,
       stress=["nadgarstki"], m="obliques abs shoulders | quads", tips=["Kolano do przeciwnego łokcia", "Biodra nisko"]),
    ex("step_touch", "Krok dostawny", "warmup", [], 1, 4.0, ["front_stand", "step_touch", "front_stand", "step_touch~"], 1.4,
       m="quads calves | shoulders", tips=["Krok w bok i dostaw nogę", "Ręce w górę przy kroku"]),
    ex("front_kicks", "Wymachy nóg w przód", "warmup", [], 1, 4.5, ["stand", "front_kick", "stand", "front_kick~"], 1.6,
       m="hamstrings quads | abs", tips=["Przeciwna ręka do stopy", "Noga prosta, bez szarpania"]),
    ex("single_leg_hops", "Podskoki na jednej nodze", "cardio", [], 3, 8.0, ["hop_one", "hop_one_up"], 0.5, uni=True, impact=True,
       stress=["kolana"], m="calves quads | glutes", tips=["Małe, sprężyste skoki", "Kolano lekko ugięte"]),
    ex("side_hops", "Przeskoki obunóż w bok", "cardio", [], 2, 8.0, ["feet_hop_a", "feet_hop_b", "feet_hop_a~", "feet_hop_b~"], 1.2,
       impact=True, stress=["kolana"], m="calves quads | abductors", tips=["Stopy razem", "Skacz nad wyobrażoną linią"]),
    ex("side_reach", "Sięganie w bok", "warmup", [], 1, 3.0, ["front_stand", "side_bend", "front_stand", "side_bend~"], 2.0,
       m="obliques lats", tips=["Ręka daleko nad głową", "Biodra stoją w miejscu"]),
    ex("pushup_burpee", "Burpees z pompką", "cardio", [], 5, 11.0,
       ["stand", "squat_hands", "pushup_top", "pushup_bot", "pushup_top", "squat_hands", "jump_up"], 4.0, impact=True,
       stress=["kolana", "nadgarstki"], m="chest quads shoulders | triceps abs glutes", easier="burpees",
       tips=["Pełna pompka na dole", "Wyskok z rękami w górę"]),

    # --- mobilność, rozciąganie, joga
    ex("pigeon", "Pozycja gołębia", "stretch", [], 2, 2.0, ["pigeon", "pigeon_low"], 6.0, static=True, uni=True,
       stress=["kolana"], m="glutes | quads", tips=["Przednie kolano zgięte, goleń przed sobą", "Opuść tułów, jeśli możesz"]),
    ex("thread_needle", "Nawlekanie igły", "mobility", [], 1, 2.5, ["quad", "thread", "quad", "thoracic_open"], 5.0, uni=True,
       stress=["nadgarstki"], m="upper_back | shoulders obliques", tips=["Ręka wsuwa się pod tułów", "Bark do podłogi"]),
    ex("lying_hamstring", "Rozciąganie tyłu uda w leżeniu", "stretch", [], 1, 2.0, ["lying_ham", dict(P["lying_ham"], ln=[-174, -174])],
       5.0, static=True, uni=True, m="hamstrings | calves", tips=["Noga prosta do góry", "Możesz pomóc sobie ręcznikiem"]),
    ex("wide_fold", "Skłon w rozkroku", "stretch", [], 1, 2.0, ["wide_fold", dict(P["wide_fold"], t=18)], 5.0, static=True,
       m="hamstrings adductors | lower_back", tips=["Stopy szeroko", "Głowa i ręce swobodnie w dół"]),
    ex("knee_circles", "Krążenia kolan", "warmup", [], 1, 2.5, ["knee_circ_a", "knee_circ_b"], 1.6, m="quads | calves",
       tips=["Dłonie na kolanach", "Kolana razem, małe koła"]),
    ex("shoulder_rolls", "Krążenia barków", "warmup", [], 1, 2.0, ["stand", "shoulder_up"], 1.6, m="traps shoulders",
       tips=["Barki w górę, w tył i w dół", "Ręce luźno"]),
    ex("neck_tilts", "Skłony głowy na boki", "mobility", [], 1, 1.5, ["neck_l", "neck_l~"], 4.0, m="traps",
       tips=["Ucho do barku", "Bez szarpania i krążenia"]),
    ex("warrior2", "Wojownik II", "stretch", [], 2, 3.0, ["warrior2", dict(P["warrior2"], h=182)], 5.0, static=True, uni=True,
       stress=["kolana"], m="quads adductors | shoulders glutes", tips=["Przednie kolano nad stopą", "Ręce długie, barki nisko"]),
    ex("triangle", "Trójkąt", "stretch", [], 2, 2.5, ["triangle", dict(P["triangle"], h=134)], 5.0, static=True, uni=True,
       m="hamstrings obliques | adductors", tips=["Obie nogi proste", "Klatka otwarta do przodu"]),
    ex("windmill", "Wiatrak", "mobility", [], 1, 3.5, ["windmill", "windmill~"], 2.4, stress=["plecy"],
       m="hamstrings obliques | upper_back", tips=["Dłoń do przeciwnej stopy", "Druga ręka w górę"]),
    ex("standing_backbend", "Odchylenie w staniu", "stretch", [], 1, 2.0, ["stand_up", "backbend"], 4.0, stress=["plecy"],
       m="abs | chest", tips=["Biodra lekko do przodu", "Tylko w komfortowym zakresie"]),
    ex("upper_back_stretch", "Rozciąganie górnej części pleców", "stretch", [], 1, 2.0, ["upper_back", dict(P["upper_back"], h=146)],
       4.0, static=True, m="upper_back | traps shoulders", tips=["Zaokrąglij plecy", "Ręce przed sobą, splecione"]),
    ex("wrist_mobility", "Rozgrzewka nadgarstków", "warmup", [], 1, 1.5, ["wrist_a", "wrist_b"], 1.6, m="forearms",
       tips=["Dłonie w górę i w dół", "Potem krążenia"]),
    ex("ankle_circles", "Krążenia stóp", "warmup", [], 1, 1.5, ["ankle_a", "ankle_b"], 1.4, uni=True, m="calves",
       tips=["Kolano nieruchomo", "Duże koła stopą"]),
    ex("plow", "Pług", "stretch", [], 3, 2.0, ["plow", dict(P["plow"], t=42)], 5.0, static=True, stress=["plecy"],
       m="lower_back hamstrings | traps", tips=["Ciężar na barkach, nie na szyi", "Nie obracaj głowy"]),
    ex("shoulder_stand", "Świeca", "stretch", [], 3, 2.5, ["candle", dict(P["candle"], t=16)], 5.0, static=True, stress=["plecy"],
       m="abs lower_back | traps", tips=["Dłonie podpierają plecy", "Nie obracaj głowy"]),
    ex("fish_pose", "Ryba", "stretch", [], 2, 2.0, ["fish", dict(P["fish"], t=106)], 5.0, static=True, m="chest abs | traps",
       tips=["Klatka w górę, ciężar na łokciach", "Szyja długa"]),
    ex("mountain_pose", "Pozycja góry", "mobility", [], 1, 1.5, ["mountain", dict(P["mountain"], h=182)], 6.0, static=True,
       m="abs | calves", tips=["Stopy razem, ciężar równo", "Spokojny oddech"]),
]

# ------------------------------------------------------------ odpowiedniki nazw z Fitify (do wyszukiwania i importu)
FITIFY = {
    "Chair Squats": "box_squat", "Sumo Chair Squats": "sumo_squat", "Wall Sit": "wall_sit", "Step-Ups": "step_ups",
    "Calf Raises": "calf_raises", "Bridge Pose": "bridge_hold", "Bridges": "glute_bridge", "Bridge Marching": "bridge_march",
    "Bridge Kick": "single_leg_bridge", "Outer Thigh Raises": "side_leg_raise", "Squats": "squat", "Free Arm Squat": "squat",
    "Prisoner's Squat": "prisoner_squat", "Bouncing Squat": "squat_pulse", "Back & Forth Squat": "squat",
    "Punching Squats": "punch_squat", "Squat & Reach": "squat_reach", "Squat & Knee Kick": "squat_knee",
    "Toe Touch Squat": "toe_touch_squat", "Chair Pose": "chair_pose", "Sumo Squat": "sumo_squat", "Jump Squats": "jump_squats",
    "Side-to-Side Jump Squat": "lateral_jump_squat", "Frog Jumps": "frog_jumps", "Pistol Squats": "pistol_squat",
    "One Leg Chair Squats": "chair_pistol", "Bulgarian Squat": "split_squat", "ATG Split Squat": "atg_split_squat",
    "Ski Sit": "wall_sit", "Lunges": "forward_lunge", "Rear Lunges": "reverse_lunge", "Knee-Up Lunge": "lunge_knee_drive",
    "Diagonal Lunges": "curtsy_lunge", "Heisman Lunges": "side_lunge", "Toe Balancing Lunge": "forward_lunge",
    "Jumping Lunges": "jump_lunge", "Lunge Run": "jump_lunge", "Alternating Side Lunge": "side_lunge",
    "Side Lunge March": "side_lunge", "Single Calf Raises": "sl_calf_raise", "Hamstring Kickback": "leg_curl_standing",
    "Warrior III": "sl_rdl", "Donkey Kick": "donkey_kicks", "Straight Leg Donkey Kick": "donkey_straight",
    "Butt Lifters": "glute_bridge", "Bridge Kicker": "single_leg_bridge", "Inner Thigh Raises": "inner_thigh_raise",
    "Outer Thigh Bicycle": "side_leg_raise", "Outer Thigh Triangle": "side_leg_raise", "Side Leg Lift": "side_leg_standing",
    "Seated Leg Scissors": "flutter_kicks", "Fire Hydrants": "fire_hydrant",
    "Seated Core Twist": "russian_twist", "Russian Twist": "russian_twist", "Crunches": "crunches", "Bird Dog": "bird_dog",
    "Supine Marching": "supine_march", "Alternating Leg Raises": "alt_leg_raise", "Single Leg Circles": "leg_circles",
    "Corkscrew": "leg_circles", "Sit-Ups": "sit_ups", "Bicycle Crunches": "bicycle", "Elevated Crunches": "crunch_legs_up",
    "Reaching Crunch": "crunch_legs_up", "Side Crunches": "side_crunch", "Elbow to the Knee": "knee_to_elbow",
    "Heel Touches": "heel_taps", "Belly Penguin": "heel_taps", "Toe Touches": "toe_touches", "Ab Rollups": "roll_up",
    "Dynamic Rollups": "roll_up", "Roll Like a Ball": "rolling_ball", "The Hundred": "hundred", "Hundred Pike": "hundred",
    "Teaser": "teaser", "V Sit-Ups": "v_ups", "V-Sit Hold": "v_sit_hold", "V Sit Rowing": "seated_tucks",
    "Leg Lifts": "leg_raises", "Abdominal Hip Raises": "reverse_crunch", "Mason Twist": "russian_twist",
    "Oblique Rotations": "russian_twist", "Standing Torso Twist": "torso_twist", "Lumbar Rotation": "lumbar_rotation",
    "Mountain Climbers": "mountain_climbers", "Mountain Runner": "mountain_climbers", "Mountain Walkers": "inchworm",
    "Plank": "plank", "High Plank": "high_plank", "One Elbow Plank": "plank_reach", "One Arm Plank": "plank_reach",
    "Two Point Plank": "two_point_plank", "Arm Raise Plank": "plank_reach", "Alternating Plank": "plank_up_down",
    "Walking Plank": "plank_up_down", "Shoulder Tap Plank": "shoulder_taps", "Plank Jacks": "plank_jacks",
    "Plank-Ins": "plank_jump_in", "Jump Planks": "plank_jump_in", "Single Leg Plank": "plank_leg_raise",
    "Plank & Rear Kick": "plank_leg_raise", "Scapular Planks": "scap_pushup", "Reverse Plank": "reverse_plank",
    "Back Plank & Kick": "reverse_plank_kick", "Roof Kickback": "reverse_plank_kick", "Roof Pose": "tabletop",
    "Table Pose": "tabletop", "Crab Walk": "crab_walk", "Side Plank": "side_plank", "Easy Side Plank": "side_plank_knee",
    "Side Plank Raises": "side_plank_dips", "Easy Side Plank Raises": "side_plank_dips", "Side Plank Balancing": "side_plank_leg",
    "Superman": "superman", "Swimmer": "swimmers", "Pulse Rows": "superman_pull", "Reachers": "superman",
    "T Raise": "prone_t", "Y Raise": "prone_y", "Reverse Snow Angels": "reverse_angels",
    "Wall Tricep Press": "wall_pushup", "Shoulder Push-Ups": "pike_pushups", "Hindu Push-Ups": "hindu_pushup",
    "Seal Push-Ups": "knee_pushups", "Forward Arm Circles": "arm_circles", "Backward Arm Circles": "arm_circles",
    "Extended Arm Circles": "small_arm_circles", "Standing Crawl Stroke": "swim_strokes",
    "Standing Butterfly Stroke": "swim_strokes", "Air Row": "scap_squeeze", "Rotation Resistance": "pallof_press",
    "Push-Ups": "pushups", "Diamond Push-Ups": "diamond_pushups", "Narrow Push-Ups": "diamond_pushups",
    "Wide Arm Push-Ups": "wide_pushups", "Incline Push-Ups": "incline_pushups", "Decline Push-Ups": "decline_pushups",
    "Kneeled Push-Ups": "knee_pushups", "Kneeled Diamond Push-Ups": "kpush_narrow", "Kneeled Narrow Push-Ups": "kpush_narrow",
    "Kneeled Wide Push-Ups": "knee_pushups", "Arm Clap Push-Ups": "clap_pushup", "Spiderman Push-Ups": "spiderman_pushup",
    "Grasshopper Push-Ups": "spiderman_pushup", "Single Leg Push-Ups": "pushups", "One Arm Side Push-Ups": "wide_pushups",
    "Shoulder Tap Push-Ups": "pushup_tap", "Push-Up & Rotation": "t_pushup", "Scapular Push-Ups": "scap_pushup",
    "Push-Up & Pike": "plank_to_dog", "Tricep Pikes": "pike_pushups", "Upside Down Push-Ups": "handstand_pushup",
    "Tricep Dips": "floor_dips",
    "Jumping Jacks": "jumping_jacks", "Inchworms": "inchworm", "Twisted Mountain Climber": "cross_climber",
    "March & Clap": "march", "Step Touch": "step_touch", "Front Kicks": "front_kicks", "Toe Touch Walk": "front_kicks",
    "High Knees": "high_knees", "Jogging": "jog_in_place", "Running in Place": "jog_in_place", "Running Sprinter": "jog_in_place",
    "Butt Kickers": "butt_kicks", "Butt Kicks": "butt_kicks", "Two Way Butt Kicks": "butt_kicks", "Scissor Run": "jog_in_place",
    "Cross Country Run": "jog_in_place", "Low Runner": "mountain_climbers", "Single Leg Runner": "single_leg_hops",
    "Jump Rope": "jump_rope", "One Leg Rope Jump": "single_leg_hops", "Star Jump": "star_jumps", "Low Jacks": "step_jacks",
    "Low Jump Jacks": "jumping_jacks", "Cancan Jump": "jumping_jacks", "Puppet Hops": "jumping_jacks",
    "Puppet Spin": "jumping_jacks", "Hero Jump": "tuck_jumps", "High Jump": "jump_squats", "Single Leg Hops": "single_leg_hops",
    "Single Leg Jumps": "single_leg_hops", "Skaters": "skaters", "Side-to-Side Jumps": "side_hops",
    "One Leg Side Hops": "single_leg_hops", "Slalom Hops": "side_hops", "Slow Box": "shadow_boxing",
    "Side to Side Reach": "side_reach", "Burpees": "burpees", "Push-Up Burpees": "pushup_burpee",
    "Running Burpees": "burpees", "Jacks & Burpees": "burpees",
    "Ab Rollouts": "ab_rollout", "Dumbbell Thrusters": "db_thruster",
    "Cat-Cow Pose": "cat_cow", "Elbow Cat-Cow Pose": "cat_cow", "Pigeon Pose": "pigeon", "Lazy Pigeon": "pigeon",
    "Low Cobra": "sphinx", "Swan Pose": "cobra", "Threading the Needle": "thread_needle",
    "Supine Hamstring Stretch": "lying_hamstring", "Seated Forward Bend": "hamstring_stretch",
    "Hurdler Stretch": "hamstring_stretch", "Forward Fold": "standing_fold", "Forward Bend": "standing_fold",
    "Wide Legged Bend": "wide_fold", "Wide Leg Bend": "wide_fold", "Calf & Ham Stretch": "down_dog",
    "Quadricep Stretch": "quad_stretch", "Standing Chest Stretch": "chest_stretch", "Resisted Chest Stretch": "chest_stretch",
    "Shoulder Opener": "chest_stretch", "Hip Circles": "hip_circles", "Knee Circles": "knee_circles",
    "Backward Shoulder Circles": "shoulder_rolls", "Front Shoulder Circles": "shoulder_rolls",
    "Opposite Arm Circles": "arm_circles", "X-Legged Spinal Twist": "lumbar_rotation", "Back Neck Stretch": "neck_tilts",
    "Front Neck Stretch": "neck_tilts", "Side Neck Stretch": "neck_tilts", "Side Neck Resistance": "neck_tilts",
    "Front Neck Resistance": "neck_tilts", "Neck Looking Around": "neck_tilts", "Warrior II": "warrior2",
    "Child Pose": "childs_pose", "Hip Flexor Stretch": "hip_flexor_stretch", "Hip Flexion": "hip_flexor_stretch",
    "Sprinter's Calf Stretch": "calf_stretch", "Lying Glute Stretch": "figure_four", "Butterfly Stretch": "butterfly",
    "Reclined Cobbler's Pose": "butterfly", "Deep Squat Stretch": "deep_squat_hold", "Fish Pose": "fish_pose",
    "Plow Pose": "plow", "Shoulder Stand": "shoulder_stand", "Half Shoulder Stand": "shoulder_stand",
    "Deep Breathing": "breathing", "Namaste Breathing": "breathing", "Mountain Pose": "mountain_pose",
    "Like & Dislike": "neck_tilts", "Triangle Pose": "triangle", "Half Triangle": "triangle",
    "Side Angle Extension": "triangle", "Side Bend": "side_bend", "Side Oblique Stretch": "side_bend",
    "Windmill": "windmill", "Yoga Backbend": "standing_backbend", "Bent Over Stretch": "standing_fold",
    "Bent Over Twist": "windmill", "Upper Back Stretch": "upper_back_stretch", "Deltoid Stretch": "shoulder_stretch",
    "Armpit Check Stretch": "triceps_stretch", "Tricep Stretch": "triceps_stretch", "Chair Pose Twist": "chair_pose",
    "Wrist Circles": "wrist_mobility", "Forearm Stretch": "wrist_mobility", "Back Wrist Stretch": "wrist_mobility",
    "Front Wrist Stretch": "wrist_mobility", "Ankle Twist": "ankle_circles",
}
FITIFY_SKIPPED = {"Barbell Clean": "wymaga sztangi"}
_byid = {e["id"]: e for e in E}
for name, eid in FITIFY.items():
    assert eid in _byid, f"Fitify {name} → brak {eid}"
    _byid[eid].setdefault("aka", []).append(name)

for e in E:
    prim = [k for k, v in e["m"].items() if v >= 1]
    g = []
    for k in prim:
        if MUSCLE_GROUP[k] not in g:
            g.append(MUSCLE_GROUP[k])
    if "całe ciało" in e["groups"] or (e["type"] == "cardio" and len(g) >= 3):
        g.insert(0, "całe ciało")
    e["groups"] = g

ids = [e["id"] for e in E]
assert len(ids) == len(set(ids)), "zduplikowane id"
for e in E:
    for k in e["anim"]["k"]:
        if isinstance(k, str):
            assert k.rstrip("~") in P, f"{e['id']}: brak pozy {k}"
    for rel in ("easier", "harder"):
        if rel in e:
            assert e[rel] in ids, f"{e['id']}: {rel} → {e[rel]}"

# Ustawienie stóp tam, gdzie nie podano go ręcznie (fp = 0):
#  - leżenie przodem i klęk (biodra lub golenie na podłodze): stopy wyprostowane, grzbietem do podłogi,
#  - zwis na drążku: stopy swobodnie opuszczone.
_hang = {k.rstrip("~") for e in E if e["anim"].get("anchor") == "hands" for k in e["anim"]["k"] if isinstance(k, str)}
_ground = {k.rstrip("~") for e in E if e["anim"].get("anchor") != "hands" for k in e["anim"]["k"] if isinstance(k, str)}
for _k, _p in P.items():
    if _p.get("fp") or _p.get("view") == "front" or _p.get("back"):
        continue
    if _k in _hang and _k not in _ground:
        _p["fp"] = 35
        continue
    _j = grounded(_p)
    _h = lambda n: -_j[n][1]
    lying = 60 <= _p.get("t", 180) <= 145 and _h("hip") < 0.16  # na brzuchu
    kneeling = max(_h("knN"), _h("knF")) < 0.155 and max(_h("anN"), _h("anF")) < 0.16  # golenie na podłodze
    if lying or kneeling:
        _p["fp"] = 70

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
print(f"{len(E)} ćwiczeń, {len(P)} póz → {dst.relative_to(ROOT)}; Fitify: {len(FITIFY)} nazw → {len(set(FITIFY.values()))} ćwiczeń")
