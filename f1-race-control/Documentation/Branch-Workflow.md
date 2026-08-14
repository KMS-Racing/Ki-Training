# Arbeiten mit Git und GitHub

## Der Ablauf für ein größeres Feature

```
main
│
├── feature/race-engine
├── feature/tyre-system
├── feature/weather
├── feature/vsc
├── feature/safety-car
├── feature/timing
├── feature/track-map
├── feature/race-director
└── feature/multiplayer
```

Für jedes Feature:

1. **Branch anlegen** — `git switch -c feature/tyre-system`
2. **Programmieren** — in kleinen Schritten
3. **Testen** — `swift test` muss grün sein, *bevor* committet wird
4. **Committen** — eine Sache pro Commit, Nachricht sagt *warum*, nicht nur *was*
5. **Pushen** — `git push -u origin feature/tyre-system`
6. **Pull Request** öffnen
7. **Review**
8. **Mergen**

## Commit-Nachrichten

Erste Zeile kurz und im Imperativ, dann eine Leerzeile, dann die Begründung:

```
Fix gap calculation for lapped cars

Die alte Formel hat Weg-Differenz mit der Rundenzeit multipliziert. Das
stimmt nur, wenn alle gleich schnell fahren. Jetzt wird nachgeschlagen,
wann der Führende an derselben Stelle war — so misst die echte Zeitnahme auch.
```

## Was nicht in einen Commit gehört

- `.build/` — das Bauverzeichnis von SwiftPM (steht in `.gitignore`)
- `*.xcodeproj` — jeder legt sich sein Xcode-Projekt selbst an
- Auskommentierter Code — dafür gibt es die Git-Historie

## Hinweis zu diesem Projekt

Der Grundstock wurde in einem Rutsch auf einem einzelnen Branch gebaut, weil die
Teile so eng zusammenhängen, dass sie einzeln gar nicht lauffähig gewesen wären —
eine Race Engine ohne Reifenmodell rechnet nichts.

Ab jetzt lohnt sich der Branch-Ablauf oben, weil jedes weitere Feature (Multiplayer,
Season Mode, Statistik) für sich allein gebaut und getestet werden kann.
