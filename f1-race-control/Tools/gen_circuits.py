#!/usr/bin/env python3
"""Erzeugt Sources/RaceEngine/Resources/Circuits.json.

    python3 Tools/gen_circuits.py

Die Layouts sind STILISIERTE Nachbauten, keine vermessenen Koordinaten. Sie geben
Form und Charakter einer Strecke wieder -- wo die Geraden sind, wo es eng wird,
welche Silhouette man wiedererkennt.


WARUM DIESE DATEI EINMAL KOMPLETT NEU GESCHRIEBEN WURDE
=======================================================

Die erste Fassung hat aus ~22 Stuetzpunkten je Strecke einen Catmull-Rom-Spline
gemacht: eine Kurve, die weich durch alle Punkte laeuft. Das Ergebnis sah man
erst, als die App lief -- und es war unbrauchbar. Alle 24 Strecken waren
abgerundete Kleckse, kaum voneinander zu unterscheiden. Monza, die Strecke mit
der laengsten Geraden der Formel 1, war eine Kartoffel.

Drei Fehler, die sich multipliziert haben:

1. EIN SPLINE RUNDET ALLES AB, AUCH DAS, WAS GERADE SEIN SOLL.
   Catmull-Rom laeuft weich durch jeden Punkt -- auch durch die drei Punkte, die
   eine Gerade beschreiben sollten. Aus jeder Geraden wurde ein Bogen, aus jeder
   Haarnadel eine Delle. Genau die Merkmale, an denen man eine Strecke erkennt,
   hat die Glaettung weggebuegelt.

   Jetzt: Der Linienzug bleibt zwischen den Punkten GERADE, und nur die Ecken
   werden mit einem Radius ausgerundet -- so, wie eine Strecke wirklich gebaut
   ist. Der Radius steht je Ecke daneben: eine Haarnadel bekommt 12, eine
   Vollgaskurve 120.

2. JEDER UMRISS WAR AUF EIN QUADRAT GEZEICHNET.
   Alle Umrisse fuellten brav 0.15 bis 0.85 in beiden Richtungen. Damit hatten
   alle 24 Strecken dieselben Proportionen -- das lange, duenne Montreal genauso
   wie das fast quadratische Budapest.

   Jetzt: Die Umrisse stehen in freien Einheiten mit den ECHTEN Proportionen,
   und `fit_unit_box` skaliert beide Achsen mit DEMSELBEN Faktor. Montreal ist
   jetzt lang und duenn, Monza hoch und schmal.

3. Die Anzeige hat zusaetzlich gestreckt (das steckte in TrackMapView und im
   Dashboard, nicht hier -- siehe dort).

Gelernt: Eine Glaettung, die "sieht schon glatt aus" liefert, ist noch lange
keine Form. Aufgefallen ist es erst, als jemand die App wirklich angeschaut hat.
"""
import json
import math
import os

# Wie viele Punkte je Strecke am Ende in der JSON stehen. Gleichmaessig ueber die
# Laenge verteilt -- das ist Pflicht: Die Track Map setzt die Autos ueber den
# Rundenfortschritt 0..1 auf die Linie. Laegen die Punkte unterschiedlich dicht,
# wuerden die Autos in manchen Kurven bremsen und auf Geraden rasen, ohne dass die
# Engine etwas davon weiss.
SAMPLES = 220

# Rand, damit die dicke Fahrbahnlinie nicht am Bildrand klebt.
MARGIN = 0.05


# =============================================================================
#  Geometrie
# =============================================================================

