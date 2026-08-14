# Architektur

## Der Grundgedanke

Die Engine kennt keine Oberfläche. Sie rechnet und gibt nach jedem Schritt ein
`RaceSnapshot` heraus — einen reinen Wertetyp mit allem, was man anzeigen könnte.

```
        ┌──────────────────────────────┐
        │         RaceEngine           │
        │  (rechnet, kennt keine UI)   │
        └───────────────┬──────────────┘
                        │  RaceSnapshot
              ┌─────────┴─────────┐
              ▼                   ▼
       ┌─────────────┐     ┌─────────────┐
       │  SwiftUI    │     │   f1ctl     │
       │  (Mac/iPad) │     │ (Terminal)  │
       └─────────────┘     └─────────────┘
```

Der Vorteil: Die Rennlogik ist an einer Stelle, ist getestet, und man kann sie auf
Linux laufen lassen, wo es kein SwiftUI gibt. Und ein späterer Server bräuchte genau
dieselbe Engine — ohne eine Zeile daran zu ändern.

Deshalb ist `RaceEngine` eine `final class` mit `snapshot()` und **kein**
`@Observable`: Das gibt es auf Linux nicht.

## Dateien

```
Sources/RaceEngine/
├── Model/          Reine Daten, keine Logik
│   ├── Driver          Fahrer mit sieben Werten von 0 bis 100
│   ├── Team            Auto-Stärke, Standfestigkeit, Boxencrew
│   ├── Circuit         Basiszeit, Boxenverlust, Streckenlinie …
│   ├── Tyre            Mischungen und ein konkreter Reifensatz
│   ├── Weather         Himmel + Streckennässe
│   ├── RaceState       Streckenzustand und Zustand eines Autos
│   ├── RaceConfiguration   Was man vor dem Start einstellt
│   └── RaceSnapshot    Was die Anzeige bekommt
│
├── Random/
│   └── SeededRandom    SplitMix64 + ein Strom pro Teilsystem und Auto
│
├── Simulation/
│   ├── RaceEngine      Die Schleife. Die einzige Stelle, die Zustand ändert.
│   ├── CarSim          Interner Zustand eines Autos
│   ├── LapTimeModel    Aus Werten werden Sekunden
│   ├── TyreModel       Abbau, Grip, falsche Mischung
│   ├── WeatherModel    Zustandsmaschine + Nässe
│   ├── OvertakeModel   Klappt der Angriff?
│   ├── IncidentModel   Fehler, Unfälle, Defekte
│   └── PitStrategy     Wann rein, welcher Reifen?
│
├── Events/
│   ├── RaceEvent       Alles, was passieren kann
│   └── EventBus        Verteilt in fester Reihenfolge
│
├── RaceControl/
│   ├── RaceControl     Macht aus Ereignissen Meldungen
│   ├── RaceDirector    Entscheidet Gelb/VSC/SC/Rot — mit Begründung
│   └── SafetyCarSystem Phasen, Countdown, Freigabe
│
├── Timing/
│   └── RaceResult      Klassement, Punkte, Strafen
│
└── Data/
    └── DataLoader      Lädt die JSON-Stammdaten
```

## Die Schleife im Detail

```
advance(dt):
  bei roter Flagge: nur Uhr weiterlaufen lassen, Autos stehen

  Wetter aktualisieren
  Flaggen-Phasen aktualisieren (Countdown, Freigabe)

  für jedes fahrende Auto:
      Rundenzeit für diesen Moment berechnen
      lapProgress += dt / Rundenzeit
      Sektorgrenzen prüfen  → Zwischenzeit buchen
      Ziellinie überfahren? → Runde abschließen:
            Rundenzeit buchen, Reifen altern,
            Zwischenfälle würfeln, Boxenstopp erwägen

  Reihenfolge nach Gesamtfortschritt → Positionen, Abstände, Intervalle
  unter Safety Car: Feld zusammenschieben
  Überholvorgänge prüfen
  Rennende prüfen
  Ereignisse zustellen
```

