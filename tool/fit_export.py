#!/usr/bin/env python3
"""Wzorcowy zapis FIT (ten sam algorytm co lib/core/fit.dart) — do testu bajt w bajt i sprawdzenia dekoderem Garmina."""
import struct
import sys
from datetime import datetime, timezone

FIT_EPOCH = 631065600
ENUM, U8, U16, U32, U32Z = (0x00, 1), (0x02, 1), (0x84, 2), (0x86, 4), (0x8C, 4)
INVALID = {0x00: 0xFF, 0x02: 0xFF, 0x84: 0xFFFF, 0x86: 0xFFFFFFFF, 0x8C: 0}
FMT = {1: "<B", 2: "<H", 4: "<I"}

CRC_TABLE = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
             0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]


def crc16(data, crc=0):
    for b in data:
        tmp = CRC_TABLE[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ CRC_TABLE[b & 0xF]
        tmp = CRC_TABLE[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ CRC_TABLE[(b >> 4) & 0xF]
    return crc


# komunikat: (lokalny numer, globalny numer, [(pole, typ)])
MSGS = {
    "file_id": (0, 0, [(0, ENUM), (1, U16), (2, U16), (3, U32Z), (4, U32)]),
    "event": (1, 21, [(253, U32), (0, ENUM), (1, ENUM)]),
    "record": (2, 20, [(253, U32), (3, U8)]),
    "set": (3, 225, [(254, U32), (0, U32), (3, U16), (4, U16), (5, U8), (6, U32), (7, U16), (8, U16), (10, U16)]),
    "lap": (4, 19, [(253, U32), (0, ENUM), (1, ENUM), (2, U32), (7, U32), (8, U32), (11, U16), (15, U8), (16, U8),
                    (25, ENUM), (39, ENUM)]),
    "session": (5, 18, [(253, U32), (0, ENUM), (1, ENUM), (2, U32), (5, ENUM), (6, ENUM), (7, U32), (8, U32), (11, U16),
                        (16, U8), (17, U8), (25, U16), (26, U16)]),
    "activity": (6, 34, [(253, U32), (0, U32), (1, U16), (2, ENUM), (3, ENUM), (4, ENUM), (5, U32)]),
}


class Writer:
    def __init__(self):
        self.buf = bytearray()
        self.defined = set()

    def msg(self, name, values):
        local, glob, fields = MSGS[name]
        if name not in self.defined:
            self.defined.add(name)
            self.buf += bytes([0x40 | local, 0, 0]) + struct.pack("<H", glob) + bytes([len(fields)])
            for num, (bt, size) in fields:
                self.buf += bytes([num, size, bt])
        self.buf.append(local)
        for (num, (bt, size)), v in zip(fields, values):
            self.buf += struct.pack(FMT[size], INVALID[bt] if v is None else v)

    def file(self):
        header = bytes([14, 0x20]) + struct.pack("<H", 2132) + struct.pack("<I", len(self.buf)) + b".FIT"
        header += struct.pack("<H", crc16(header))
        body = header + bytes(self.buf)
        return body + struct.pack("<H", crc16(body))


def fit_ts(dt):
    return int(dt.timestamp()) - FIT_EPOCH


def session_fit(start, end, sets, hr, kcal, avg_hr, max_hr, sub_sport, serial, utc_offset):
    """sets: [(sekundy, powtórzenia|None, kategoria, podtyp|None)]"""
    w = Writer()
    t0, t1 = fit_ts(start), fit_ts(end)
    elapsed = t1 - t0
    w.msg("file_id", [4, 255, 1, serial, t1])
    w.msg("event", [t0, 0, 0])
    for i, b in enumerate(hr):
        if i * 5 > elapsed:
            break
        if b > 0:
            w.msg("record", [t0 + i * 5, b])
    work = sum(s[0] for s in sets)
    gap = max(0, elapsed - work) // max(1, len(sets))
    t = t0
    for i, (sec, reps, cat, sub) in enumerate(sets):
        w.msg("set", [t + sec, sec * 1000, reps, None, 1, t, cat, sub, i])
        t += sec + gap
    w.msg("event", [t1, 0, 4])
    w.msg("lap", [t1, 9, 1, t0, elapsed * 1000, elapsed * 1000, kcal, avg_hr, max_hr, 10, sub_sport])
    w.msg("session", [t1, 8, 1, t0, 10, sub_sport, elapsed * 1000, elapsed * 1000, kcal, avg_hr, max_hr, 0, 1])
    w.msg("activity", [t1, elapsed * 1000, 1, 0, 26, 1, t1 + utc_offset])
    return w.file()


if __name__ == "__main__":
    st = datetime(2026, 11, 2, 18, 0, tzinfo=timezone.utc)
    en = datetime(2026, 11, 2, 18, 10, tzinfo=timezone.utc)
    data = session_fit(st, en, [(40, 12, 22, 77), (30, None, 19, 43)], [100, 0, 120], 80, None, None, 20, 7, 0)
    open(sys.argv[1], "wb").write(data)
    print(len(data), "B")
