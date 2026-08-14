# 🏁 F1 Race Control

Eine eigene Formel-1-Rennsimulation mit Rennleitung — Race Engine, Timing Tower,
Track Map, Wetter, VSC/Safety Car und einem Race Director, der seine Entscheidungen
begründet.

Die Rennlogik ist **selbst geschrieben**: keine fertige Race Engine, keine
Physik-Bibliothek. Rundenzeiten, Reifenabbau, Abstände, Überholvorgänge, Unfälle und
Boxenstrategie entstehen aus Formeln, die im Code stehen und einzeln getestet sind.

Datenstand: **Saison 2026** — 11 Teams, 22 Fahrer, 24 Rennen.

---

## Was drin ist

| Teil | Was es macht |
|---|---|
| `Sources/RaceEngine/` | Die gesamte Rennlogik. Reines Swift + Foundation, keine UI. |
| `Tools/gen_circuits.py` | Erzeugt die Streckenkarten aus groben Umrissen. |
| `Sources/f1ctl/` | Rennen im Terminal ansehen — läuft auf macOS **und** Linux. |
| `Sources/RaceServerCore/` | Rennleitungs-Server: WebSocket, Protokoll, Web-Dashboard. |
| `Tests/` | 140 Tests, die beweisen, dass die Logik stimmt. |
| `App/` | Die SwiftUI-App für Mac und iPad. |
| `Documentation/` | Wie die Engine aufgebaut ist und wie gerechnet wird. |

---

## Sofort ausprobieren (ohne Xcode)

Im Ordner `f1-race-control/`:

```bash
swift run f1ctl --circuit monza --laps 20 --seed 42 --speed 200
```

Das zeichnet ein laufendes Rennen ins Terminal: Timing Tower, Wetterleiste und die
Meldungen der Rennleitung, alles live.

Ein echtes Bild aus `--circuit spa --seed 3`:

```
F1 RACE CONTROL   CIRCUIT DE SPA-FRANCORCHAMPS
LAP 3 / 25    VIRTUAL SAFETY CAR   ENDING IN 2
──────────────────────────────────────────────────────────────────────────
POS  #   DRIVER       GAP        INTERVAL   LAST      TYRE   PIT  ±
  1   4  NORRIS      LEADER     —          1:46.905  M  2     0  +1 FL
  2  63  RUSSELL     +0.930     +0.930     1:47.329  M  2     0  +1
  3  81  PIASTRI     +0.965     +0.035     1:47.266  M  2     0  +2
  4   1  VERSTAPPEN  +1.139     +0.174     1:47.504  M  2     0  -3
  5  12  ANTONELLI   +1.233     +0.094     1:47.481  M  2     0  +2
  6  16  LECLERC     +1.524     +0.291     1:47.637  M  2     0  -2
  7  44  HAMILTON    +1.633     +0.108     1:47.646  M  2     0  -1
──────────────────────────────────────────────────────────────────────────
CLOUDY  wetness 0.00   air 24°C   track 41°C   wind 10 km/h   rain 33%
──────────────────────────────────────────────────────────────────────────
RACE CONTROL
  LAP 3 / VSC ENDING
  LAP 3 / WEATHER — CLOUDY
  LAP 3 / VSC DEPLOYED — Virtual Safety Car deployed because car GAS stopped
          in sector 3. The car is off the racing line, so a full Safety Car
          is not needed — drivers must hold a delta instead.
  LAP 2 / CAR 10 (GAS) — DNF — HYDRAULICS
  LAP 2 / TECHNICAL — GAS — SECTOR 3
```

Weitere Möglichkeiten:

```bash
swift run f1ctl --help                       # alle Optionen
swift run f1ctl --list                       # verfügbare Strecken
swift run f1ctl --headless --log             # nur Ergebnis + volles Protokoll
swift run f1ctl --weather heavyRain          # Regenrennen
swift run f1ctl --circuit monaco --seed 7    # gleicher Seed = gleiches Rennen
```

Tests laufen lassen:

```bash
swift test
```

---

## Season Mode — eine ganze Meisterschaft

24 Rennen, jedes mit eigenem Qualifying. Der Stand wird gespeichert und übersteht
einen Neustart.

```bash
swift run f1ctl season new --seed 2026     # Saison anlegen
swift run f1ctl season next                # Qualifying + Rennen
swift run f1ctl season next --watch        # …und dabei live zuschauen
swift run f1ctl season standings           # beide Meisterschaften
swift run f1ctl season stats VER           # Statistik eines Fahrers
swift run f1ctl season simulate            # Rest der Saison am Stück
swift run f1ctl season calendar            # Kalender mit Ergebnissen
```

