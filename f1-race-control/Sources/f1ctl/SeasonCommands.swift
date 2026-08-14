import Foundation
import RaceEngine

// =============================================================================
//  Die `season`-Befehle
// -----------------------------------------------------------------------------
//  Auch hier steckt keine Rennlogik drin — nur Aufrufe der RaceEngine und Anzeige.
// =============================================================================

let seasonUsage = """
f1ctl season — Meisterschaft

Verwendung:
  swift run f1ctl season <befehl> [Optionen]

Befehle:
  new                 Neue Saison anlegen (überschreibt eine laufende)
  calendar            Kalender mit den bisherigen Ergebnissen
  next                Nächstes Wochenende: Qualifying und Rennen
  standings           Fahrer- und Konstrukteurswertung
  stats [KÜRZEL]      Statistik aller Fahrer oder eines einzelnen (z.B. VER)
  quali               Qualifying-Ergebnis der letzten gefahrenen Runde
  simulate [n]        n Wochenenden am Stück (ohne Zahl: bis Saisonende)
  reset               Gespeicherte Saison löschen

Optionen für `new`:
  --seed <n>          Startwert; gleicher Seed = gleiche Saison (Standard 2026)
  --length <0..1>     Anteil der vollen Renndistanz (Standard 1.0)
  --ai <0..1>         Stärke der KI (Standard 0.9)

Optionen für `next`:
  --watch             Das Rennen live im Timing Tower mitverfolgen
  --speed <n>         Rennsekunden pro echter Sekunde beim Mitschauen
"""

/// Lädt die Saison oder bricht mit einer verständlichen Meldung ab.
func loadSeasonOrExit() -> Season {
    do {
        guard let season = try SeasonStore.load() else {
            print("Es läuft noch keine Saison. Erst anlegen mit:")
            print("  swift run f1ctl season new")
            exit(1)
        }
        return season
    } catch {
        FileHandle.standardError.write("Saison konnte nicht geladen werden: \(error)\n"
            .data(using: .utf8)!)
        exit(1)
    }
}

func storeSeasonOrExit(_ season: Season) {
    do {
        try SeasonStore.save(season)
    } catch {
        FileHandle.standardError.write("Saison konnte nicht gespeichert werden: \(error)\n"
            .data(using: .utf8)!)
        exit(1)
    }
}

/// Einstieg für alle `season`-Befehle.
func runSeasonCommand(_ arguments: [String], data: RaceData, style: Style) {
    guard arguments.count > 2 else {
        print(seasonUsage)
        return
    }

    let command = arguments[2]
    let rest = Array(arguments.dropFirst(3))

    switch command {
    case "new":       seasonNew(rest, data: data, style: style)
    case "calendar":  seasonCalendar(data: data, style: style)
    case "next":      seasonNext(rest, data: data, style: style)
    case "simulate":  seasonSimulate(rest, data: data, style: style)
    case "standings": seasonStandings(data: data, style: style)
    case "stats":     seasonStats(rest, data: data, style: style)
    case "quali":     seasonQualifying(data: data, style: style)
    case "reset":     seasonReset()
    case "--help", "-h", "help": print(seasonUsage)
    default:
        FileHandle.standardError.write("Unbekannter Saison-Befehl: \(command)\n".data(using: .utf8)!)
        print(seasonUsage)
    }
}

/// Kleiner Helfer, um `--name wert` aus einer Argumentliste zu ziehen.
func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

// MARK: - new

func seasonNew(_ arguments: [String], data: RaceData, style: Style) {
    let seed = UInt64(option("--seed", in: arguments) ?? "") ?? 2026
    let length = Double(option("--length", in: arguments) ?? "") ?? 1.0
    let ai = Double(option("--ai", in: arguments) ?? "") ?? 0.9

    let season = Season(
        year: 2026,
        seed: seed,
        aiStrength: min(max(ai, 0), 1),
        raceLengthFactor: min(max(length, 0.05), 1.0)
    )
    storeSeasonOrExit(season)

    print(style.bold("\nNEUE SAISON \(season.year)"))
    print("\(season.calendar.count) Rennen · Seed \(season.seed) · "
          + "Renndistanz \(Int(season.raceLengthFactor * 100)) %")
    print(style.dim("Gespeichert unter \(SeasonStore.fileURL().path)"))
    print("\nWeiter mit: " + style.cyan("swift run f1ctl season next") + "\n")
}

// MARK: - calendar

