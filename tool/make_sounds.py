#!/usr/bin/env python3
"""Krótkie dźwięki Formy (WAV 16-bit mono) — generowane, bez cudzych nagrań."""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def tone(freq, dur, vol=0.5, attack=0.004, decay=None, harm=(1.0, 0.25, 0.08)):
    n = int(RATE * dur)
    decay = decay or dur
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-t / (decay / 4))
        s = sum(a * math.sin(2 * math.pi * freq * (k + 1) * t) for k, a in enumerate(harm))
        out.append(vol * env * s / sum(harm))
    return out


def mix(*parts):
    """(offset_s, samples) → jeden sygnał."""
    n = max(int(o * RATE) + len(p) for o, p in parts)
    buf = [0.0] * n
    for o, p in parts:
        st = int(o * RATE)
        for i, v in enumerate(p):
            buf[st + i] += v
    m = max(1e-9, max(abs(v) for v in buf))
    return [v / m * 0.85 for v in buf] if m > 0.85 else buf


def save(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))


# odliczanie: krótkie „tik”
save("tick", tone(1046.5, 0.09, 0.5, decay=0.08))
# start pracy: dwa tony w górę
save("go", mix((0, tone(784, 0.12, 0.5)), (0.09, tone(1175, 0.22, 0.55))))
# seria zrobiona: ciepły akord
save("set", mix((0, tone(659.3, 0.35, 0.4)), (0.06, tone(830.6, 0.35, 0.35)), (0.12, tone(987.8, 0.45, 0.35))))
# koniec treningu: krótka fanfara
save("finish", mix((0, tone(523.3, 0.18, 0.45)), (0.16, tone(659.3, 0.18, 0.45)), (0.32, tone(784, 0.18, 0.45)),
                   (0.48, tone(1046.5, 0.8, 0.5)), (0.48, tone(784, 0.8, 0.3)), (0.48, tone(659.3, 0.8, 0.25))))
# rekord / odznaka
save("record", mix((0, tone(1318.5, 0.25, 0.4)), (0.08, tone(1568, 0.25, 0.4)), (0.16, tone(2093, 0.5, 0.35))))
print("ok", sorted(p.name for p in OUT.iterdir()))