### Qualifying

Echtes Q1/Q2/Q3 mit Ausscheiden:

```
Q1   alle 22   → die langsamsten 6 raus  → Startplätze 17–22
Q2   16 übrig  → die langsamsten 6 raus  → Startplätze 11–16
Q3   die Top 10                          → Startplätze 1–10, Schnellster hat die Pole
```

Die Qualirunde benutzt **dieselbe** Rundenzeit-Formel wie das Rennen — nur mit leerem
Tank, freier Strecke und frischen Reifen. Es gibt bewusst keine zweite Zeitformel,
sonst könnten Quali- und Renntempo auseinanderlaufen. Dazu kommt Streckenevolution:
Q3 ist schneller als Q1, weil bis dahin Gummi auf dem Asphalt liegt.

```
POS  #   FAHRER          Q1         Q2         Q3         RAUS
  1  44  HAMILTON        1:16.700   1:16.368   1:15.904   Q3   POLE
  2  63  RUSSELL         1:16.363   1:16.077   1:15.904   Q3
  3   4  NORRIS          1:16.517   1:16.237   1:15.959   Q3
  4   1  VERSTAPPEN      1:16.567   1:16.314   1:15.995   Q3
 ...
 17  23  ALBON           1:17.548   —          —          Q1
```

### Meisterschaft

Der Saisonstand speichert **nur die Ergebnisse**. Die Tabelle wird daraus jedes Mal
neu ausgerechnet — so kann sie nie auseinanderlaufen, und man kann sie testen, ohne
ein einziges Rennen zu simulieren.

Gezählt wird alles, was eine Saison ausmacht: Punkte, Siege, Podien, Poles, schnellste
Runden, Ausfälle, Boxenstopps, mittlere Platzierung und mittlere Rundenzeit.

Ein kompletter Durchlauf mit Seed 2026 endete so:

```
POS  FAHRER              TEAM                        PKT  SIEGE  POD  POLE
  1  Max Verstappen      Oracle Red Bull Racing      433     11   20     9
  2  Lewis Hamilton      Scuderia Ferrari            338      4   12     1
  3  George Russell      Mercedes-AMG Petronas       334      4   14     2
  4  Lando Norris        McLaren Formula 1 Team      318      4   12     3

KONSTRUKTEUR   McLaren, 578 Punkte
```

Fünf verschiedene Sieger, sieben verschiedene Polesitter — genau das, was ein
Qualifying bringen soll.

### Wo die Saison liegt

| System | Ort |
|---|---|
| macOS / iPadOS | `~/Library/Application Support/F1RaceControl/season.json` |
| Linux | `~/.f1-race-control/season.json` |

---

## Mehrspieler — der Rennleitungs-Server

Ein Rennen läuft auf dem Server, beliebig viele schauen im Browser zu, und **einer**
ist der Race Director und darf eingreifen.

```bash
swift run f1server --circuit monza --laps 30
```

```
  http://localhost:8080/                        zuschauen
  http://localhost:8080/?role=director          Rennleitung bedienen
  http://localhost:8080/?role=driver&car=VER    selbst fahren
```

Der Race Director kann live **VSC**, **Safety Car** und die **Rote Flagge** anordnen,
**Strafen** verhängen, das **Wetter** umstellen sowie pausieren und das Tempo ändern —
alles kommt sofort bei allen Zuschauern an.

HTTP, WebSocket und sogar SHA-1 für den Handshake sind selbst gebaut. Das Projekt
bleibt damit komplett abhängigkeitsfrei: `swift build` braucht kein Netz.
Details in [`Documentation/Server.md`](Documentation/Server.md).

> Der Server ist für Wohnzimmer und LAN gedacht, **nicht fürs offene Internet** —
> wer `?role=director` an die Adresse hängt, ist Race Director.

### Selbst fahren

Die Engine rechnet Rundenzeiten, keine Physik — es gibt also **kein Lenkrad**.
Gefahren wird das, was in der Formel 1 wirklich über das Ergebnis entscheidet:

```
              Rundenzeit   Reifen   Batterie   Risiko
SCHONEN         +0.55 s    ×0.80     +0.22     ×0.75
NORMAL           0.00 s    ×1.00     +0.06     ×1.00
PUSH            −0.30 s    ×1.25     −0.12     ×1.30
ATTACK          −0.65 s    ×1.55     −0.34     ×1.85
```