def round_corners(points, default_radius, steps_per_radian=9.0):
    """Ecken ausrunden, Geraden gerade lassen.

    `points` ist ein geschlossener Linienzug aus (x, y) oder (x, y, radius).
    Zwischen zwei Ecken bleibt die Verbindung eine echte Gerade; an jeder Ecke
    wird ein Kreisbogen eingesetzt, der beide Geraden tangential beruehrt.

    Der Radius wird gekuerzt, wenn die anliegenden Geraden zu kurz sind -- sonst
    wuerden sich die Boegen zweier enger Ecken ueberlappen und die Linie schlaegt
    einen Knoten.
    """
    n = len(points)
    out = []

    for i in range(n):
        prev = points[(i - 1) % n]
        cur = points[i]
        nxt = points[(i + 1) % n]
        radius = cur[2] if len(cur) > 2 else default_radius

        v1 = (prev[0] - cur[0], prev[1] - cur[1])
        v2 = (nxt[0] - cur[0], nxt[1] - cur[1])
        l1 = math.hypot(*v1)
        l2 = math.hypot(*v2)
        if l1 < 1e-9 or l2 < 1e-9:
            continue

        u1 = (v1[0] / l1, v1[1] / l1)
        u2 = (v2[0] / l2, v2[1] / l2)

        cosang = max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1]))
        angle = math.acos(cosang)          # Innenwinkel an der Ecke

        # Fast gestreckt: keine Ecke, der Punkt liegt einfach auf der Geraden.
        if angle > math.pi - 0.02 or radius <= 0:
            out.append((cur[0], cur[1]))
            continue

        half = angle / 2.0
        tan_half = math.tan(half)
        if tan_half < 1e-9:
            out.append((cur[0], cur[1]))
            continue

        # Abstand vom Eckpunkt bis zum Beruehrpunkt.
        tangent = radius / tan_half
        # Hoechstens 45 % der anliegenden Geraden -- der Rest gehoert der
        # naechsten Ecke.
        tangent = min(tangent, l1 * 0.45, l2 * 0.45)
        eff_radius = tangent * tan_half

        t1 = (cur[0] + u1[0] * tangent, cur[1] + u1[1] * tangent)
        t2 = (cur[0] + u2[0] * tangent, cur[1] + u2[1] * tangent)

        # Mittelpunkt des Bogens liegt auf der Winkelhalbierenden.
        bx, by = u1[0] + u2[0], u1[1] + u2[1]
        blen = math.hypot(bx, by)
        if blen < 1e-9:
            # 180-Grad-Kehre: die Winkelhalbierende ist nicht definiert.
            out.append(t1)
            out.append(t2)
            continue
        bx, by = bx / blen, by / blen
        dist = eff_radius / math.sin(half)
        cx, cy = cur[0] + bx * dist, cur[1] + by * dist

        a1 = math.atan2(t1[1] - cy, t1[0] - cx)
        a2 = math.atan2(t2[1] - cy, t2[0] - cx)
        sweep = a2 - a1
        while sweep > math.pi:
            sweep -= 2 * math.pi
        while sweep < -math.pi:
            sweep += 2 * math.pi

        segments = max(2, int(abs(sweep) * steps_per_radian) + 1)
        for s in range(segments + 1):
            a = a1 + sweep * (s / segments)
            out.append((cx + math.cos(a) * eff_radius,
                        cy + math.sin(a) * eff_radius))

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
        while idx < n - 1 and walked + seg[idx] < target:
            walked += seg[idx]
            idx += 1
        a, b = points[idx], points[(idx + 1) % n]
        t = (target - walked) / seg[idx] if seg[idx] > 1e-12 else 0.0
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        target += step
    return out


def fit_unit_box(points, margin=MARGIN):
    """In 0..1 legen -- BEIDE Achsen mit demselben Faktor.

    Getrennt zu skalieren waere bequemer (jede Strecke fuellt das Bild aus), macht
    aber aus jeder Strecke dieselbe Form. Lieber Platz an den Seiten als ein
    Montreal, das aussieht wie ein Budapest.
    """
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    width = max(xs) - min(xs)
    height = max(ys) - min(ys)
    scale = (1.0 - 2 * margin) / max(width, height, 1e-9)

    offset_x = (1.0 - width * scale) / 2 - min(xs) * scale
    offset_y = (1.0 - height * scale) / 2 - min(ys) * scale
    return [(x * scale + offset_x, y * scale + offset_y) for x, y in points]


