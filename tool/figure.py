"""Szkielet postaci Formy — ta sama kinematyka co w lib/ui/figure.dart.

Kąty w stopniach, mierzone od pionu w dół, dodatnie w stronę +x (postać patrzy w prawo):
0 = w dół, 90 = do przodu poziomo, 180 = w górę, -90 = do tyłu poziomo.
Oś y ekranu rośnie w dół; podłoga to y = 0.
"""
import math

TORSO, NECK, HEAD_R = 0.50, 0.07, 0.10
UPPER, FORE = 0.30, 0.28
THIGH, SHIN, FOOT = 0.44, 0.46, 0.10
SHOULDER_W, HIP_W = 0.17, 0.09

DEFAULT = {
    "t": 180, "an": [8, 12], "af": [-8, -4], "ln": [2, 0], "lf": [-2, 0],
    "fp": 0, "fq": [0, 0], "lift": 0, "x": 0, "view": "side", "back": False,
    # ruch poza płaszczyzną: ab — odchylenie kończyn na bok [ręka N, ręka F, noga N, noga F] (stopnie),
    # rot — skręt barków wokół kręgosłupa (stopnie, + = bliższy bark do przodu),
    # sp / se — wysunięcie / uniesienie barków (łopatki, metry)
    "ab": [0, 0, 0, 0], "rot": 0, "sp": 0, "se": 0,
    # kr — kolano odchylone na bok wokół osi biodro–kostka [N, F] (stopnie, + = na zewnątrz; stopa zostaje)
    "kr": [0, 0],
    # tw — sam skręt klatki i głowy (bez ruchu rąk), np. otwieranie klatki z ręką do sufitu
    "tw": 0,
}


def d(a):
    r = math.radians(a)
    return (math.sin(r), math.cos(r))


def add(p, a, length):
    v = d(a)
    return (p[0] + v[0] * length, p[1] + v[1] * length)


def full(pose):
    p = dict(DEFAULT)
    p.update(pose)
    if "h" not in pose:
        p["h"] = p["t"]
    return p


def swap(pose):
    """Druga strona: zamiana kończyn bliższych z dalszymi (w widoku z przodu także odbicie)."""
    p = full(pose)
    q = dict(p)
    q["an"], q["af"] = p["af"], p["an"]
    q["ln"], q["lf"] = p["lf"], p["ln"]
    q["fq"] = [p["fq"][1], p["fq"][0]]
    a = p["ab"]
    q["ab"] = [a[1], a[0], a[3], a[2]]
    q["rot"] = -p["rot"]
    q["tw"] = -p["tw"]
    q["kr"] = [p["kr"][1], p["kr"][0]]
    if p["view"] == "front":
        q["t"] = 360 - p["t"]
        q["h"] = 360 - p["h"]
        q["x"] = -p["x"]
    return q


def joints(pose):
    """Pozycje stawów przed opuszczeniem na podłogę (biodro w (x, 0))."""
    return joints_z(pose)[0]