Dazu **wann du an die Box kommst und auf welchen Reifen**, und ob du **angreifen oder
Position halten** willst. Die Batterie ist die eigentliche Bremse: ATTACK leert sie in
wenigen Runden, SCHONEN lädt sie nach, und leer fällt sie auf NORMAL zurück. Man kann
sich Angriff leisten — aber nicht dauerhaft.

Sobald du ein Auto übernimmst, hält sich die KI-Strategie bei diesem Auto komplett
heraus. Wer nie „BOX BOX“ drückt, fährt die ganze Distanz auf einem Satz Reifen.

---

## Wie die Engine rechnet

### Die Simulationsschleife

Das Rennen läuft in **festen Zeitschritten**, nicht Runde für Runde. Nur so bewegen
sich die Autos auf der Karte flüssig, passieren Unfälle mitten in der Runde und wirkt
ein VSC sofort statt erst beim nächsten Überfahren der Linie.

```
Wetter → Flaggen → Autos bewegen → Reihenfolge & Abstände
  → Safety-Car-Pulk → Überholen → Rundenwechsel → Rennende?
```

### Die Rundenzeit

Absichtlich eine Summe einzelner Zuschläge statt einer großen Gleichung — so kann man
jeden Effekt einzeln nachrechnen und verstellen:

```
Rundenzeit = Basiszeit der Strecke
           + Auto & Fahrer          60 % Auto, 40 % Fahrer (im Regen umgekehrt)
           + Reifen                 Mischung + Abbau + passend zum Wetter?
           + Spritlast              volle Tanks sind langsam
           + nasse Strecke
           + Dirty Air              hinter einem Auto fehlt Abtrieb
           + Streuung               niemand trifft zweimal dieselbe Zeit
           × Neutralisierung        VSC ×1.40, Safety Car ×1.60
```

### Abstände

Nicht geschätzt, sondern wie bei der echten Zeitnahme gemessen: **Wann war der
Führende an genau der Stelle, an der das hintere Auto jetzt ist?** Jedes Auto merkt
sich seine Zeit beim Überfahren der Linie; der Abstand ergibt sich aus dem Vergleich.
Deshalb stimmen auch die Abstände zu überrundeten Autos.

### Reifen

Fünf Mischungen. Weich = schneller, aber schneller hinüber. Der Grip fällt zunächst
sanft und ab etwa 85 % Abnutzung **plötzlich** ab — genau diese Klippe ist der Grund,
warum in der Formel 1 überhaupt an die Box gefahren wird.

Der falsche Reifen fürs Wetter kostet zweistellig Sekunden pro Runde. Slicks bei
Starkregen sind kein Nachteil, sondern hoffnungslos.

### Wetter

Zwei getrennte Dinge — und genau darin liegt die Spannung eines Regenrennens:

- **Der Himmel:** `Dry → Cloudy → Light Rain → Heavy Rain → Drying → Dry`
- **Die Strecke:** ein Nässewert 0–1, der dem Himmel **hinterherläuft**

Die Strecke saugt sich in etwa zwei Minuten voll und braucht zum Abtrocknen ein
Vielfaches. Wer zu früh auf Slicks wechselt, verliert — wer zu spät wechselt, auch.

### Race Director

Regelbasiert und **ohne Zufall**: dieselbe Lage führt immer zur selben Anordnung.
Dadurch ist die Entscheidung testbar und man kann sie dem Nutzer erklären.

| Situation | Anordnung |
|---|---|
| Auto dreht sich, fährt weiter | YELLOW FLAG |
| Auto steht abseits der Strecke | VIRTUAL SAFETY CAR |
| Auto oder Trümmer auf der Strecke | SAFETY CAR |
| Strecke blockiert, mehrere Autos | RED FLAG |

Dazu zwei Sonderregeln: Auf nasser Strecke wird eine Stufe schärfer entschieden, und
auf den letzten Runden wird nicht mehr abgebrochen, sondern hinter dem Safety Car zu
Ende gefahren.

### Gleicher Seed = gleiches Rennen

Ein eigener Zufallsgenerator (SplitMix64), und **jedes Auto hat seinen eigenen
Zufallsstrom**. Das ist kein Detail: Würden sich alle aus einem Topf bedienen, würde
schon die Reihenfolge, in der die Autos ihre Runde beenden, das ganze Rennen
verändern — und die hängt an der Schrittweite der Simulation. So ist ein Rennen
wirklich reproduzierbar.

---

## Die App in Xcode öffnen

Das Projekt ist ein Swift-Paket. Die App wird einmal in Xcode angelegt und benutzt
das Paket:

