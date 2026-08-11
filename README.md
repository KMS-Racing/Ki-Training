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

## 🔐 KI-Labor Escape Room (`escape-room/`)
Kein Lern-Projekt, sondern ein **Rätsel-Spiel für Menschen**: Du bist im
geheimen KI-Labor eingesperrt und musst dich raushacken. Vier Sicherheits-
Terminals mit je einem anderen Rätsel – **Muster fortsetzen, Geheimschrift
knacken, Zahlencode aus Hinweisen, Logik-Rätsel**. Alle geknackt → der
Notausgang öffnet sich. Mit Timer, Hinweisen und „Zugriff verweigert“.

Drei Schwierigkeitsgrade: **Leicht (10 Rätsel) / Mittel (20) / Schwer (30)**.
Die Rätsel werden von **Generatoren** bei jedem Start frisch gewürfelt (und die
Lösung selbst berechnet – deshalb immer korrekt und jedes Mal anders). Schwerere
Stufen bringen mehr und kniffligere Rätsel (Primzahlen, größere Caesar-
Verschiebungen, längere Wörter, 5-stellige Mathe-Codes).

Zwei Modi: **🧑 Selbst spielen** oder **🤖 KI zuschauen** – im KI-Modus knackt
die KI die Terminals automatisch durchs Ausprobieren/Durchsuchen (z.B. das
Zahlenschloss durch Hochzählen), und man schaut ihr dabei zu.

➡️ Einfach `escape-room/index.html` im Browser öffnen.

## 🚪 KI-Labor: Der Ausbruch (`escape-story/`)
Ein **immersiver Story-Escape-Room** (inspiriert von Escape-Games): Du hackst
dich durch **drei verbundene Räume**. Statt fertiger Fragen **durchsuchst** du
jeden Raum per Point-and-Click, sammelst versteckte Hinweise in deinem
**Notizbuch** (Inventar) und **kombinierst** sie zum Türcode. Die KI **SYSTEM**
redet mit dir und neckt dich bei falschen Codes. Mit Timer und Hinweis-Funktion.

➡️ Einfach `escape-story/index.html` im Browser öffnen.
