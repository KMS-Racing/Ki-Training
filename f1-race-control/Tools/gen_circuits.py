#!/usr/bin/env python3
"""Erzeugt Sources/RaceEngine/Resources/Circuits.json.

Aus groben, von Hand gesetzten Umrissen werden geglaettete Linienzuege mit
gleichmaessig verteilten Punkten. Gleichmaessig ist wichtig: Die Track Map setzt
die Autos ueber den Rundenfortschritt 0..1 auf die Linie. Lagen die Stuetzpunkte
unterschiedlich dicht, wuerden die Autos in manchen Kurven bremsen und auf
Geraden rasen, ohne dass die Engine etwas davon weiss.

Die Layouts sind STILISIERTE Nachbauten, keine vermessenen Koordinaten. Sie geben
die Form und den Charakter einer Strecke wieder, nicht den exakten Verlauf.

    python3 Tools/gen_circuits.py
"""
import json
import math
import os

# y zeigt nach unten (Bildschirmkoordinaten). Start/Ziel ist jeweils Punkt 0.
OUTLINES = {
    # ---- Bereits vorhandene sieben ----------------------------------------
    # Monza: lange Geraden, Schikanen, Parabolica
    "monza": [
        (0.14, 0.88), (0.14, 0.62), (0.15, 0.40), (0.19, 0.30), (0.25, 0.28),
        (0.23, 0.22), (0.28, 0.18), (0.40, 0.13), (0.52, 0.12), (0.60, 0.16),
        (0.58, 0.23), (0.64, 0.25), (0.74, 0.29), (0.80, 0.35), (0.78, 0.42),
        (0.74, 0.50), (0.72, 0.60), (0.66, 0.66), (0.60, 0.68), (0.64, 0.74),
        (0.60, 0.80), (0.50, 0.86), (0.38, 0.92), (0.26, 0.94), (0.17, 0.93),
    ],
    # Spa: La Source, Eau Rouge, Kemmel, Bus Stop
    "spa": [
        (0.20, 0.84), (0.16, 0.80), (0.18, 0.74), (0.24, 0.72), (0.30, 0.66),
        (0.34, 0.56), (0.36, 0.44), (0.42, 0.34), (0.52, 0.28), (0.64, 0.24),
        (0.74, 0.20), (0.82, 0.22), (0.86, 0.30), (0.82, 0.38), (0.74, 0.42),
        (0.68, 0.48), (0.72, 0.56), (0.80, 0.60), (0.84, 0.68), (0.78, 0.76),
        (0.66, 0.80), (0.54, 0.82), (0.44, 0.86), (0.34, 0.90), (0.26, 0.90),
    ],
    # Monaco: enger Stadtkurs, Haarnadel, Hafen
    "monaco": [
        (0.22, 0.78), (0.24, 0.68), (0.28, 0.58), (0.30, 0.48), (0.28, 0.40),
        (0.32, 0.34), (0.40, 0.30), (0.46, 0.24), (0.52, 0.20), (0.58, 0.22),
        (0.60, 0.30), (0.56, 0.36), (0.58, 0.44), (0.66, 0.46), (0.74, 0.48),
        (0.80, 0.54), (0.78, 0.62), (0.70, 0.66), (0.60, 0.68), (0.52, 0.72),
        (0.46, 0.78), (0.38, 0.82), (0.30, 0.84), (0.24, 0.84),
    ],
    # Silverstone: schnelle Bogen, Maggotts/Becketts, Arena
    "silverstone": [
        (0.20, 0.70), (0.22, 0.60), (0.28, 0.52), (0.36, 0.46), (0.44, 0.42),
        (0.52, 0.36), (0.58, 0.28), (0.66, 0.24), (0.74, 0.26), (0.80, 0.32),
        (0.82, 0.40), (0.76, 0.46), (0.68, 0.48), (0.62, 0.54), (0.66, 0.62),
        (0.74, 0.66), (0.78, 0.74), (0.72, 0.80), (0.62, 0.82), (0.52, 0.80),
        (0.44, 0.76), (0.36, 0.78), (0.28, 0.80), (0.22, 0.78),
    ],
    # Bahrain: Stop-and-Go, viele enge Rechtwinkel
    "bahrain": [
        (0.18, 0.80), (0.18, 0.66), (0.20, 0.54), (0.26, 0.48), (0.34, 0.46),
        (0.40, 0.40), (0.38, 0.32), (0.42, 0.24), (0.52, 0.20), (0.62, 0.22),
        (0.68, 0.28), (0.66, 0.36), (0.60, 0.40), (0.62, 0.48), (0.70, 0.50),
        (0.78, 0.52), (0.82, 0.60), (0.78, 0.68), (0.68, 0.72), (0.58, 0.74),
        (0.48, 0.78), (0.38, 0.84), (0.28, 0.86), (0.20, 0.86),
    ],
    # Madrid (Madring): neu im Kalender 2026
    "madrid": [
        (0.20, 0.76), (0.20, 0.64), (0.24, 0.54), (0.30, 0.48), (0.38, 0.44),
        (0.44, 0.38), (0.42, 0.30), (0.48, 0.24), (0.58, 0.22), (0.68, 0.24),
        (0.74, 0.30), (0.72, 0.38), (0.64, 0.42), (0.58, 0.48), (0.62, 0.56),
        (0.72, 0.58), (0.80, 0.62), (0.82, 0.70), (0.76, 0.78), (0.66, 0.80),
        (0.54, 0.78), (0.44, 0.80), (0.34, 0.84), (0.24, 0.82),
    ],
    # Suzuka: Esses, Spoon, 130R
    "suzuka": [
        (0.22, 0.82), (0.22, 0.70), (0.26, 0.60), (0.32, 0.54), (0.38, 0.48),
        (0.44, 0.42), (0.50, 0.36), (0.56, 0.30), (0.64, 0.26), (0.72, 0.26),
        (0.78, 0.32), (0.76, 0.40), (0.68, 0.44), (0.60, 0.48), (0.54, 0.54),
        (0.58, 0.62), (0.66, 0.66), (0.74, 0.70), (0.80, 0.76), (0.74, 0.82),
        (0.62, 0.84), (0.50, 0.82), (0.42, 0.78), (0.34, 0.80), (0.26, 0.84),
    ],

    # ---- Neu fuer den Kalender 2026 ---------------------------------------
    # Melbourne / Albert Park: schnell, um einen See herum
    "melbourne": [
        (0.24, 0.80), (0.20, 0.70), (0.20, 0.58), (0.24, 0.48), (0.32, 0.42),
        (0.42, 0.38), (0.50, 0.32), (0.56, 0.24), (0.64, 0.20), (0.72, 0.22),
        (0.78, 0.28), (0.80, 0.36), (0.76, 0.44), (0.70, 0.50), (0.72, 0.58),
        (0.78, 0.64), (0.80, 0.72), (0.74, 0.80), (0.64, 0.84), (0.54, 0.84),
        (0.44, 0.82), (0.36, 0.84), (0.28, 0.86),
    ],
    # Shanghai: die beruehmte einrollende Schnecke, dann lange Gerade
    "shanghai": [
        (0.20, 0.78), (0.22, 0.66), (0.28, 0.58), (0.36, 0.54), (0.44, 0.50),
        (0.50, 0.44), (0.48, 0.36), (0.42, 0.32), (0.44, 0.24), (0.52, 0.20),
        (0.62, 0.20), (0.70, 0.24), (0.74, 0.32), (0.72, 0.40), (0.66, 0.46),
        (0.68, 0.54), (0.76, 0.58), (0.84, 0.64), (0.84, 0.72), (0.76, 0.78),
        (0.64, 0.82), (0.50, 0.84), (0.38, 0.84), (0.28, 0.84),
    ],
    # Jeddah: sehr schneller Stadtkurs, endlose Mauerbogen
    "jeddah": [
        (0.18, 0.84), (0.16, 0.72), (0.18, 0.60), (0.22, 0.50), (0.26, 0.40),
        (0.30, 0.30), (0.36, 0.22), (0.44, 0.18), (0.54, 0.16), (0.64, 0.18),
        (0.72, 0.22), (0.76, 0.30), (0.72, 0.38), (0.66, 0.42), (0.70, 0.50),
        (0.78, 0.54), (0.84, 0.60), (0.86, 0.68), (0.82, 0.76), (0.72, 0.82),
        (0.60, 0.86), (0.46, 0.88), (0.34, 0.88), (0.24, 0.88),
    ],
    # Miami: schneller Teil plus enge Schikanen ums Stadion
    "miami": [
        (0.22, 0.80), (0.20, 0.68), (0.24, 0.58), (0.32, 0.52), (0.40, 0.48),
        (0.46, 0.40), (0.44, 0.32), (0.50, 0.26), (0.60, 0.22), (0.70, 0.24),
        (0.76, 0.30), (0.74, 0.38), (0.68, 0.44), (0.70, 0.52), (0.78, 0.56),
        (0.82, 0.64), (0.78, 0.72), (0.68, 0.78), (0.56, 0.82), (0.44, 0.84),
        (0.34, 0.86), (0.26, 0.86),
    ],
    # Montreal: Rechtecke auf einer Insel, Wall of Champions
    "montreal": [
        (0.16, 0.78), (0.16, 0.64), (0.18, 0.52), (0.24, 0.44), (0.32, 0.40),
        (0.40, 0.36), (0.46, 0.30), (0.52, 0.24), (0.62, 0.22), (0.72, 0.24),
        (0.80, 0.30), (0.82, 0.40), (0.78, 0.48), (0.72, 0.52), (0.76, 0.60),
        (0.82, 0.68), (0.78, 0.76), (0.68, 0.80), (0.56, 0.82), (0.44, 0.82),
        (0.32, 0.82), (0.22, 0.82),
    ],
    # Barcelona: zwei lange Rechtsbogen, technischer Schlusssektor
    "barcelona": [
        (0.20, 0.76), (0.20, 0.62), (0.24, 0.50), (0.32, 0.42), (0.42, 0.36),
        (0.52, 0.30), (0.62, 0.26), (0.72, 0.28), (0.78, 0.34), (0.80, 0.42),
        (0.76, 0.50), (0.68, 0.54), (0.60, 0.56), (0.56, 0.62), (0.62, 0.68),
        (0.70, 0.72), (0.74, 0.78), (0.68, 0.84), (0.56, 0.86), (0.44, 0.84),
        (0.34, 0.82), (0.26, 0.82),
    ],
    # Red Bull Ring: kurz, drei Bergaufbremspunkte
    "spielberg": [
        (0.22, 0.78), (0.22, 0.64), (0.26, 0.52), (0.34, 0.44), (0.44, 0.38),
        (0.56, 0.32), (0.66, 0.28), (0.74, 0.30), (0.78, 0.38), (0.74, 0.46),
        (0.66, 0.50), (0.62, 0.58), (0.68, 0.64), (0.76, 0.68), (0.78, 0.76),
        (0.70, 0.82), (0.58, 0.84), (0.46, 0.84), (0.34, 0.82), (0.26, 0.82),
    ],
    # Zandvoort: Duenenkurs mit ueberhoehten Kurven
    "zandvoort": [
        (0.22, 0.80), (0.20, 0.68), (0.22, 0.56), (0.28, 0.46), (0.36, 0.40),
        (0.44, 0.34), (0.50, 0.26), (0.58, 0.20), (0.68, 0.20), (0.76, 0.26),
        (0.78, 0.34), (0.72, 0.42), (0.64, 0.46), (0.60, 0.54), (0.66, 0.60),
        (0.74, 0.64), (0.80, 0.72), (0.74, 0.80), (0.62, 0.84), (0.50, 0.86),
        (0.38, 0.86), (0.28, 0.84),
    ],
    # Hungaroring: enge Kartbahn im Grossformat
    "budapest": [
        (0.22, 0.80), (0.22, 0.68), (0.26, 0.58), (0.32, 0.50), (0.30, 0.42),
        (0.36, 0.34), (0.44, 0.30), (0.52, 0.26), (0.62, 0.24), (0.70, 0.28),
        (0.74, 0.36), (0.70, 0.44), (0.62, 0.48), (0.58, 0.54), (0.64, 0.60),
        (0.72, 0.64), (0.78, 0.70), (0.74, 0.78), (0.64, 0.82), (0.52, 0.84),
        (0.40, 0.84), (0.30, 0.84),
    ],
    # Baku: Schlosspassage und eine sehr lange Gerade
    "baku": [
        (0.16, 0.86), (0.16, 0.74), (0.16, 0.62), (0.18, 0.50), (0.22, 0.40),
        (0.28, 0.32), (0.34, 0.26), (0.40, 0.20), (0.46, 0.16), (0.52, 0.20),
        (0.54, 0.28), (0.58, 0.34), (0.66, 0.36), (0.74, 0.38), (0.80, 0.44),
        (0.82, 0.52), (0.80, 0.62), (0.76, 0.72), (0.68, 0.80), (0.56, 0.86),
        (0.44, 0.90), (0.32, 0.90), (0.22, 0.90),
    ],
    # Singapur: Nachtrennen, 19 Kurven zwischen Mauern
    "singapore": [
        (0.20, 0.82), (0.18, 0.72), (0.20, 0.62), (0.26, 0.54), (0.32, 0.48),
        (0.30, 0.40), (0.36, 0.34), (0.44, 0.30), (0.50, 0.24), (0.58, 0.22),
        (0.66, 0.24), (0.72, 0.30), (0.70, 0.38), (0.64, 0.44), (0.68, 0.52),
        (0.76, 0.56), (0.82, 0.62), (0.80, 0.70), (0.72, 0.78), (0.62, 0.82),
        (0.50, 0.86), (0.38, 0.86), (0.28, 0.86),
    ],
    # Austin / COTA: Bergaufkurve 1, Esses nach Silverstone-Vorbild
    "austin": [
        (0.20, 0.80), (0.18, 0.68), (0.22, 0.56), (0.30, 0.48), (0.38, 0.42),
        (0.46, 0.36), (0.54, 0.30), (0.62, 0.24), (0.72, 0.24), (0.80, 0.30),
        (0.82, 0.38), (0.76, 0.46), (0.68, 0.50), (0.62, 0.56), (0.66, 0.64),
        (0.74, 0.68), (0.78, 0.76), (0.70, 0.82), (0.58, 0.84), (0.46, 0.84),
        (0.34, 0.84), (0.26, 0.84),
    ],
    # Mexiko-Stadt: duenne Luft, Stadionabschnitt
    "mexico": [
        (0.18, 0.80), (0.16, 0.68), (0.18, 0.56), (0.24, 0.46), (0.34, 0.40),
        (0.44, 0.36), (0.54, 0.30), (0.64, 0.26), (0.74, 0.28), (0.80, 0.34),
        (0.80, 0.42), (0.74, 0.48), (0.66, 0.52), (0.64, 0.60), (0.70, 0.66),
        (0.66, 0.72), (0.58, 0.74), (0.52, 0.70), (0.46, 0.74), (0.44, 0.82),
        (0.34, 0.86), (0.24, 0.86),
    ],
    # Interlagos: gegen den Uhrzeigersinn, Senna-S, bergauf ins Ziel
    "interlagos": [
        (0.24, 0.82), (0.20, 0.72), (0.22, 0.62), (0.28, 0.54), (0.26, 0.46),
        (0.32, 0.38), (0.42, 0.32), (0.52, 0.28), (0.62, 0.24), (0.72, 0.26),
        (0.78, 0.34), (0.76, 0.42), (0.68, 0.48), (0.62, 0.54), (0.66, 0.62),
        (0.74, 0.68), (0.78, 0.76), (0.70, 0.82), (0.58, 0.86), (0.46, 0.86),
        (0.34, 0.86),
    ],
    # Las Vegas: Strip-Gerade, ansonsten fast nur Rechtwinkel
    "lasvegas": [
        (0.14, 0.82), (0.14, 0.70), (0.14, 0.58), (0.16, 0.46), (0.22, 0.36),
        (0.30, 0.28), (0.40, 0.22), (0.52, 0.18), (0.64, 0.18), (0.74, 0.22),
        (0.82, 0.28), (0.84, 0.38), (0.82, 0.48), (0.78, 0.58), (0.80, 0.68),
        (0.76, 0.78), (0.66, 0.84), (0.54, 0.88), (0.42, 0.90), (0.30, 0.90),
        (0.20, 0.88),
    ],
    # Losail: schnelle Bogen, extrem reifenfressend
    "losail": [
        (0.22, 0.80), (0.20, 0.68), (0.22, 0.56), (0.28, 0.46), (0.36, 0.38),
        (0.46, 0.32), (0.56, 0.26), (0.66, 0.24), (0.76, 0.28), (0.80, 0.36),
        (0.80, 0.46), (0.74, 0.54), (0.66, 0.58), (0.62, 0.64), (0.68, 0.70),
        (0.74, 0.76), (0.68, 0.82), (0.56, 0.86), (0.44, 0.86), (0.32, 0.84),
    ],
    # Yas Marina: Saisonfinale, lange Geraden mit engen Kurven dazwischen
    "yasmarina": [
        (0.18, 0.80), (0.18, 0.68), (0.20, 0.56), (0.26, 0.46), (0.34, 0.40),
        (0.44, 0.36), (0.54, 0.32), (0.62, 0.26), (0.72, 0.24), (0.80, 0.28),
        (0.82, 0.36), (0.76, 0.44), (0.68, 0.48), (0.66, 0.56), (0.72, 0.62),
        (0.80, 0.68), (0.78, 0.76), (0.68, 0.82), (0.56, 0.84), (0.44, 0.84),
        (0.32, 0.84), (0.24, 0.84),
    ],
}