func seasonCalendar(data: RaceData, style: Style) {
    let season = loadSeasonOrExit()
    print(style.bold("\nKALENDER \(season.year)") + style.dim("   (\(season.completedRounds)/\(season.calendar.count) gefahren)"))
    print(style.dim("RND  RENNEN                            STRECKE          SIEGER      POLE"))

    for round in season.calendar {
        let result = season.result(forRound: round.round)
        let circuit = data.circuit(id: round.circuitID)

        var line = padLeft("\(round.round)", 3) + "  "
        line += fit(round.name, 34)
        line += fit(circuit?.country ?? round.circuitID, 17)

        if let result = result {
            let winner = result.winner.flatMap { lastName(of: $0, data: data) } ?? "—"
            let pole = result.poleSitter.flatMap { lastName(of: $0, data: data) } ?? "—"
            line += pad(style.green(winner), 12) + pad(style.cyan(pole), 12)
        } else if round.round == season.nextRound?.round {
            line += style.yellow("← als Nächstes")
        } else {
            line += style.dim("—")
        }
        print(line)
    }
    print("")
}

func lastName(of driverID: String, data: RaceData) -> String? {
    return data.drivers.first { $0.id == driverID }?.lastName
}

// MARK: - next / simulate

func seasonNext(_ arguments: [String], data: RaceData, style: Style) {
    var season = loadSeasonOrExit()
    let watch = arguments.contains("--watch")
    let speed = Double(option("--speed", in: arguments) ?? "") ?? 150

    let setup: WeekendSetup
    do {
        setup = try SeasonEngine.prepareNextWeekend(season: season, data: data)
    } catch {
        print("\n\(error)\n")
        if season.isFinished { showChampionshipSummary(season: season, data: data, style: style) }
        return
    }

    print(style.bold("\nRUNDE \(setup.round.round) — \(setup.round.name.uppercased())"))
    print(style.dim("\(setup.circuit.name) · \(setup.raceConfiguration.laps) Runden · "
                    + setup.raceConfiguration.startingWeather.displayName))

    printQualifying(setup.qualifying, data: data, style: style)

    // Rennen fahren.
    let engine = RaceEngine(configuration: setup.raceConfiguration)
    if watch {
        var driversByID: [String: Driver] = [:]
        for driver in data.drivers { driversByID[driver.id] = driver }
        runRaceLive(engine: engine, drivers: driversByID, style: style, speed: speed)
    } else {
        engine.runToCompletion()
    }

    guard let race = engine.result() else {
        print("Das Rennen konnte nicht beendet werden.")
        return
    }

    SeasonEngine.record(race: race, setup: setup, into: &season)
    storeSeasonOrExit(season)

    var driversByID: [String: Driver] = [:]
    for driver in data.drivers { driversByID[driver.id] = driver }
    print(renderResult(race, drivers: driversByID, style: style))

    printChampionshipShort(season: season, data: data, style: style)

    if season.isFinished {
        showChampionshipSummary(season: season, data: data, style: style)
    } else if let next = season.nextRound {
        print(style.dim("Als Nächstes: Runde \(next.round) — \(next.name)\n"))
    }
}

func seasonSimulate(_ arguments: [String], data: RaceData, style: Style) {
    var season = loadSeasonOrExit()
    let count = Int(arguments.first ?? "") ?? (season.calendar.count - season.completedRounds)

    guard count > 0, !season.isFinished else {
        print("\nDie Saison ist bereits zu Ende.\n")
        return
    }

    print(style.bold("\nSIMULIERE \(count) WOCHENENDE(N)\n"))
    print(style.dim("RND  RENNEN                            POLE        SIEGER"))

    for _ in 0..<count {
        guard !season.isFinished else { break }
        do {
            let result = try SeasonEngine.simulateNextWeekend(season: &season, data: data)
            let name = season.calendar.first { $0.round == result.round }?.name ?? ""
            var line = padLeft("\(result.round)", 3) + "  " + fit(name, 34)
            line += pad(style.cyan(result.poleSitter.flatMap { lastName(of: $0, data: data) } ?? "—"), 12)
            line += style.green(result.winner.flatMap { lastName(of: $0, data: data) } ?? "—")
            print(line)
        } catch {
            print("\(error)")
            break
        }
    }

    storeSeasonOrExit(season)
    printChampionshipShort(season: season, data: data, style: style)
    if season.isFinished {
        showChampionshipSummary(season: season, data: data, style: style)
    }
}

// MARK: - standings

