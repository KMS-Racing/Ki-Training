import Foundation
import RaceEngine

// =============================================================================
//  f1ctl — ein komplettes Rennen im Terminal
// -----------------------------------------------------------------------------
//  Absichtlich dünn: hier steckt keinerlei Rennlogik drin, nur Anzeige. Alles,
//  was gerechnet wird, kommt aus der RaceEngine. Damit lässt sich die Engine
//  überall ausprobieren, auch ohne Xcode und ohne SwiftUI.
//
//  Beispiel:
//      swift run f1ctl --circuit monza --laps 20 --seed 42 --speed 200
// =============================================================================

// MARK: - Aufrufparameter

struct Options {
    var circuit = "monza"
    var laps: Int? = nil
    var seed: UInt64 = 42
    /// Wie viele Rennsekunden pro echter Sekunde vergehen.
    var speed: Double = 120
    var weather: WeatherState = .dry
    var aiStrength: Double = 0.9
    /// Ohne Anzeige durchrechnen und nur das Ergebnis zeigen.
    var headless = false
    var color = true
    /// Am Ende alle Meldungen der Rennleitung ausgeben.
    var showLog = false

    static let usage = """
    f1ctl — F1 Race Control im Terminal

    Verwendung:
      swift run f1ctl [Optionen]

    Optionen:
      --circuit <id>     monza | spa | monaco | silverstone | bahrain | madrid | suzuka
      --laps <n>         Rennlänge (Standard: Renndistanz der Strecke)
      --seed <n>         Zufalls-Startwert; gleicher Seed = gleiches Rennen
      --speed <n>        Rennsekunden pro echter Sekunde (Standard 120)
      --weather <s>      dry | cloudy | lightRain | heavyRain | drying
      --ai <0..1>        Stärke der KI (Standard 0.9)
      --headless         Ohne Live-Anzeige, nur Endergebnis
      --log              Alle Meldungen der Rennleitung ausgeben
      --no-color         Keine Farben
      --list             Verfügbare Strecken anzeigen
      --help             Diese Hilfe
    """
}

func parseOptions(_ arguments: [String]) -> Options? {
    var options = Options()
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        func value() -> String? {
            guard index + 1 < arguments.count else { return nil }
            index += 1
            return arguments[index]
        }

        switch argument {
        case "--help", "-h":
            print(Options.usage)
            return nil
        case "--circuit":
            if let v = value() { options.circuit = v }
        case "--laps":
            if let v = value(), let n = Int(v) { options.laps = n }
        case "--seed":
            if let v = value(), let n = UInt64(v) { options.seed = n }
        case "--speed":
            if let v = value(), let n = Double(v) { options.speed = max(1, n) }
        case "--ai":
            if let v = value(), let n = Double(v) { options.aiStrength = min(max(n, 0), 1) }
        case "--weather":
            if let v = value(), let state = WeatherState(rawValue: v) { options.weather = state }
        case "--headless":
            options.headless = true
        case "--log":
            options.showLog = true
        case "--no-color":
            options.color = false
        case "--list":
            listCircuits()
            return nil
        default:
            FileHandle.standardError.write("Unbekannte Option: \(argument)\n".data(using: .utf8)!)
            print(Options.usage)
            return nil
        }
        index += 1
    }
    return options
}

func listCircuits() {
    guard let circuits = try? DataLoader.loadCircuits() else { return }
    print("Verfügbare Strecken:")
    for circuit in circuits {
        print(String(format: "  %-12s %-38s %2d Runden  %.3f km",
                     (circuit.id as NSString).utf8String!,
                     (circuit.name as NSString).utf8String!,
                     circuit.defaultLaps,
                     circuit.lengthKm))
    }
}

// MARK: - Farben und Formatierung