1. **Xcode → File → New → Project → Multiplatform → App**
   Name z.B. `F1RaceControl`, Interface **SwiftUI**.
2. **File → Add Package Dependencies… → Add Local…** und den Ordner
   `f1-race-control/` auswählen.
3. Im Target unter *General → Frameworks, Libraries* die Bibliothek **RaceEngine**
   hinzufügen.
4. Die von Xcode erzeugte `ContentView.swift` und `…App.swift` löschen und
   stattdessen die Dateien aus `App/` ins Projekt ziehen
   (*Copy items if needed* muss **nicht** angehakt sein).
5. Starten. Zielgeräte sind **Mac** und **iPad**.

Die App braucht macOS 14 bzw. iPadOS 17.

### Aufbau der App

```
Home
├── SAISON
│   ├── Kalender          24 Rennen, gefahrene mit Sieger und Pole
│   ├── Meisterschaft     Fahrer- und Konstrukteurswertung
│   └── Statistik         alles aus §20 in einer Tabelle
├── EINZELRENNEN
│   ├── Neues Rennen      Strecke, Länge, Wetter, KI-Stärke, Seed
│   └── Rennen fortsetzen → Dashboard
├── Fahrer · Teams · Strecken
└── Einstellungen
```

Ein Saison-Wochenende in der App: **Wochenende starten** → das Qualifying-Ergebnis
erscheint mit allen drei Abschnitten → **Rennen starten** → das Dashboard läuft live →
nach der Zielflagge landet das Ergebnis automatisch in der Meisterschaft.

Das Dashboard:

```
┌──────────────────────────────────────────────────┐
│ F1 RACE CONTROL   MONZA   LAP 34/53   GREEN FLAG │
├──────────────┬──────────────────┬────────────────┤
│ TIMING TOWER │    TRACK MAP     │  RACE CONTROL  │
│              ├──────────────────┤                │
│              │    STRATEGY      │                │
├──────────────┴──────────────────┴────────────────┤
│ DRY   TRACK 42°C   AIR 24°C   WIND   WETNESS ▓░░ │
└──────────────────────────────────────────────────┘
```

Über **RACE DIRECTOR** in der Kopfzeile lässt sich die Rennleitung von Hand bedienen:
VSC, Safety Car, Rote Flagge, Wetter umstellen. Das ist die Vorarbeit für den
Mehrspieler-Modus.

---

## Was (noch) fehlt

Ehrlich gesagt, damit klar ist, wo das Projekt steht:

- **Mehrspieler/Server** ist noch nicht gebaut. Die Engine ist aber schon darauf
  vorbereitet: Sie hat keine UI-Abhängigkeiten, liefert Zustände als Wertetypen und
  lässt sich von außen steuern (`forceTrackStatus`, `applyPenalty`, `forceWeather`).
- **Kein Fahrgefühl.** Man steuert Tempo, Reifen und Strategie — nicht das Auto selbst.
  Für echtes Fahren bräuchte die Engine ein Physikmodell statt Rundenzeiten.
- **Sprintrennen** gibt es nicht. Der Kalender 2026 hat sechs davon; hier wird jedes
  Wochenende als normales Rennen gefahren.
- **Mehrere Saisons hintereinander** (Fahrerwechsel, Entwicklung der Autos über Jahre)
  sind nicht vorgesehen — gespeichert wird immer genau eine Saison.
- **Die Streckenlinien sind stilisiert**, keine vermessenen Koordinaten. Sie geben die
  Form wieder, nicht den exakten Verlauf.
- **Der Kalender** gibt den veröffentlichten Stand 2026 wieder und steht in
  `SeasonCalendar.year2026` — umsortieren dauert eine Minute.
- **Die Team-Stärken für 2026 sind Schätzungen.** Die Fahrerpaarungen sind der
  bekannte Stand, aber wie schnell die Autos unter dem neuen Reglement wirklich sind,
  weiß vor der Saison niemand. Alle Werte stehen in `Sources/RaceEngine/Resources/`
  und lassen sich dort ändern.
- **Die SwiftUI-Views wurden auf einem Linux-Rechner geschrieben**, wo es kein SwiftUI
  gibt — dort ließen sie sich nicht kompilieren. Dafür gibt es jetzt
  `.github/workflows/f1-race-control.yml`: Der Lauf auf einem **macOS-Runner** prüft die
  App gegen das echte SDK. Beim ersten Durchlauf zeigt sich, ob noch Typfehler drin sind.

---

## Lizenz

MIT — siehe [LICENSE](../LICENSE).
