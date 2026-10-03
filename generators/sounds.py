#!/usr/bin/env python3
"""Synthesise the 'hacker' sound theme: short retro terminal beeps.

usage: sounds.py OUTPUT_THEME_DIR
"""
import math
import os
import struct
import sys
import wave

RATE = 44100


def tone(freq, dur, vol=0.35, square=True):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        s = math.sin(2 * math.pi * freq * i / RATE)
        v = ((1 if s >= 0 else -1) * 0.6 + s * 0.4) if square else s
        envelope = min(1, i / 200, (n - i) / 400)  # tiny fades so there is no click
        out.append(v * vol * envelope)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def save(folder, name, samples):
    with wave.open(f"{folder}/{name}.wav", "w") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<hh", int(x * 32767), int(x * 32767)) for x in samples))


def main():
    dst = sys.argv[1]
    stereo = f"{dst}/stereo"
    os.makedirs(stereo, exist_ok=True)

    message = tone(1320, .05) + silence(.03) + tone(1760, .07)
    alert = tone(440, .09, .3)
    login = sum((tone(f, .06) + silence(.015) for f in (660, 880, 1100, 1320)), []) + tone(1760, .18, .3, False)
    plug_in = tone(880, .05) + tone(1320, .06)
    unplug = tone(1320, .05) + tone(880, .06)
    done = tone(1100, .05) + silence(.02) + tone(1100, .05)

    for name in ("message-new-instant", "message"):
        save(stereo, name, message)
    for name in ("bell-window-system", "bell-terminal", "dialog-warning", "dialog-error", "bell"):
        save(stereo, name, alert)
    for name in ("desktop-login", "service-login"):
        save(stereo, name, login)
    save(stereo, "device-added", plug_in)
    save(stereo, "device-removed", unplug)
    for name in ("complete", "screen-capture"):
        save(stereo, name, done)

    with open(f"{dst}/index.theme", "w") as f:
        f.write("[Sound Theme]\nName=Hacker\nComment=Short retro terminal beeps\n"
                "Inherits=freedesktop\nDirectories=stereo\n\n[stereo]\nOutputProfile=stereo\n")
    print("sounds written")


if __name__ == "__main__":
    main()