struct Style {
    let enabled: Bool
    func paint(_ text: String, _ code: String) -> String {
        guard enabled else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
    func dim(_ t: String) -> String { paint(t, "2") }
    func bold(_ t: String) -> String { paint(t, "1") }
    func red(_ t: String) -> String { paint(t, "31") }
    func green(_ t: String) -> String { paint(t, "32") }
    func yellow(_ t: String) -> String { paint(t, "33") }
    func cyan(_ t: String) -> String { paint(t, "36") }
    func white(_ t: String) -> String { paint(t, "97") }
}

/// Wie breit der Text auf dem Bildschirm wirklich ist.
///
/// Farbcodes wie `\u{001B}[31m` stehen zwar im String, sind aber unsichtbar.
/// Zählt man sie mit, werden farbige Spalten viel zu breit.
func visibleWidth(_ text: String) -> Int {
    var width = 0
    var inEscape = false
    for character in text {
        if inEscape {
            if character == "m" { inEscape = false }
        } else if character == "\u{001B}" {
            inEscape = true
        } else {
            width += 1
        }
    }
    return width
}

/// Text auf feste Breite bringen (links).
func pad(_ text: String, _ width: Int) -> String {
    let visible = visibleWidth(text)
    if visible >= width { return text }
    return text + String(repeating: " ", count: width - visible)
}

/// Text auf feste Breite bringen (rechts).
func padLeft(_ text: String, _ width: Int) -> String {
    let visible = visibleWidth(text)
    if visible >= width { return text }
    return String(repeating: " ", count: width - visible) + text
}

func compoundColor(_ compound: TyreCompound, _ style: Style) -> String {
    switch compound {
    case .soft: return style.red(compound.letter)
    case .medium: return style.yellow(compound.letter)
    case .hard: return style.white(compound.letter)
    case .intermediate: return style.green(compound.letter)
    case .wet: return style.cyan(compound.letter)
    }
}

func statusColor(_ status: TrackStatus, _ style: Style) -> String {
    switch status {
    case .green: return style.green(status.displayName)
    case .yellow: return style.yellow(status.displayName)
    case .virtualSafetyCar, .safetyCar: return style.yellow(style.bold(status.displayName))
    case .redFlag: return style.red(style.bold(status.displayName))
    case .finished: return style.white(status.displayName)
    }
}

// MARK: - Anzeige

func render(_ snapshot: RaceSnapshot, drivers: [String: Driver], style: Style) -> String {
    var out = ""

    // --- Kopfzeile ---
    out += style.bold("F1 RACE CONTROL") + "   " + style.white(snapshot.circuit.name.uppercased()) + "\n"
    var header = "LAP \(snapshot.lap) / \(snapshot.totalLaps)    " + statusColor(snapshot.trackStatus, style)
    if let countdown = snapshot.neutralisationCountdown {
        header += style.bold("   ENDING IN \(countdown)")
    }
    out += header + "\n"
    out += style.dim(String(repeating: "─", count: 74)) + "\n"

    // --- Timing Tower ---
    out += style.dim("POS  #   DRIVER       GAP        INTERVAL   LAST      TYRE   PIT  ±") + "\n"
    for state in snapshot.standings.prefix(24) {
        guard let driver = drivers[state.driverID] else { continue }

        let gapText: String
        let intervalText: String
        switch state.status {
        case .retired:
            gapText = style.red("DNF")
            intervalText = "—"
        case .inPitLane:
            gapText = style.cyan("PIT")
            intervalText = "—"
        default:
            if state.position == 1 {
                gapText = "LEADER"
                intervalText = "—"
            } else if state.lapsDown >= 1 {
                gapText = "+\(state.lapsDown) LAP"
                intervalText = "—"
            } else {
                gapText = RaceControl.formatGap(state.gapToLeader)
                intervalText = RaceControl.formatGap(state.interval)
            }
        }

        let lastLap = state.lastLapTime.map { RaceControl.formatLapTime($0) } ?? "—"
        let change = state.positionChange
        let changeText = change > 0 ? style.green("+\(change)")
            : (change < 0 ? style.red("\(change)") : style.dim(" 0"))

        var line = padLeft("\(state.position)", 3) + "  "
        line += padLeft("\(driver.number)", 2) + "  "
        line += pad(driver.lastName, 12)
        line += pad(gapText, 11)
        line += pad(intervalText, 11)
        line += pad(lastLap, 10)
        line += compoundColor(state.tyres.compound, style) + padLeft("\(state.tyres.age)", 3) + "   "
        line += padLeft("\(state.pitStops)", 3) + "  "
        line += changeText

        if state.hasFastestLap {
            line += " " + style.paint("FL", "35")
        }
        out += line + "\n"
    }

    // --- Wetter ---
    out += style.dim(String(repeating: "─", count: 74)) + "\n"
    let weather = snapshot.weather
    out += String(
        format: "%@  wetness %.2f   air %.0f°C   track %.0f°C   wind %.0f km/h   rain %.0f%%\n",
        style.cyan(weather.state.displayName),
        weather.trackWetness,
        weather.airTemperature,
        weather.trackTemperature,
        weather.windSpeed,
        weather.rainProbability * 100
    )

    // --- Meldungen der Rennleitung ---
    out += style.dim(String(repeating: "─", count: 74)) + "\n"
    out += style.bold("RACE CONTROL") + "\n"
    for message in snapshot.messages.prefix(6) {
        let colored: String
        switch message.category {
        case .flag: colored = style.yellow(message.displayLine)
        case .incident: colored = style.red(message.displayLine)
        case .penalty: colored = style.paint(message.displayLine, "35")
        case .weather: colored = style.cyan(message.displayLine)
        default: colored = style.dim(message.displayLine)
        }
        out += "  " + colored + "\n"
    }

    return out
}

func renderResult(_ result: RaceResult, drivers: [String: Driver], style: Style) -> String {
    var out = "\n" + style.bold("═══ RACE FINISHED — \(result.circuitName.uppercased()) ═══") + "\n\n"
    out += style.dim("POS  DRIVER            LAPS   TIME / GAP        PIT  PTS") + "\n"

    let winnerTime = result.winner?.classifiedTime ?? 0
    for entry in result.entries {
        guard let driver = drivers[entry.driverID] else { continue }
        let timeText: String
        if entry.status == .retired {
            timeText = style.red("DNF — \(entry.retirementReason ?? "")")
        } else if entry.position == 1 {
            timeText = RaceControl.formatLapTime(entry.classifiedTime)
        } else if entry.lapsCompleted < result.totalLaps {
            timeText = "+\(result.totalLaps - entry.lapsCompleted) LAP"
        } else {
            timeText = RaceControl.formatGap(entry.classifiedTime - winnerTime)
        }

        var line = padLeft("\(entry.position)", 3) + "  "
        line += pad(driver.lastName, 18)
        line += padLeft("\(entry.lapsCompleted)", 4) + "   "
        line += pad(timeText, 26)
        line += padLeft("\(entry.pitStops)", 3) + "  "
        line += padLeft("\(entry.points)", 3)
        if entry.penaltySeconds > 0 {
            line += style.paint("  +\(Int(entry.penaltySeconds))s PEN", "35")
        }
        if entry.hasFastestLap {
            line += style.paint("  FL", "35")
        }
        out += line + "\n"
    }

    if let fastest = result.fastestLap, let driver = drivers[fastest.driverID] {
        out += "\n" + style.bold("FASTEST LAP  ") + "\(driver.lastName)  "
            + RaceControl.formatLapTime(fastest.time) + "  (lap \(fastest.lap))\n"
    }
    out += style.dim("Boxenstopps gesamt: \(result.totalPitStops)   Ausfälle: \(result.retirements.count)\n")
    return out
}

// MARK: - Hauptprogramm

guard let options = parseOptions(CommandLine.arguments) else {
    exit(0)
}

let data: RaceData
do {
    data = try DataLoader.loadAll()
} catch {
    FileHandle.standardError.write("Stammdaten konnten nicht geladen werden: \(error)\n".data(using: .utf8)!)
    exit(1)
}

guard let circuit = data.circuit(id: options.circuit) else {
    FileHandle.standardError.write("Unbekannte Strecke '\(options.circuit)'.\n".data(using: .utf8)!)
    listCircuits()
    exit(1)
}

let style = Style(enabled: options.color)
var driversByID: [String: Driver] = [:]
for driver in data.drivers { driversByID[driver.id] = driver }

let configuration = RaceConfiguration(
    circuit: circuit,
    drivers: data.drivers,
    teams: data.teams,
    laps: options.laps,
    startingWeather: options.weather,
    aiStrength: options.aiStrength,
    seed: options.seed
)

let engine = RaceEngine(configuration: configuration)

print(style.bold("\nF1 RACE CONTROL"))
print("\(circuit.name) — \(configuration.laps) Runden — Seed \(options.seed)")
print(style.dim("Gleicher Seed = gleiches Rennen.\n"))

if options.headless {
    engine.runToCompletion()
} else {
    // 10 Bilder pro Sekunde; pro Bild so viel Rennzeit wie eingestellt.
    let frameInterval = 0.1
    let simulatedPerFrame = options.speed * frameInterval
    print("\u{001B}[?25l", terminator: "")   // Cursor aus
    defer { print("\u{001B}[?25h", terminator: "") }

    while !engine.isFinished {
        engine.advance(simulatedPerFrame)
        let frame = render(engine.snapshot(), drivers: driversByID, style: style)
        print("\u{001B}[H\u{001B}[2J" + frame, terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: frameInterval)
    }
}

if options.showLog {
    print("\n" + style.bold("RACE CONTROL — VOLLSTÄNDIGES PROTOKOLL"))
    for message in engine.raceControl.messages {
        print("  " + message.displayLine)
    }
}

if let result = engine.result() {
    print(renderResult(result, drivers: driversByID, style: style))
} else {
    print("Das Rennen wurde nicht beendet.")
}