def joints_z(pose):
    """(stawy, głębokość z) — z tylko dla punktów wysuniętych przed płaszczyznę (skłon w widoku z przodu)."""
    p = full(pose)
    hip = (p["x"], 0.0)
    neck = add(hip, p["t"], TORSO)
    head = add(neck, p["h"], NECK + HEAD_R)
    j = {"hip": hip, "neck": neck, "head": head}
    front = p["view"] == "front"
    td = d(p["t"])
    perp = (-td[1], td[0])
    for side, sgn in (("N", 1), ("F", -1)):
        arm = p["an"] if side == "N" else p["af"]
        leg = p["ln"] if side == "N" else p["lf"]
        if front:
            sh = (neck[0] + perp[0] * SHOULDER_W * sgn, neck[1] + perp[1] * SHOULDER_W * sgn)
            hp = (hip[0] + perp[0] * HIP_W * sgn, hip[1] + perp[1] * HIP_W * sgn)
            m = 1 if side == "N" else -1  # dalsze kończyny odbite lustrzanie
            arm = [a * m for a in arm]
            leg = [a * m for a in leg]
        else:
            sh, hp = neck, hip
        el = add(sh, arm[0], UPPER)
        ha = add(el, arm[1], FORE)
        kn = add(hp, leg[0], THIGH)
        an = add(kn, leg[1], SHIN)
        if front and p.get("kb"):
            # goleń za plecami (poza płaszczyzną): w rzucie z przodu kostka i palce przy kolanie
            an = (kn[0], kn[1] + 0.01)
            toe = an
        elif front:
            out = perp[0] * sgn
            # but widziany od przodu: przedłużenie goleni (pod kostką, gdy stoi), lekko na zewnątrz
            sd = d(leg[1])
            toe = (an[0] + sd[0] * 0.045 + out * 0.02, an[1] + sd[1] * 0.045 + perp[1] * sgn * 0.02)
        else:
            # stopa prostopadle do goleni, palcami do przodu ciała; fp > 0 = wspięcie na palce / wyprost stopy.
            # Na plecach (back) postać jest lustrzanym odbiciem, więc „przód” stopy jest po drugiej stronie.
            fp = p["fp"] + p["fq"][0 if side == "N" else 1]
            fa = leg[1] - 90 + fp if p["back"] else leg[1] + 90 - fp
            toe = add(an, fa, FOOT)
        j.update({f"sh{side}": sh, f"el{side}": el, f"ha{side}": ha,
                  f"hp{side}": hp, f"kn{side}": kn, f"an{side}": an, f"to{side}": toe})
    z = {}
    if front and p.get("fold"):
        # skłon w przód: tułów, głowa i barki obracają się wokół osi bioder do widza; ręce zwisają w płaszczyźnie
        f = math.radians(p["fold"])
        for k in ("neck", "head", "shN", "shF"):
            dy = j[k][1] - hip[1]
            j[k] = (j[k][0], hip[1] + dy * math.cos(f))
            z[k] = -dy * math.sin(f)
        for side in "NF":
            arm = p["an"] if side == "N" else [-a for a in p["af"]]
            el = add(j["sh" + side], arm[0], UPPER)
            j["el" + side] = el
            j["ha" + side] = add(el, arm[1], FORE)
            z["el" + side] = z["ha" + side] = z["sh" + side]
    if any(p["ab"]) or any(p["kr"]) or p["rot"] or p["sp"] or p["se"]:
        _out_of_plane(p, j, z, front)
    return j, z


def base_z(k, front):
    """Głębokość, którą widok 3D nadaje stawom w pozie bez ruchu poza płaszczyzną."""
    if front or k[-1] not in "NF":
        return 0.0
    arm = k[:2] in ("sh", "el", "ha")
    return (1 if k[-1] == "N" else -1) * (SHOULDER_W if arm else HIP_W + 0.01)