### Warum feste Zeitschritte?

Runde für Runde wäre einfacher, aber dann

- könnten sich die Autos auf der Track Map nicht bewegen,
- könnte ein Unfall nur an der Ziellinie passieren,
- würde ein VSC erst eine Runde später wirken.

Der Schritt ist auf 0,5 s begrenzt; größere Aufrufe werden intern zerlegt.

### Rundenwechsel genau treffen

Ein Simulationsschritt endet selten genau auf der Ziellinie. Deshalb wird ausgerechnet,
wann innerhalb des Schrittes die Linie überfahren wurde, und die Restzeit gehört schon
zur nächsten Runde. Ohne das würden sich pro Runde ein paar Hundertstel ansammeln.

### Sektorzeiten

Sie werden so aufgeteilt, dass ihre Summe **exakt** die Rundenzeit ergibt — sonst
passt die Anzeige nicht zu den Zahlen daneben. Ein Test prüft das für jede Runde.

## Abstände richtig rechnen

Die naheliegende Formel wäre `Weg-Differenz × Rundenzeit`. Die ist aber falsch, sobald
sich die Rundenzeiten unterscheiden — und das tun sie immer.

Stattdessen merkt sich jedes Auto seine Zeit bei jedem Überfahren der Ziellinie
(`crossingTimes`). Der Abstand ist dann:

```
Abstand = jetzt − (Zeitpunkt, zu dem der Führende hier war)
```

Dazwischen wird linear interpoliert. Genau so misst die Zeitnahme an der Strecke auch.

**Zwei verschiedene Reihenfolgen:** Die Wertung (`standings`) sortiert nach
Gesamtfortschritt; die Track Map (`trackOrder`) nach der Position auf der Strecke. Wer
überrundet wurde, fährt räumlich zwischen den Führenden, steht in der Wertung aber
weit hinten. Beide Listen dürfen nie verwechselt werden.

Daraus folgt auch: **Überrunden ist kein Überholen.** Weil die Wertung die Autos
trennt, stehen Führender und Überrundeter nie nebeneinander in der Liste — es kann
also gar kein Positionswechsel ausgelöst werden.

## Ereignisse

Die Simulation meldet nur, *dass* etwas passiert ist. Wer darauf reagiert, entscheiden
die Empfänger.

```
Crash
  ↓
EventBus
  ↓
RaceDirector      → „Strecke blockiert?“
  ↓
SafetyCarSystem   → SAFETY CAR
  ↓
RaceControl       → „LAP 18 / SAFETY CAR DEPLOYED“
  ↓
Anzeige
```

Ereignisse werden gesammelt und erst am Ende des Schrittes der Reihe nach zugestellt
(FIFO). Empfänger dürfen dabei neue Ereignisse auslösen; die landen hinten in der
Schlange. Diese feste Reihenfolge ist die Voraussetzung dafür, dass zwei Läufe mit
gleichem Seed identisch verlaufen.

## Reproduzierbarkeit

Ein eigener Generator (SplitMix64) statt `Double.random`. Entscheidend ist die
Aufteilung: **ein eigener Strom je Teilsystem und Auto.**

Warum? Ziehen alle Autos aus einem Topf, entscheidet die Reihenfolge, in der sie ihre
Runde beenden, wer welche Zahl bekommt. Diese Reihenfolge hängt aber an der
Schrittweite der Simulation — und schon wäre dasselbe Rennen anders ausgegangen, nur
weil feiner gerechnet wurde. Das ist beim Bauen tatsächlich passiert und war der
Grund für diese Aufteilung.

Zweiter Punkt: Pro Runde wird **einmal** die Tagesform eines Fahrers gewürfelt, nicht
in jedem Schritt. Sonst hinge die Zahl der Zufallsziehungen an der Schrittweite.