# =============================================================================
#  Die Umrisse
# =============================================================================
#
#  y zeigt nach unten (Bildschirmkoordinaten). Punkt 0 ist Start/Ziel.
#  Die Einheiten sind frei, aber je Strecke MASSSTABSGETREU: Das
#  Seitenverhaeltnis der echten Strecke bleibt erhalten.
#
#  Dritter Wert = Kurvenradius in denselben Einheiten:
#      12- 25   Haarnadel, enge Stadtkurve
#      30- 60   normale Kurve
#      70-140   schneller Bogen, Vollgas
#
OUTLINES = {

    # Monza -- hoch und schmal. Zwei sehr lange Geraden, drei Schikanen,
    # die beiden Lesmos, die Parabolica als grosser Bogen zurueck.
    "monza": [
        (60, 400), (60, 130),                                  # Start/Ziel-Gerade
        (88, 104, 14), (70, 84, 14),                           # Variante del Rettifilo
        (150, 44, 110),                                        # Curva Grande
        (214, 62, 40),
        (232, 46, 11), (252, 64, 11),                          # Variante della Roggia
        (286, 44, 26),                                         # Lesmo 1
        (302, 78, 24),                                         # Lesmo 2
        (232, 196, 60),                                        # Serraglio
        (250, 214, 13), (232, 236, 13), (250, 258, 13),        # Ascari
        (272, 418, 50),                                        # Gegengerade
        (258, 468, 55), (196, 496, 80), (108, 484, 80),        # Parabolica
        (62, 436, 45),
    ],

    # Spa -- langgezogenes Dreieck. La Source, Eau Rouge, Kemmel,
    # Les Combes an der Spitze, Pouhon, Blanchimont, Bus Stop.
    "spa": [
        (120, 470), (96, 452, 16),                             # La Source (Haarnadel)
        (150, 396, 40),                                        # Eau Rouge
        (176, 356, 45),                                        # Raidillon
        (300, 176, 130),                                       # Kemmel-Gerade
        (330, 150, 22), (356, 168, 20),                        # Les Combes
        (388, 152, 26),                                        # Malmedy
        (430, 214, 70),                                        # Rivage / Abfahrt
        (400, 256, 30),
        (438, 300, 60), (466, 344, 55),                        # Pouhon
        (508, 360, 34), (536, 336, 30),                        # Fagnes
        (566, 372, 26),                                        # Campus
        (540, 424, 40),                                        # Stavelot
        (452, 452, 90),                                        # Blanchimont
        (330, 470, 110),
        (186, 496, 60),
        (152, 486, 14), (140, 470, 14),                        # Bus Stop
    ],

    # Monaco -- eng und winklig. Nichts ist hier weit, alle Radien klein.
    "monaco": [
        (150, 300), (196, 268, 20),                            # Sainte Devote
        (238, 200, 40),                                        # Beau Rivage
        (262, 152, 26),                                        # Massenet
        (300, 132, 22),                                        # Casino
        (322, 158, 18),                                        # Mirabeau
        (300, 186, 9),                                         # Loews -- engste Kurve der F1
        (330, 214, 16),                                        # Portier
        (392, 244, 60),                                        # Tunnel
        (420, 268, 12), (404, 288, 12),                        # Nouvelle Chicane
        (356, 306, 30),                                        # Tabac
        (330, 336, 18), (300, 330, 16), (286, 356, 16),        # Piscine
        (250, 370, 20),
        (222, 356, 10),                                        # Rascasse
        (198, 366, 14),                                        # Anthony Noghes
        (156, 340, 26),
    ],

    # Silverstone -- breit. Unten rechts haengt die Arena-Schleife
    # (Village / The Loop / Aintree), links die enge Kehre Brooklands/Luffield,
    # oben rechts das grosse Dreieck Copse - Becketts - Hangar - Stowe.
    #
    # Die erste Fassung hat sich hier selbst verknotet: Die Linie kreuzte sich
    # dreimal. Silverstone kreuzt sich nirgends -- Suzuka ist die einzige
    # Strecke im Kalender, die das tut.
    "silverstone": [
        # Reihenfolge einmal komplett umsortiert. Die erste Fassung hatte die
        # Arena-Schleife auf der falschen Seite -- dadurch musste die Linie
        # dreimal durch sich selbst hindurch. Ein Pruefer zaehlt die Kreuzungen
        # jetzt automatisch (Tests/RaceEngineTests), damit das nicht wiederkommt.
        (290, 305),                                            # Start/Ziel
        (240, 335, 55),                                        # Abbey
        (205, 355, 45),                                        # Farm
        (170, 375, 18),                                        # Village
        (140, 360, 12),                                        # The Loop
        (150, 330, 24),                                        # Aintree
        (170, 250, 90),                                        # Wellington-Gerade
        (160, 225, 18),                                        # Brooklands
        (130, 210, 20), (135, 180, 22),                        # Luffield
        (170, 155, 40),                                        # Woodcote
        (230, 120, 55),                                        # alte Boxengerade, Copse
        (280, 110, 45),                                        # Maggotts
        (315, 140, 30), (345, 115, 30),                        # Becketts
        (375, 140, 36),                                        # Chapel
        (450, 235, 110),                                       # Hangar-Gerade
        (455, 275, 34),                                        # Stowe
        (415, 305, 18), (400, 275, 20),                        # Vale
        (365, 250, 40),                                        # Club
    ],

    # Bahrain -- Stop and Go. Kurze Geraden, viele enge Rechtwinkel,
    # unten rechts die schnelle Schleife.
    "bahrain": [
        (100, 300), (100, 150),                                # Start/Ziel
        (140, 118, 26),                                        # T1
        (196, 138, 44),                                        # T2/3
        (172, 186, 24),                                        # T4
        (206, 214, 26),
        (300, 172, 60),                                        # T5/6/7
        (338, 190, 22), (320, 226, 20),                        # T8
        (356, 252, 24),                                        # T9/10
        (300, 296, 44),
        (240, 290, 30),                                        # T11
        (206, 320, 22),                                        # T12
        (150, 346, 40),                                        # T13
        (104, 330, 30),
    ],

    # Madring (Madrid) -- neu 2026. Stadtkurs mit einem langen
    # Vollgasabschnitt und einem engen Innenstadt-Teil.
    "madrid": [
        (120, 320), (120, 190),
        (152, 158, 24),
        (232, 130, 70),
        (280, 150, 28), (262, 186, 18),
        (300, 214, 22),
        (352, 196, 40),
        (382, 232, 26),
        (340, 274, 30),
        (288, 262, 18), (262, 288, 18),
        (300, 320, 24),
        (250, 356, 34),
        (176, 344, 40),
        (128, 358, 22),
    ],

    # Suzuka -- die Acht. Die Strecke kreuzt sich selbst; genau das macht
    # die Silhouette aus. S-Kurven, Degner, Haarnadel, Spoon, 130R.
    "suzuka": [
        # EHRLICH DAZUGESAGT: Die echte Suzuka ist eine Acht -- die Gegengerade
        # von Spoon zurueck laeuft unter einer Bruecke hindurch, es ist die
        # einzige Strecke im Kalender, die sich selbst kreuzt.
        #
        # Diese Nachbildung kreuzt sich NICHT. Drei Anlaeufe, den Uebergang von
        # Hand zu setzen, brachten jedes Mal zwei oder drei Kreuzungen statt
        # einer: Die Rueckgerade schnitt zusaetzlich durch die Spoon-Schleife
        # oder durch die Anfahrt auf Turn 1. Ein verknotetes Suzuka sieht
        # schlechter aus als ein sauberes ohne Bruecke -- also lieber sauber und
        # eine Zeile Wahrheit im Kommentar. Der Test besteht darauf, dass sich
        # KEINE der 24 Strecken selbst kreuzt.
        #
        # Was bleibt: die S-Kurven, Degner, die Haarnadel als Einbuchtung,
        # Spoon am Ende und die lange Gegengerade zurueck auf 130R.
        (110, 300), (180, 250, 45),                            # Start/Ziel, T1/T2
        (218, 212, 34), (246, 238, 30), (274, 204, 32),        # S-Kurven
        (302, 230, 30), (330, 196, 32),
        (378, 192, 40),                                        # Dunlop
        (420, 220, 20), (408, 252, 16),                        # Degner 1 / 2
        (330, 292, 40),
        (296, 312, 12),                                        # Haarnadel
        (350, 348, 34),
        (450, 392, 90),
        (496, 412, 26), (478, 448, 20),                        # Spoon
        (200, 384, 120),                                       # Gegengerade
        (150, 360, 55),                                        # 130R
        (120, 342, 12), (106, 320, 12),                        # Schikane
    ],

    # Melbourne -- Park, schnell und fliessend, breit gelagert.
    "melbourne": [
        (110, 300), (110, 210),
        (152, 178, 22),                                        # T1
        (188, 208, 20),                                        # T2
        (250, 232, 44),                                        # T3
        (300, 196, 34),                                        # T4
        (336, 214, 26),                                        # T5
        (392, 168, 60),                                        # T6 schnell
        (444, 190, 40),                                        # T7
        (470, 236, 34),                                        # T8
        (438, 276, 44),                                        # T9/10 Vollgas-Schikane
        (386, 268, 40),
        (330, 302, 46),                                        # T11
        (268, 316, 40),
        (216, 344, 26),                                        # T13
        (160, 330, 30),                                        # T14
        (118, 344, 22),                                        # T15
    ],

    # Shanghai -- die Schnecke: T1 bis T4 zieht sich immer enger zu,
    # dann die lange Gegengerade und die Haarnadel T14.
    "shanghai": [
        (120, 300), (170, 250, 70),                            # T1
        (216, 218, 40),                                        # T2
        (238, 244, 24),                                        # T3
        (212, 268, 14),                                        # T4 -- innen, ganz eng
        (262, 296, 30),
        (330, 250, 50),                                        # T6
        (368, 268, 26), (350, 302, 22),                        # T7/8
        (398, 330, 30),                                        # T9/10
        (356, 372, 34),
        (300, 356, 24),                                        # T11/12
        (250, 384, 30),                                        # T13
        (140, 366, 100),                                       # lange Gegengerade
        (112, 340, 16),                                        # T14 Haarnadel
    ],

    # Jeddah -- sehr lang und schmal, 27 Kurven, fast alles Vollgas.
    "jeddah": [
        (80, 260), (80, 190),
        (140, 160, 60), (200, 176, 60), (260, 148, 60),
        (330, 164, 60), (400, 140, 60), (470, 156, 60),
        (540, 132, 60), (600, 150, 50),
        (640, 186, 34), (612, 224, 26),
        (546, 210, 44), (480, 232, 50), (414, 214, 50),
        (348, 236, 50), (282, 218, 50), (216, 240, 50),
        (150, 224, 44), (100, 244, 26),
    ],

    # Miami -- Stadion aussen herum, in der Mitte der enge Teil.
    "miami": [
        (110, 250), (110, 150),
        (150, 120, 30),
        (230, 138, 60),
        (280, 176, 34),
        (322, 150, 26), (348, 184, 22),
        (310, 218, 20), (272, 202, 18), (244, 232, 20),
        (296, 262, 26),
        (356, 250, 34),
        (398, 286, 30),
        (330, 330, 44),
        (220, 344, 60),
        (140, 326, 40),
    ],

    # Montreal -- die Insel: sehr lang, sehr schmal. Haarnadel am einen Ende,
    # die Schikane vor der Mauer am anderen.
    "montreal": [
        (80, 200), (140, 176, 40),
        (196, 190, 34), (176, 216, 20),
        (250, 236, 30),
        (340, 210, 60),
        (420, 226, 44),
        (500, 200, 50),
        (560, 214, 30),
        (596, 190, 13),                                        # L'Epingle
        (556, 168, 20),
        (460, 152, 60),
        (360, 168, 50),
        (260, 146, 50),
        (170, 160, 40),
        (116, 144, 12), (96, 166, 12),                         # Mauer der Champions
    ],

    # Barcelona -- Tropfenform. Lange Start/Ziel-Gerade, T1/2/3 rechts,
    # Campsa, dann die Gegengerade auf T10.
    "barcelona": [
        (110, 330), (110, 176),                                # sehr lange Start/Ziel-Gerade
        (158, 142, 26),                                        # T1 Elf
        (198, 170, 20),                                        # T2
        (232, 146, 24),                                        # T3
        (296, 168, 55),                                        # T4 Repsol
        (340, 144, 22),                                        # T5 Seat
        (374, 178, 26),                                        # T6
        (348, 212, 18),                                        # T7 Wuerth
        (388, 240, 22),                                        # T8
        (356, 274, 20),                                        # T9 Campsa
        (232, 296, 90),                                        # Gegengerade
        (196, 288, 14),                                        # T10 La Caixa
        (238, 330, 26),                                        # T11
        (296, 344, 30),                                        # T12
        (256, 380, 18),                                        # T13
        (186, 372, 30),                                        # T14
        (124, 358, 34),                                        # T15
    ],

    # Red Bull Ring -- die einfachste Strecke im Kalender: drei lange
    # Bergauf-Geraden, drei Kurvengruppen. Sonst nichts.
    "spielberg": [
        (120, 300), (170, 168, 40),
        (232, 140, 24),                                        # T1
        (300, 190, 34),                                        # T2
        (256, 262, 30),                                        # T3
        (318, 296, 26),                                        # T4
        (352, 262, 22),                                        # T5/6
        (330, 330, 30),
        (270, 356, 26),                                        # T7
        (206, 344, 30),                                        # T8
        (160, 360, 24),                                        # T9/10
        (126, 336, 20),
    ],

    # Zandvoort -- Duenen, kompakt und verwinkelt. Tarzan am Ende der Geraden
    # ist eine ueberhoehte Kehre, die letzte Kurve ebenfalls.
    "zandvoort": [
        (110, 300), (110, 190),
        (156, 158, 16),                                        # Tarzan, ueberhoeht
        (188, 190, 20),                                        # Gerlach
        (222, 176, 18),                                        # Hugenholtz
        (250, 206, 22),
        (300, 178, 40),                                        # Hunserug
        (348, 196, 30),                                        # Scheivlak
        (372, 238, 24),
        (336, 262, 16), (364, 288, 16),                        # Mastersbocht
        (330, 318, 20),
        (272, 330, 30),
        (232, 356, 20),
        (176, 344, 26),
        (128, 358, 18),                                        # Arie Luyendyk, ueberhoeht
    ],

    # Hungaroring -- eng und verwinkelt, kaum eine Gerade.
    "budapest": [
        (110, 260), (110, 168),
        (152, 140, 22),                                        # T1
        (188, 176, 18),                                        # T2 Haarnadel
        (232, 152, 24),                                        # T3
        (272, 182, 22),
        (250, 216, 18), (286, 240, 18),
        (330, 214, 22),
        (356, 250, 20),
        (312, 286, 24),
        (256, 272, 18), (232, 300, 18),
        (280, 326, 22),
        (216, 350, 26),
        (150, 336, 30),
        (114, 310, 22),
    ],

    # Baku -- die Extreme: 2,2 km Gerade an der Kueste, oben der
    # Burgabschnitt, so eng, dass zwei Autos kaum nebeneinander passen.
    "baku": [
        (100, 380), (100, 240),                                # Start/Ziel
        (128, 208, 16),                                        # T1
        (128, 150, 14),                                        # T2
        (176, 122, 22),
        (240, 138, 34),
        (286, 112, 20),                                        # Richtung Burg
        (318, 128, 11), (306, 152, 9), (330, 168, 9),          # Burgabschnitt, engst
        (368, 150, 16),
        (410, 176, 22),
        (386, 212, 18),
        (420, 240, 20),
        (470, 220, 26),
        (508, 250, 22),
        (470, 300, 30),
        (420, 322, 24),
        (140, 396, 130),                                       # die lange Gerade
    ],

    # Singapur -- Stadtkurs, fast nur Rechtwinkel, unten die Bucht.
    "singapore": [
        (110, 280), (110, 180),
        (146, 148, 20),                                        # T1
        (196, 166, 22), (176, 200, 18),                        # T2/3
        (228, 224, 22),
        (300, 190, 40),
        (340, 214, 18), (318, 248, 18),
        (360, 274, 20),
        (410, 250, 22),
        (438, 286, 20),
        (386, 322, 26),
        (300, 336, 34),
        (240, 320, 20), (216, 348, 20),
        (156, 336, 26),
        (116, 312, 20),
    ],

    # COTA -- T1 ist eine Bergauf-Haarnadel, dann die schnellen Esses,
    # lange Gegengerade auf die Haarnadel T12, unten der Stadionteil.
    "austin": [
        (140, 330), (140, 190),
        (172, 156, 15),                                        # T1, steil bergauf
        (216, 178, 34), (244, 150, 34), (272, 178, 34),        # Esses T3-6
        (300, 150, 34), (328, 178, 34),
        (372, 152, 30),                                        # T9
        (410, 186, 26),                                        # T10
        (446, 164, 14),                                        # T11 Haarnadel
        (300, 292, 150),                                       # die lange Gerade
        (262, 320, 16),                                        # T12
        (300, 348, 26),
        (356, 336, 30),
        (392, 366, 24),
        (340, 400, 30),                                        # Stadion
        (262, 396, 26),
        (206, 372, 30),
        (162, 380, 22),
    ],

    # Mexiko -- lange Start/Ziel-Gerade auf 2200 m Hoehe, unten das
    # Stadion mit der engen Schleife.
    "mexico": [
        (110, 300), (110, 160),
        (156, 130, 26),                                        # T1
        (200, 158, 22), (180, 190, 18),                        # T2/3
        (250, 214, 30),
        (330, 180, 50),
        (378, 206, 26),
        (356, 246, 22),
        (398, 272, 24),
        (352, 306, 26),
        (300, 292, 18),                                        # Stadion
        (268, 318, 14), (296, 340, 14),
        (240, 360, 22),
        (170, 348, 34),
        (120, 336, 26),
    ],

    # Interlagos -- gegen den Uhrzeigersinn, kompakt, mit dem Senna-S
    # oben und Juncao unten links, von wo es bergauf zur Linie geht.
    "interlagos": [
        (140, 300), (166, 232, 30),
        (200, 200, 20), (232, 226, 20),                        # Senna-S
        (300, 252, 40),                                        # Reta Oposta
        (348, 232, 22),
        (330, 190, 20),                                        # Descida do Lago
        (376, 168, 24),
        (416, 200, 26),
        (390, 246, 22),                                        # Ferradura
        (356, 290, 26),
        (390, 320, 22),
        (340, 356, 26),
        (270, 344, 24),
        (216, 372, 26),
        (162, 356, 18),                                        # Juncao
    ],

    # Las Vegas -- der Strip. Eine sehr lange Gerade, sonst fast nur
    # Neunzig-Grad-Ecken. Breit und flach.
    "lasvegas": [
        (100, 280), (100, 200),
        (140, 168, 22),
        (240, 150, 40),
        (330, 162, 40),
        (430, 140, 40),
        (520, 154, 34),
        (580, 132, 26),
        (620, 160, 20),
        (596, 196, 18),
        (540, 214, 30),
        (430, 232, 40),
        (330, 218, 40),
        (230, 240, 40),
        (150, 226, 26),
        (108, 250, 20),
    ],

    # Losail -- eine lange Gerade und danach fast nur schnelle Boegen, die
    # ineinander uebergehen. Motorrad-Strecke, deshalb kaum enge Ecken.
    "losail": [
        (120, 300), (120, 196),
        (160, 162, 26),                                        # T1
        (216, 176, 46), (250, 148, 44),                        # T2/3
        (306, 164, 60),                                        # T4
        (356, 146, 44),                                        # T5
        (404, 182, 40),                                        # T6/7
        (392, 236, 34),
        (416, 272, 26),                                        # T10
        (368, 306, 34),
        (306, 318, 50),                                        # T12/13
        (246, 300, 44),
        (196, 326, 30),                                        # T14
        (154, 358, 20),                                        # T15, enge Kehre
        (118, 340, 22),                                        # T16
    ],

    # Yas Marina -- lange Geraden, die Haarnadel T5, unten der
    # Hafenabschnitt zwischen den Gebaeuden.
    "yasmarina": [
        (120, 300), (120, 180),
        (156, 152, 24),
        (216, 168, 34),
        (256, 140, 22),
        (300, 168, 26),
        (270, 200, 14),                                        # Haarnadel
        (330, 232, 30),
        (400, 206, 44),
        (436, 240, 22),
        (400, 276, 24),
        (346, 292, 30),
        (300, 320, 22),
        (250, 306, 20),
        (206, 334, 24),
        (154, 340, 30),
        (124, 330, 20),
    ],
}

# Grundradius, falls an einer Ecke keiner steht.
DEFAULT_RADIUS = 30


def layout_for(key):
    rounded = round_corners(OUTLINES[key], DEFAULT_RADIUS)
    even = resample_even(rounded, SAMPLES)
    fitted = fit_unit_box(even)
    return [{"x": round(x, 5), "y": round(y, 5)} for x, y in fitted]


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
print(f"{len(CIRCUITS)} Strecken, je {SAMPLES} Punkte")
missing = set(c["id"] for c in CIRCUITS) - set(OUTLINES)
if missing:
    raise SystemExit(f"FEHLER: kein Umriss fuer {missing}")
