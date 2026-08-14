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

## 🏁 F1 Race Control (`f1-race-control/`)
Kein Browser-Projekt, sondern das bisher größte hier: eine **eigene Formel-1-
Rennsimulation mit Rennleitung**, geschrieben in **Swift**. Die Rennlogik ist
komplett selbst gebaut – keine fertige Engine. Rundenzeiten, Reifenabbau,
Abstände, Überholvorgänge, Unfälle, Wetter und Boxenstrategie entstehen aus
Formeln, die im Code stehen und einzeln getestet sind (**140 Tests**).

Mit dabei: **Timing Tower**, **Track Map**, **VSC und Safety Car** mit echtem
Countdown, **Rote Flagge** und ein **Race Director**, der seine Entscheidungen
in ganzen Sätzen begründet („Safety Car, weil die Strecke blockiert ist“).
Dazu ein **Season Mode**: eine komplette Meisterschaft über **24 Rennen**, jedes mit
echtem **Qualifying (Q1/Q2/Q3)**, mit Fahrer- und Konstrukteurswertung und einem
Saisonstand, der gespeichert wird. Gleicher Seed = exakt gleiches Rennen.
Datenstand: **Saison 2026**.

Dazu ein **Mehrspieler-Server**: Ein Rennen läuft, beliebig viele schauen im Browser
zu, und einer ist **Race Director** und darf live VSC, Safety Car, Rote Flagge,
Strafen und Wetter anordnen. HTTP und WebSocket sind selbst gebaut — das Projekt
braucht keine einzige fremde Bibliothek.

Drei Oberflächen: eine **SwiftUI-App für Mac und iPad**, ein **Web-Dashboard** und ein
**Terminal-Programm**, mit dem man sofort loslegen kann:

```bash
cd f1-race-control
swift run f1ctl --circuit monza --laps 20 --seed 42 --speed 200   # Einzelrennen
swift run f1ctl season new --seed 2026                            # Meisterschaft
swift run f1ctl season next                                       # Quali + Rennen
swift run f1ctl season standings                                  # Tabelle
swift run f1server --circuit monza --laps 30                      # Server
```

➡️ Details, Formeln und die Xcode-Anleitung stehen in
[`f1-race-control/README.md`](f1-race-control/README.md).

## 💻 KI-Labor: Code-Ausbruch (`escape-code/`)
Wie der Story-Escape, aber **coding-basiert** (inspiriert von CodinGame Escape):
In jedem Raum steht ein **Code-Terminal**, in das du eine kleine **JavaScript-
Funktion** schreibst (z.B. `quersumme`, `umkehren`, `groessteZahl`). Dein Code
wird gegen Tests geprüft; besteht er alle, führt das Terminal ihn mit einer
geheimen Eingabe aus – **das Ergebnis ist der Türcode**. Mit echtem Code-Editor,
Test-Ausgabe, Tipps und der KI **SYSTEM** als Gegenspieler.

➡️ Einfach `escape-code/index.html` im Browser öffnen. (Braucht Code-Ausführung
im Browser – klappt lokal immer; das Spiel warnt, falls eine Umgebung sie sperrt.)
