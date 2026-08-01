# 🧠 Ki-Training

Projekte, in denen eine KI etwas **lernt** – durch Ausprobieren und Belohnungen
(Reinforcement Learning). Alles läuft direkt im Browser, keine Installation nötig,
komplett auf Deutsch kommentiert.

## 🏁 KI-Ausbruch (`ki-ausbruch/`)
Drei Lern-Methoden treten in einem Labyrinth **gegeneinander** an:
- **Q-Learning** – lernt nach jedem Schritt, optimistisch
- **SARSA** – lernt nach jedem Schritt, vorsichtiger
- **Monte-Carlo** – lernt erst am Ende jeder Runde

Keine KI kennt die Karte – sie finden den Weg nur über **Belohnungen** heraus
und dürfen sich dabei verirren. Man schaut ihnen **live** beim Lernen zu:
Lernkurve, Neugier und Rangliste. Klickt man eine Methode an, sieht man
genauere Statistiken; sonst nur die Grund-Infos.

Drei Labyrinthe: **leicht / mittel / schwer**.

➡️ Einfach `ki-ausbruch/index.html` im Browser öffnen und „Wettkampf starten“.

## 🚗 KI-Autofahren (`autofahren/`)
Dieselben drei Methoden lernen jetzt **Autofahren**: Sie müssen eine
Rundstrecke fahren und dabei die **Kontrollpunkte 1→2→3→4** der Reihe nach
abfahren. Das Auto kann nur lenken (links/geradeaus/rechts); ins Gras fahren =
**Crash**, Versuch vorbei. Keine KI kennt die Strecke – sie lernen nur durchs
Fahren, Crashen und Belohnungen. Auch hier: Rangliste, Lernkurve und
anklickbare Detail-Statistiken pro Methode.

➡️ Einfach `autofahren/index.html` im Browser öffnen.

## Geplant
- 🧩 **Coding-Level** – kommt noch
