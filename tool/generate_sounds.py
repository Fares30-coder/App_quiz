"""Génère les effets sonores de Quizzéo (synthèse, aucune source externe).

Usage : python3 tool/generate_sounds.py
Écrit des WAV mono 16 bits 44,1 kHz dans assets/sounds/.
Sons créés pour le projet et versés dans le domaine public (CC0 1.0).
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def bell(freq, seconds, decay=8.0, volume=1.0):
    """Note de type clochette : fondamentale + harmoniques, attaque douce, déclin exponentiel."""
    n = int(RATE * seconds)
    attack = int(RATE * 0.004)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * t) * min(1.0, i / attack if attack else 1.0)
        s = (
            math.sin(2 * math.pi * freq * t)
            + 0.35 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-4 * t)
            + 0.12 * math.sin(2 * math.pi * freq * 3 * t) * math.exp(-8 * t)
        )
        out.append(volume * env * s / 1.47)
    return out


def mix(base, other, offset_s=0.0):
    start = int(RATE * offset_s)
    need = start + len(other)
    if need > len(base):
        base = base + [0.0] * (need - len(base))
    for i, v in enumerate(other):
        base[start + i] += v
    return base


def fade_out(samples, seconds=0.03):
    n = min(len(samples), int(RATE * seconds))
    for i in range(n):
        samples[-1 - i] *= i / n
    return samples


def normalize(samples, peak):
    m = max(abs(s) for s in samples) or 1.0
    return [s * peak / m for s in samples]


def write(name, samples, peak):
    samples = fade_out(normalize(samples, peak))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
                for s in samples
            )
        )


def correct():
    """« Ding » court (≈ 300 ms) : deux notes montantes (mi 6 puis si 6)."""
    s = silence(0.30)
    s = mix(s, bell(1318.5, 0.12, decay=14), 0.0)
    s = mix(s, bell(1975.5, 0.22, decay=12), 0.07)
    return s[: int(RATE * 0.30)]


def wrong():
    """Son neutre et discret (≈ 220 ms) : « bop » grave légèrement descendant."""
    n = int(RATE * 0.22)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        freq = 260 - 80 * (t / 0.22)
        phase += 2 * math.pi * freq / RATE
        env = math.exp(-14 * t) * min(1.0, i / (RATE * 0.006))
        out.append(env * (math.sin(phase) + 0.2 * math.sin(2 * phase)))
    return out


def streak():
    """« Flamme » (≈ 500 ms) : souffle montant + petit arpège brillant."""
    rng = random.Random(42)
    n = int(RATE * 0.5)
    out = []
    low = 0.0
    for i in range(n):
        t = i / RATE
        # Bruit filtré (passe-bas qui s'ouvre) : effet de flamme qui s'embrase.
        alpha = 0.02 + 0.25 * (t / 0.5)
        low += alpha * (rng.uniform(-1, 1) - low)
        env = math.sin(math.pi * min(1.0, t / 0.45)) ** 2
        out.append(0.55 * env * low)
    out = mix(out, bell(784.0, 0.30, decay=9, volume=0.5), 0.12)
    out = mix(out, bell(1046.5, 0.30, decay=9, volume=0.5), 0.20)
    out = mix(out, bell(1568.0, 0.30, decay=8, volume=0.6), 0.28)
    return out[:n]


def fanfare():
    """Fanfare courte (≈ 1 s) : arpège do-mi-sol-do puis accord final."""
    s = silence(1.0)
    notes = [523.25, 659.25, 783.99]
    for k, f in enumerate(notes):
        s = mix(s, bell(f, 0.25, decay=10, volume=0.8), 0.09 * k)
    for f in (523.25, 659.25, 783.99, 1046.5):
        s = mix(s, bell(f, 0.73, decay=4.5, volume=0.6), 0.27)
    return s[: int(RATE * 1.0)]


if __name__ == "__main__":
    write("correct.wav", correct(), 0.7)
    write("wrong.wav", wrong(), 0.4)
    write("streak.wav", streak(), 0.7)
    write("fanfare.wav", fanfare(), 0.7)
    print("Sons écrits dans", OUT)
