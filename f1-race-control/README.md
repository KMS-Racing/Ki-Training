# 🏁 F1 Race Control

Eine eigene Formel-1-Rennsimulation mit Rennleitung — Race Engine, Timing Tower,
Track Map, Wetter, VSC/Safety Car und einem Race Director, der seine Entscheidungen
begründet.

Die Rennlogik ist **selbst geschrieben**: keine fertige Race Engine, keine
Physik-Bibliothek. Rundenzeiten, Reifenabbau, Abstände, Überholvorgänge, Unfälle und
Boxenstrategie entstehen aus Formeln, die im Code stehen und einzeln getestet sind.

Datenstand: **Saison 2026** (11 Teams, 22 Fahrer).

---

## Was drin ist

| Teil | Was es macht |
|---|---|
| `Sources/RaceEngine/` | Die gesamte Rennlogik. Reines Swift + Foundation, keine UI. |
| `Sources/f1ctl/` | Rennen im Terminal ansehen — läuft auf macOS **und** Linux. |
| `Tests/RaceEngineTests/` | 74 Tests, die beweisen, dass die Logik stimmt. |
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
├── Neues Rennen      Strecke, Länge, Wetter, KI-Stärke, Seed
├── Rennen fortsetzen → Dashboard
├── Fahrer            alle Werte als Balken
├── Teams
├── Strecken          mit kleiner Streckenzeichnung
└── Einstellungen
```

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
- **Season Mode** und die dauerhafte Statistik-Datenbank fehlen. Die Punkte pro
  Rennen und pro Team werden aber schon berechnet (`RaceResult.constructorPoints`).
- **Die Streckenlinien sind stilisiert**, keine vermessenen Koordinaten. Sie geben die
  Form wieder, nicht den exakten Verlauf.
- **Die Team-Stärken für 2026 sind Schätzungen.** Die Fahrerpaarungen sind der
  bekannte Stand, aber wie schnell die Autos unter dem neuen Reglement wirklich sind,
  weiß vor der Saison niemand. Alle Werte stehen in `Sources/RaceEngine/Resources/`
  und lassen sich dort ändern.
- **Die SwiftUI-Views sind noch nicht auf einem Mac kompiliert worden** — sie wurden
  auf einem Linux-Rechner geschrieben, wo es kein SwiftUI gibt. Die Engine dagegen ist
  vollständig gebaut und getestet.

---

## Lizenz

MIT — siehe [LICENSE](../LICENSE).
