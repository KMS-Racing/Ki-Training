# Der Rennleitungs-Server

Ein Rennen läuft auf dem Server. Wer sich verbindet, sieht es live. Wer sich als
Race Director verbindet, darf eingreifen.

```bash
swift run f1server --circuit monza --laps 30
```

```
        ┌──────────────────────────┐
        │        f1server          │
        │  RaceEngine + Broadcast  │
        └────────────┬─────────────┘
                     │  WebSocket, 10× pro Sekunde
        ┌────────────┼────────────┐
        ▼            ▼            ▼
   ZUSCHAUER    ZUSCHAUER    RACE DIRECTOR
   (nur sehen)  (nur sehen)  (VSC · SC · Rot · Strafen · Wetter)
```

- `http://localhost:8080/` — zuschauen
- `http://localhost:8080/?role=director` — Rennleitung bedienen

## Warum ohne Bibliothek

HTTP, WebSocket und sogar SHA-1 sind hier selbst gebaut. SwiftNIO oder Vapor hätten
es getan — die Abhängigkeiten ließen sich in dieser Umgebung auch problemlos laden.

Dagegen sprach:

1. **Das Projekt kommt sonst ohne Abhängigkeiten aus.** `swift build` funktioniert
   ohne Netz, auf jedem Rechner, auch in fünf Jahren noch.
2. **Man kann es lesen.** Der ganze WebSocket sind rund 200 Zeilen. Wer wissen will,
   wie eine Verbindung aus einer HTTP-Anfrage entsteht, sieht es hier — statt in
   einer Bibliothek, die es versteckt.
3. Die Regel „keine fertige Engine“ galt der **Rennlogik**. Netzwerk ist Infrastruktur.
   Trotzdem war es hier billig genug, es selbst zu machen.

Wer den Server später auf viele hundert Verbindungen bringen will, sollte auf
SwiftNIO wechseln — ein Thread pro Verbindung trägt nicht beliebig weit.

## SHA-1 im Handshake

Der WebSocket-Handshake schreibt SHA-1 vor (RFC 6455): Der Server hängt an den
Schlüssel des Clients eine feste Kennung, bildet SHA-1, schickt das Ergebnis in
Base64 zurück. Erst dann redet der Browser WebSocket.

SHA-1 ist als Sicherheitsfunktion **gebrochen** und darf dafür nirgends mehr benutzt
werden. Hier geht es aber nicht um Sicherheit: Der Hash beweist nur, dass die
Gegenstelle das Protokoll versteht und kein alter Proxy dazwischenfunkt.

Die Implementierung ist gegen die offiziellen Testvektoren geprüft, inklusive des
Beispiel-Handshakes aus dem RFC selbst (`Tests/RaceServerTests`).

## Aufbau

```
Sources/
├── RaceServerCore/          Bibliothek — testbar
│   ├── SHA1                 nur für den Handshake
│   ├── WebSocket            Rahmen lesen/schreiben, HTTP-Upgrade
│   ├── Protocol             Nachrichtenformat, JSON
│   ├── RaceSession          Engine + Clients + Befehle
│   └── Resources/dashboard.html
└── RaceServer/main.swift    dünne Hülle: Argumente, Socket, Accept-Schleife
```

Der Server ist bewusst in **Bibliothek plus Hülle** geteilt. Ein reines
Executable-Target lässt sich kaum testen; so laufen SHA-1, Handshake und Protokoll
in `swift test` mit.

## Nebenläufigkeit

- **Ein Thread pro Verbindung**, der liest.
- **Ein Thread**, der das Rennen weiterrechnet und zehnmal pro Sekunde sendet.
- **Eine Sperre** um alles, was die Engine anfasst.

Die `RaceEngine` ist absichtlich eine einfache Klasse ohne eigene Absicherung — im
Einzelspieler soll sie nichts kosten. Also schützt der Server sie von außen. Auch die
Log-Ausgabe passiert innerhalb der Sperre: Sonst rechnen die Threads zwar die
richtigen Zahlen aus, drucken sie aber in beliebiger Reihenfolge, und im Protokoll
steht „0 verbunden“ direkt vor „3 verbunden“. Genau das ist beim ersten Test passiert.

## Das Protokoll

**Server → Client**

| Nachricht | Wann | Inhalt |
|---|---|---|
| `welcome` | einmal beim Verbinden | Strecke samt Streckenlinie, alle Fahrer mit Nummer und Teamfarbe, Rundenzahl, Rolle |
| `snapshot` | 10× pro Sekunde | Runde, Flaggenstatus, Countdown, Begründung, Wetter, Klassement, Meldungen |
| `notice` | nach jedem Befehl | ob er ausgeführt wurde |

Die Streckenlinie (160 Punkte) geht **nur in der Begrüßung** raus. Würde sie in jedem
Snapshot mitfahren, wäre die Nachricht zehnmal so groß — für Daten, die sich nie ändern.

**Client → Server**

```json
{"action":"vsc"}
{"action":"safetyCar"}
{"action":"redFlag"}
{"action":"resume"}
{"action":"penalty","driverID":"HAM","seconds":5}
{"action":"weather","state":"heavyRain"}
{"action":"pause"} · {"action":"play"} · {"action":"speed","value":40}
```

Befehle von Zuschauern werden abgelehnt und mit einer `notice` beantwortet.

## Was der Server (noch) nicht ist

Ehrlich dazugesagt:

- **Keine Absicherung.** Wer `?role=director` an die Adresse hängt, ist Race Director.
  Das reicht fürs Wohnzimmer und für ein LAN, aber der Server gehört **nicht ins
  offene Internet**.
- **Ein Rennen pro Server.** Keine Lobbys, keine Räume, keine Anmeldung.
- **Zuschauen, nicht mitfahren.** Die Clients steuern kein eigenes Auto — das Feld
  fährt die KI. Der Mehrspieler-Teil ist die *Rennleitung*, so wie in der Aufgabe
  beschrieben (Race Director gegen Fahrer wäre der nächste Schritt).
- **Unter Neutralisierung zeigen alle Autos dieselbe Rundenzeit** (z.B. exakt
  `1:52.000` unter Safety Car). Das ist gewollt: „Delta halten“ heißt hier, dass alle
  exakt gleich schnell fahren, damit unter einer Flagge, die Überholen verbietet,
  garantiert niemand aufholt. Etwas Streuung wäre realistischer, könnte aber bei
  engen Abständen genau das kaputtmachen.