func seasonStandings(data: RaceData, style: Style) {
    let season = loadSeasonOrExit()
    let drivers = Championship.drivers(from: season.results, drivers: data.drivers)
    let teams = Championship.constructors(
        from: season.results, drivers: data.drivers, teams: data.teams)

    print(style.bold("\nFAHRERWERTUNG \(season.year)")
          + style.dim("   nach \(season.completedRounds) von \(season.calendar.count) Rennen"))
    print(style.dim("POS  FAHRER              TEAM                 PKT   SIEGE  POD  POLE  FL  DNF"))
    for entry in drivers {
        guard let driver = data.drivers.first(where: { $0.id == entry.driverID }) else { continue }
        let team = data.teams.first { $0.id == driver.teamID }
        var line = padLeft("\(entry.position)", 3) + "  "
        line += fit(driver.name, 20)
        line += fit(team?.name ?? "", 27)
        line += padLeft(style.bold("\(entry.points)"), 5) + "  "
        line += padLeft("\(entry.wins)", 5) + "  "
        line += padLeft("\(entry.podiums)", 3) + "  "
        line += padLeft("\(entry.poles)", 4) + "  "
        line += padLeft("\(entry.fastestLaps)", 2) + "  "
        line += padLeft("\(entry.dnfs)", 3)
        print(line)
    }

    print(style.bold("\nKONSTRUKTEURSWERTUNG \(season.year)"))
    print(style.dim("POS  TEAM                        PKT   SIEGE  POD  POLE"))
    for entry in teams {
        guard let team = data.teams.first(where: { $0.id == entry.teamID }) else { continue }
        var line = padLeft("\(entry.position)", 3) + "  "
        line += fit(team.name, 28)
        line += padLeft(style.bold("\(entry.points)"), 5) + "  "
        line += padLeft("\(entry.wins)", 5) + "  "
        line += padLeft("\(entry.podiums)", 3) + "  "
        line += padLeft("\(entry.poles)", 4)
        print(line)
    }
    print("")
}

/// Die Top 5 nach einem Rennen — kurz gehalten.
func printChampionshipShort(season: Season, data: RaceData, style: Style) {
    let drivers = Championship.drivers(from: season.results, drivers: data.drivers)
    print(style.bold("MEISTERSCHAFT nach \(season.completedRounds) Rennen"))
    for entry in drivers.prefix(5) {
        guard let driver = data.drivers.first(where: { $0.id == entry.driverID }) else { continue }
        print("  " + padLeft("\(entry.position)", 2) + "  " + fit(driver.lastName, 14)
              + padLeft("\(entry.points)", 4) + style.dim("  (\(entry.wins) Siege)"))
    }
    print("")
}

func showChampionshipSummary(season: Season, data: RaceData, style: Style) {
    let drivers = Championship.drivers(from: season.results, drivers: data.drivers)
    let teams = Championship.constructors(
        from: season.results, drivers: data.drivers, teams: data.teams)

    print(style.bold("\n═══ SAISON \(season.year) BEENDET ═══\n"))
    if let champion = drivers.first,
       let driver = data.drivers.first(where: { $0.id == champion.driverID }) {
        print(style.bold("WELTMEISTER   ") + style.yellow(driver.name.uppercased())
              + "   \(champion.points) Punkte, \(champion.wins) Siege")
    }
    if let best = teams.first, let team = data.teams.first(where: { $0.id == best.teamID }) {
        print(style.bold("KONSTRUKTEUR  ") + style.yellow(team.name.uppercased())
              + "   \(best.points) Punkte")
    }
    print("")
}

// MARK: - stats