def _v(a, b, k=1.0):
    return tuple(x + y * k for x, y in zip(a, b))


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _out_of_plane(p, j, z, front):
    """Łopatki, odchylenie kończyn na bok i skręt tułowia — w 3D; wynik: rzut (x, y) i głębokość z."""
    P = {k: (v[0], v[1], base_z(k, front) + z.get(k, 0.0)) for k, v in j.items()}
    hip, neck = P["hip"], P["neck"]
    u = _v(neck, hip, -1)
    n = math.sqrt(_dot(u, u)) or 1.0
    u = tuple(c / n for c in u)
    if front:
        f = (0.0, 0.0, 1.0)
        L = (-u[1], u[0], 0.0) if (P["shN"][0] - neck[0]) * (-u[1]) + (P["shN"][1] - neck[1]) * u[0] >= 0 else (u[1], -u[0], 0.0)
    else:
        f = (-u[1], u[0], 0.0)
        if p["back"]:
            f = (u[1], -u[0], 0.0)
        L = (0.0, 0.0, 1.0)
    arms = [k + sd for sd in "NF" for k in ("sh", "el", "ha")]
    # 1) łopatki: cała ręka przesuwa się razem z barkiem
    if p["sp"] or p["se"]:
        for k in arms:
            P[k] = _v(_v(P[k], f, p["sp"]), u, p["se"])
    # 1b) kolano na bok wokół osi biodro–kostka (stopa zostaje w miejscu)
    for i, sd in enumerate("NF"):
        a = p["kr"][i]
        if not a:
            continue
        hp, an = P["hp" + sd], P["an" + sd]
        ax = _v(an, hp, -1)
        na = math.sqrt(_dot(ax, ax)) or 1.0
        ax = tuple(c / na for c in ax)
        v = _v(P["kn" + sd], hp, -1)
        par = _dot(v, ax)
        perp = _v(v, ax, -par)
        r = math.sqrt(_dot(perp, perp))
        if r < 1e-6:
            continue
        e1 = tuple(c / r for c in perp)
        S = tuple(c * (1 if sd == "N" else -1) for c in L)
        e2 = _v(_v(S, ax, -_dot(S, ax)), e1, -_dot(S, e1))
        n2 = math.sqrt(_dot(e2, e2)) or 1.0
        e2 = tuple(c / n2 for c in e2)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        P["kn" + sd] = _v(_v(_v(hp, ax, par), e1, r * ca), e2, r * sa)
    # 2) odchylenie kończyn na bok (poza płaszczyznę ruchu)
    for i, (root, pts, sd) in enumerate((("shN", ("elN", "haN"), 1), ("shF", ("elF", "haF"), -1),
                                         ("hpN", ("knN", "anN", "toN"), 1), ("hpF", ("knF", "anF", "toF"), -1))):
        a = p["ab"][i]
        if not a:
            continue
        r = P[root]
        d1 = _v(P[pts[0]], r, -1)
        nd = math.sqrt(_dot(d1, d1)) or 1.0
        d1 = tuple(c / nd for c in d1)
        side = f if front else tuple(c * sd for c in L)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        for k in pts:
            v = _v(P[k], r, -1)
            al = _dot(v, d1)
            rest = _v(v, d1, -al)
            P[k] = _v(_v(_v(r, rest), d1, al * ca), side, al * sa)
    # 3) skręt barków i rąk wokół osi tułowia (przez szyję)
    if p["rot"]:
        c, s_ = math.cos(math.radians(p["rot"])), math.sin(math.radians(p["rot"]))
        for k in arms:
            v = _v(P[k], neck, -1)
            a_, b_, c_ = _dot(v, u), _dot(v, f), _dot(v, L)
            w = _v(_v(tuple(x * a_ for x in u), f, b_ * c + c_ * s_), L, c_ * c - b_ * s_)
            P[k] = _v(neck, w)
    for k, (x, y, zz) in P.items():
        j[k] = (x, y)
        dz = zz - base_z(k, front)
        if abs(dz) > 1e-9:
            z[k] = dz
        else:
            z.pop(k, None)


def grounded(pose, anchor="ground", bar_y=-2.3):
    """Stawy po opuszczeniu na podłogę (najniższy punkt na y=0) i uniesieniu o lift."""
    p = full(pose)
    j = joints(p)
    if anchor == "hands":
        dy = bar_y - j["haN"][1]
    else:
        # uwzględniamy grubość ciała (postać ma objętość), żeby nie „wchodziła” w podłogę
        low = max(v[1] + thickness(k) for k, v in j.items())
        dy = -low - p["lift"]
    return {k: (v[0], v[1] + dy) for k, v in j.items()}


def thickness(joint):
    """Promień ciała wokół stawu (przy opieraniu o podłogę); zgodny z lib/core/figure.dart."""
    k = joint[:-1] if joint[-1] in "NF" else joint
    return {"head": HEAD_R + 0.008, "hip": 0.10, "hp": 0.10, "neck": 0.08, "sh": 0.08,
            "kn": 0.055, "an": 0.045, "to": 0.035}.get(k, 0.04)


def resolve(spec, library):
    """Nazwa pozy z biblioteki; przyrostek ~ oznacza drugą stronę."""
    if isinstance(spec, dict):
        return full(spec)
    name = spec.rstrip("~")
    pose = library[name]
    return swap(pose) if spec.endswith("~") else full(pose)