SAMPLES = 160  # so viele Punkte bekommt die fertige Linie


def catmull_rom(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return (
        0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
               + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
               + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
        0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
               + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
               + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
    )


def smooth_closed(points, per_segment=12):
    n = len(points)
    out = []
    for i in range(n):
        p0, p1 = points[(i - 1) % n], points[i]
        p2, p3 = points[(i + 1) % n], points[(i + 2) % n]
        for s in range(per_segment):
            out.append(catmull_rom(p0, p1, p2, p3, s / per_segment))
    return out


def resample_even(points, count):
    """Punkte gleichmaessig ueber die Streckenlaenge verteilen."""
    n = len(points)
    seg = []
    total = 0.0
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        seg.append(math.hypot(b[0] - a[0], b[1] - a[1]))
        total += seg[-1]

    out = []
    target = 0.0
    step = total / count
    idx = 0
    walked = 0.0
    for _ in range(count):
        while walked + seg[idx] < target and idx < n - 1:
            walked += seg[idx]
            idx += 1
        a, b = points[idx], points[(idx + 1) % n]
        t = (target - walked) / seg[idx] if seg[idx] > 1e-12 else 0.0
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        target += step
    return out


def layout_for(key):
    pts = resample_even(smooth_closed(OUTLINES[key]), SAMPLES)
    return [{"x": round(x, 5), "y": round(y, 5)} for x, y in pts]


def circuit(cid, name, country, km, laps, base, spread, pit, overtaking, wear, rain):
    return dict(
        id=cid, name=name, country=country, lengthKm=km, defaultLaps=laps,
        baseLapTime=base, paceSpread=spread, pitLaneLoss=pit,
        overtakingDifficulty=overtaking, tyreWear=wear, rainProbability=rain,
        sectorSplits=[0.33, 0.66], layout=layout_for(cid),
    )


# baseLapTime entspricht ungefaehr einer Pole-Runde: perfektes Auto, perfekter
# Fahrer, frische Softs, trocken. Alles andere rechnet die Engine oben drauf.
CIRCUITS = [
    circuit("melbourne", "Albert Park Circuit", "Australia",
            5.278, 58, 76.0, 2.5, 21.0, 0.45, 1.05, 0.25),
    circuit("shanghai", "Shanghai International Circuit", "China",
            5.451, 56, 92.5, 2.7, 22.0, 0.30, 1.25, 0.30),
    circuit("suzuka", "Suzuka International Racing Course", "Japan",
            5.807, 53, 90.0, 2.8, 21.0, 0.55, 1.30, 0.35),
    circuit("bahrain", "Bahrain International Circuit", "Bahrain",
            5.412, 57, 91.5, 2.5, 22.5, 0.30, 1.40, 0.03),
    circuit("jeddah", "Jeddah Corniche Circuit", "Saudi Arabia",
            6.174, 50, 88.0, 2.6, 20.0, 0.35, 1.10, 0.02),
    circuit("miami", "Miami International Autodrome", "United States",
            5.412, 57, 87.5, 2.6, 20.5, 0.35, 1.25, 0.30),
    circuit("montreal", "Circuit Gilles-Villeneuve", "Canada",
            4.361, 70, 72.5, 2.3, 18.5, 0.30, 0.95, 0.30),
    circuit("monaco", "Circuit de Monaco", "Monaco",
            3.337, 78, 72.0, 2.2, 19.0, 0.92, 0.75, 0.25),
    circuit("barcelona", "Circuit de Barcelona-Catalunya", "Spain",
            4.657, 66, 71.5, 2.4, 21.5, 0.65, 1.35, 0.15),
    circuit("spielberg", "Red Bull Ring", "Austria",
            4.318, 71, 64.0, 2.0, 19.0, 0.22, 1.15, 0.35),
    circuit("silverstone", "Silverstone Circuit", "Great Britain",
            5.891, 52, 87.0, 2.7, 20.5, 0.35, 1.35, 0.40),
    circuit("spa", "Circuit de Spa-Francorchamps", "Belgium",
            7.004, 44, 105.5, 3.0, 19.5, 0.25, 1.25, 0.45),
    circuit("budapest", "Hungaroring", "Hungary",
            4.381, 70, 76.0, 2.3, 20.0, 0.80, 1.20, 0.20),
    circuit("zandvoort", "Circuit Zandvoort", "Netherlands",
            4.259, 72, 70.0, 2.2, 20.0, 0.75, 1.20, 0.35),
    circuit("monza", "Autodromo Nazionale Monza", "Italy",
            5.793, 53, 80.5, 2.6, 22.0, 0.20, 1.05, 0.15),
    circuit("madrid", "Madring", "Spain",
            5.474, 57, 88.0, 2.5, 21.5, 0.60, 1.10, 0.10),
    circuit("baku", "Baku City Circuit", "Azerbaijan",
            6.003, 51, 102.0, 2.8, 19.0, 0.25, 0.95, 0.10),
    circuit("singapore", "Marina Bay Street Circuit", "Singapore",
            4.940, 62, 90.0, 2.5, 27.0, 0.78, 1.15, 0.35),
    circuit("austin", "Circuit of the Americas", "United States",
            5.513, 56, 93.0, 2.7, 21.0, 0.32, 1.30, 0.25),
    circuit("mexico", "Autodromo Hermanos Rodriguez", "Mexico",
            4.304, 71, 76.0, 2.4, 22.0, 0.40, 0.90, 0.20),
    circuit("interlagos", "Autodromo Jose Carlos Pace", "Brazil",
            4.309, 71, 70.0, 2.4, 20.0, 0.28, 1.20, 0.45),
    circuit("lasvegas", "Las Vegas Strip Circuit", "United States",
            6.201, 50, 94.0, 2.6, 20.5, 0.25, 0.85, 0.05),
    circuit("losail", "Lusail International Circuit", "Qatar",
            5.419, 57, 82.0, 2.5, 24.0, 0.50, 1.45, 0.03),
    circuit("yasmarina", "Yas Marina Circuit", "Abu Dhabi",
            5.281, 58, 84.0, 2.5, 21.0, 0.55, 1.10, 0.02),
]

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(here, "Sources", "RaceEngine", "Resources", "Circuits.json")
with open(out, "w") as f:
    json.dump(CIRCUITS, f, indent=1)

print("geschrieben:", out)
print(f"{len(CIRCUITS)} Strecken")
missing = set(c["id"] for c in CIRCUITS) - set(OUTLINES)
if missing:
    raise SystemExit(f"FEHLER: kein Umriss fuer {missing}")