func seasonStats(_ arguments: [String], data: RaceData, style: Style) {
    let season = loadSeasonOrExit()
    let table = Championship.drivers(from: season.results, drivers: data.drivers)

    if let wanted = arguments.first?.uppercased() {
        guard let entry = table.first(where: { $0.driverID == wanted }),
              let driver = data.drivers.first(where: { $0.id == wanted }) else {
            print("\nKein Fahrer mit dem Kürzel '\(wanted)'.\n")
            return
        }
        print(style.bold("\n\(driver.name.uppercased())") + style.dim("  #\(driver.number)"))
        func row(_ label: String, _ value: String) {
            print("  " + pad(label, 22) + value)
        }
        row("Position", "\(entry.position)")
        row("Punkte", "\(entry.points)")
        row("Rennen", "\(entry.races)")
        row("Siege", "\(entry.wins)")
        row("Podien", "\(entry.podiums)")
        row("Poles", "\(entry.poles)")
        row("Schnellste Runden", "\(entry.fastestLaps)")
        row("Ausfälle", "\(entry.dnfs)")
        row("Boxenstopps", "\(entry.totalPitStops)")
        row("Bestes Ergebnis", entry.bestFinish.map { "P\($0)" } ?? "—")
        row("Mittlere Platzierung", entry.averageFinish.map { String(format: "%.1f", $0) } ?? "—")
        row("Mittlere Rundenzeit", entry.averageLapTime.map { RaceControl.formatLapTime($0) } ?? "—")
        row("Schnellste Runde", entry.bestLapTime.map { RaceControl.formatLapTime($0) } ?? "—")
        print("")
        return
    }

    print(style.bold("\nSTATISTIK \(season.year)")
          + style.dim("   nach \(season.completedRounds) Rennen"))
    print(style.dim("POS  FAHRER          REN  SIE  POD  POL   FL  DNF  BOX   Ø POS   Ø RUNDE"))
    for entry in table {
        guard let driver = data.drivers.first(where: { $0.id == entry.driverID }) else { continue }
        var line = padLeft("\(entry.position)", 3) + "  "
        line += fit(driver.lastName, 16)
        line += padLeft("\(entry.races)", 3) + "  "
        line += padLeft("\(entry.wins)", 3) + "  "
        line += padLeft("\(entry.podiums)", 3) + "  "
        line += padLeft("\(entry.poles)", 3) + "  "
        line += padLeft("\(entry.fastestLaps)", 3) + "  "
        line += padLeft("\(entry.dnfs)", 3) + "  "
        line += padLeft("\(entry.totalPitStops)", 3) + "  "
        line += padLeft(entry.averageFinish.map { String(format: "%.1f", $0) } ?? "—", 6) + "  "
        line += padLeft(entry.averageLapTime.map { RaceControl.formatLapTime($0) } ?? "—", 9)
        print(line)
    }
    print("")
}

// MARK: - quali

func seasonQualifying(data: RaceData, style: Style) {
    let season = loadSeasonOrExit()
    guard let last = season.results.last else {
        print("\nEs wurde noch kein Wochenende gefahren.\n")
        return
    }
    let round = season.calendar.first { $0.round == last.round }
    print(style.bold("\nQUALIFYING — RUNDE \(last.round): \(round?.name ?? last.circuitID)"))
    printQualifying(last.qualifying, data: data, style: style)
}

func printQualifying(_ result: QualifyingResult, data: RaceData, style: Style) {
    print(style.dim("\nPOS  #   FAHRER          Q1         Q2         Q3         RAUS"))
    for entry in result.entries {
        guard let driver = data.drivers.first(where: { $0.id == entry.driverID }) else { continue }
        func time(_ value: Double?) -> String {
            return value.map { RaceControl.formatLapTime($0) } ?? "—"
        }
        var line = padLeft("\(entry.position)", 3) + "  "
        line += padLeft("\(driver.number)", 2) + "  "
        line += fit(driver.lastName, 16)
        line += pad(time(entry.q1Time), 11)
        line += pad(time(entry.q2Time), 11)
        line += pad(entry.q3Time.map { style.bold(time($0)) } ?? "—", 11)
        line += entry.eliminatedIn == .q3 ? style.green("Q3") : style.dim(entry.eliminatedIn.displayName)
        if entry.position == 1 { line += style.yellow("   POLE") }
        print(line)
    }
    print("")
}

// MARK: - reset

func seasonReset() {
    do {
        try SeasonStore.delete()
        print("\nGespeicherte Saison gelöscht.\n")
    } catch {
        FileHandle.standardError.write("Konnte nicht löschen: \(error)\n".data(using: .utf8)!)
    }
}

// MARK: - Live-Rennen

/// Das Rennen im Terminal mitverfolgen.
func runRaceLive(engine: RaceEngine, drivers: [String: Driver], style: Style, speed: Double) {
    let frameInterval = 0.1
    let simulatedPerFrame = max(1.0, speed) * frameInterval

    print("\u{001B}[?25l", terminator: "")   // Cursor aus
    defer { print("\u{001B}[?25h", terminator: "") }

    while !engine.isFinished {
        engine.advance(simulatedPerFrame)
        let frame = render(engine.snapshot(), drivers: drivers, style: style)
        print("\u{001B}[H\u{001B}[2J" + frame, terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: frameInterval)
    }
}
