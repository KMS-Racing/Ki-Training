import Foundation

/// Wozu eine Meldung gehört — die UI färbt danach ein.
public enum MessageCategory: String, Codable, Hashable, Sendable {
    case flag
    case incident
    case penalty
    case pit
    case weather
    case info
    case result
}

/// Eine Meldung der Rennleitung, so wie sie im echten Timing steht.
///
/// ```
/// LAP 18 / VSC DEPLOYED
/// LAP 31 / CAR 44 (HAM) — 5 SECOND PENALTY — TRACK LIMITS
/// ```
public struct RaceControlMessage: Codable, Hashable, Sendable, Identifiable {
    /// Fortlaufende Nummer, damit die Reihenfolge eindeutig bleibt.
    public let id: Int
    public let lap: Int
    public let category: MessageCategory
    /// Die Hauptzeile, immer in Großbuchstaben — wie im Original.
    public let headline: String
    /// Zusatz, z.B. der Grund für eine Strafe.
    public let detail: String?
    /// Betroffene Startnummern.
    public let carNumbers: [Int]

    public init(
        id: Int,
        lap: Int,
        category: MessageCategory,
        headline: String,
        detail: String? = nil,
        carNumbers: [Int] = []
    ) {
        self.id = id
        self.lap = lap
        self.category = category
        self.headline = headline
        self.detail = detail
        self.carNumbers = carNumbers
    }

    /// Eine Zeile, fertig zum Anzeigen.
    public var displayLine: String {
        var line = "LAP \(lap) / \(headline)"
        if let detail = detail, !detail.isEmpty {
            line += " — \(detail)"
        }
        return line
    }
}

/// Sammelt und nummeriert die Meldungen der Rennleitung.
///
/// Sie hängt am `EventBus`: Die Simulation meldet nur, *dass* etwas passiert ist —
/// die Race Control macht daraus den Text, den die Rennleitung herausgibt.
public final class RaceControl {
    public private(set) var messages: [RaceControlMessage] = []
    private var nextID = 1
    /// Die höchste Rundenzahl, die bisher gemeldet wurde.
    /// Ereignisse ohne eigene Runde (z.B. die Zielflagge) hängen sich daran.
    private var lastKnownLap = 1
    private let numberLookup: [String: Int]
    private let nameLookup: [String: String]

    public init(drivers: [Driver]) {
        var numbers: [String: Int] = [:]
        var names: [String: String] = [:]
        for driver in drivers {
            numbers[driver.id] = driver.number
            names[driver.id] = driver.id
        }
        self.numberLookup = numbers
        self.nameLookup = names
    }

    /// Meldung anlegen.
    @discardableResult
    public func post(
        lap: Int,
        category: MessageCategory,
        headline: String,
        detail: String? = nil,
        driverIDs: [String] = []
    ) -> RaceControlMessage {
        lastKnownLap = max(lastKnownLap, lap)
        let numbers = driverIDs.compactMap { numberLookup[$0] }
        let message = RaceControlMessage(
            id: nextID,
            lap: lap,
            category: category,
            headline: headline,
            detail: detail,
            carNumbers: numbers
        )
        nextID += 1
        messages.append(message)
        return message
    }

    /// Wandelt ein Renn-Ereignis in die passende Meldung um.
    ///
    /// Nicht jedes Ereignis wird gemeldet — abgeschlossene Runden zum Beispiel
    /// stehen im Timing Tower, nicht im Meldungsfenster. Die Rennleitung meldet nur,
    /// was für alle wichtig ist.
    public func handle(_ event: RaceEvent) {
        switch event {
        case .raceStarted:
            post(lap: 1, category: .flag, headline: "GREEN FLAG", detail: "RACE STARTED")

        case .yellowFlag(let sector, let lap):
            post(lap: lap, category: .flag, headline: "YELLOW FLAG", detail: "SECTOR \(sector)")

        case .virtualSafetyCarDeployed(let lap, let reason):
            post(lap: lap, category: .flag, headline: "VSC DEPLOYED", detail: reason)

        case .virtualSafetyCarEnding(let lap):
            post(lap: lap, category: .flag, headline: "VSC ENDING")

        case .safetyCarDeployed(let lap, let reason):
            post(lap: lap, category: .flag, headline: "SAFETY CAR DEPLOYED", detail: reason)

        case .safetyCarEnding(let lap):
            post(lap: lap, category: .flag, headline: "SAFETY CAR IN THIS LAP")

        case .greenFlag(let lap):
            post(lap: lap, category: .flag, headline: "GREEN FLAG", detail: "TRACK CLEAR")

        case .redFlag(let lap, let reason):
            post(lap: lap, category: .flag, headline: "RED FLAG", detail: reason)

        case .raceResumed(let lap):
            post(lap: lap, category: .flag, headline: "RACE RESUMED")

        case .incident(let incident):
            let names = incident.driverIDs.compactMap { nameLookup[$0] }.joined(separator: ", ")
            post(
                lap: incident.lap,
                category: .incident,
                headline: "\(incident.kind.displayName) — \(names)",
                detail: "SECTOR \(incident.sector)",
                driverIDs: incident.driverIDs
            )

        case .penalty(let driverID, let lap, let seconds, let reason):
            let name = nameLookup[driverID] ?? driverID
            let number = numberLookup[driverID].map { "CAR \($0) (\(name))" } ?? name
            post(
                lap: lap,
                category: .penalty,
                headline: "\(number) — \(Int(seconds)) SECOND PENALTY",
                detail: reason,
                driverIDs: [driverID]
            )

        case .retirement(let driverID, let lap, let reason):
            let name = nameLookup[driverID] ?? driverID
            let number = numberLookup[driverID].map { "CAR \($0) (\(name))" } ?? name
            post(lap: lap, category: .incident, headline: "\(number) — DNF", detail: reason, driverIDs: [driverID])

        case .weatherChanged(_, let to, let lap):
            post(lap: lap, category: .weather, headline: "WEATHER — \(to.displayName)")

        case .fastestLap(let driverID, let lap, let lapTime):
            let name = nameLookup[driverID] ?? driverID
            post(
                lap: lap,
                category: .info,
                headline: "FASTEST LAP — \(name)",
                detail: RaceControl.formatLapTime(lapTime),
                driverIDs: [driverID]
            )

        case .raceFinished:
            post(lap: lastKnownLap, category: .result, headline: "CHEQUERED FLAG")

        case .lapCompleted, .overtake, .pitStop:
            break   // steht im Timing Tower, nicht in den Meldungen
        }
    }

    /// Die letzten `count` Meldungen, neueste zuerst.
    public func latest(_ count: Int) -> [RaceControlMessage] {
        return Array(messages.suffix(count).reversed())
    }

    /// Sekunden als Rundenzeit: `83.412` → `1:23.412`.
    public static func formatLapTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let minutes = Int(seconds) / 60
        let rest = seconds - Double(minutes * 60)
        return String(format: "%d:%06.3f", minutes, rest)
    }

    /// Sekunden als Abstand: `+1.824`.
    public static func formatGap(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        return String(format: "+%.3f", seconds)
    }
}
