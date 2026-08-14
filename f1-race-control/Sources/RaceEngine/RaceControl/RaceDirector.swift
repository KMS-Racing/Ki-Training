import Foundation

/// Was die Rennleitung anordnen kann.
public enum RaceControlDecision: String, Hashable, Sendable {
    case noAction
    case localYellow
    case virtualSafetyCar
    case safetyCar
    case redFlag

    /// Rangfolge — höher heißt einschneidender.
    public var level: Int {
        switch self {
        case .noAction: return 0
        case .localYellow: return 1
        case .virtualSafetyCar: return 2
        case .safetyCar: return 3
        case .redFlag: return 4
        }
    }
}

/// Die Entscheidung samt Begründung.
public struct DirectorVerdict: Hashable, Sendable {
    public let decision: RaceControlDecision
    /// Warum — in ganzen Sätzen, damit die App es anzeigen kann.
    public let justification: String
    /// Wie lange das Bergen voraussichtlich dauert (Sekunden).
    public let clearanceSeconds: Double

    public init(decision: RaceControlDecision, justification: String, clearanceSeconds: Double) {
        self.decision = decision
        self.justification = justification
        self.clearanceSeconds = clearanceSeconds
    }
}

/// Die „Renndirektor-KI“ — vorerst regelbasiert.
///
/// Bewusst **ohne Zufall**: dieselbe Lage führt immer zur selben Anordnung. Dadurch
/// ist die Entscheidung nachvollziehbar, testbar und man kann sie dem Nutzer erklären
/// („Safety Car, weil die Strecke blockiert ist“). Genau das verlangt die Aufgabe.
///
/// Die Leiter der Eskalation:
/// ```
/// Dreher, fährt weiter          → YELLOW FLAG
/// Auto steht abseits            → VIRTUAL SAFETY CAR
/// Auto/Trümmer auf der Strecke  → SAFETY CAR
/// Strecke blockiert, mehrere    → RED FLAG
/// ```
public enum RaceDirector {

    /// Bewertet einen Zwischenfall.
    ///
    /// - Parameters:
    ///   - incident: Was passiert ist.
    ///   - currentStatus: Was gerade schon gilt — es wird nie zurückgestuft.
    ///   - wetness: Nasse Strecke macht das Bergen gefährlicher.
    ///   - lapsRemaining: Kurz vor Schluss wird nicht mehr abgebrochen.
    ///   - runningCars: Wie viele Autos noch fahren.
    public static func evaluate(
        incident: Incident,
        currentStatus: TrackStatus,
        wetness: Double,
        lapsRemaining: Int,
        runningCars: Int
    ) -> DirectorVerdict {

        var decision = baseDecision(for: incident)

        // --- Verschärfungen ---

        // Auf nasser Strecke ist Bergen deutlich gefährlicher: eine Stufe höher.
        if wetness > 0.75, decision.level >= RaceControlDecision.localYellow.level {
            decision = escalate(decision)
        }

        // --- Abmilderungen ---

        // Auf den letzten Runden wird ein Rennen nicht mehr abgebrochen,
        // sondern hinter dem Safety Car zu Ende gefahren.
        if decision == .redFlag, lapsRemaining <= 3 {
            decision = .safetyCar
        }

        // Sind kaum noch Autos im Rennen, reicht das VSC — ein Safety Car würde
        // das Rennen unnötig zerstören.
        if decision == .safetyCar, runningCars <= 4 {
            decision = .virtualSafetyCar
        }

        // Es gilt schon etwas Schärferes: keine neue Anordnung.
        if statusLevel(currentStatus) >= decision.level {
            return DirectorVerdict(
                decision: .noAction,
                justification: "Incident noted. \(currentStatus.displayName) already in force.",
                clearanceSeconds: 0
            )
        }

        return DirectorVerdict(
            decision: decision,
            justification: justify(decision: decision, incident: incident, wetness: wetness),
            clearanceSeconds: clearance(for: incident, decision: decision)
        )
    }

    /// Die Grundentscheidung allein aus dem Zwischenfall.
    private static func baseDecision(for incident: Incident) -> RaceControlDecision {
        // Mehrere Autos und die Strecke dicht → Rennabbruch.
        if incident.blocksTrack, incident.driverIDs.count >= 3 {
            return .redFlag
        }
        if incident.blocksTrack, incident.severity == .extreme {
            return .redFlag
        }
        // Etwas liegt auf der Strecke → Safety Car, damit geräumt werden kann.
        if incident.blocksTrack {
            return .safetyCar
        }
        // Auto steht, aber sicher abseits → VSC reicht.
        if incident.carStopped {
            return .virtualSafetyCar
        }
        // Fährt weiter, aber es liegen vielleicht Teile herum → örtliches Gelb.
        if incident.severity >= .medium {
            return .localYellow
        }
        return .noAction
    }

    private static func escalate(_ decision: RaceControlDecision) -> RaceControlDecision {
        switch decision {
        case .noAction: return .localYellow
        case .localYellow: return .virtualSafetyCar
        case .virtualSafetyCar: return .safetyCar
        case .safetyCar: return .redFlag
        case .redFlag: return .redFlag
        }
    }

    private static func statusLevel(_ status: TrackStatus) -> Int {
        switch status {
        case .green, .finished: return 0
        case .yellow: return 1
        case .virtualSafetyCar: return 2
        case .safetyCar: return 3
        case .redFlag: return 4
        }
    }

    /// Der Erklärtext, den die App anzeigt.
    private static func justify(
        decision: RaceControlDecision,
        incident: Incident,
        wetness: Double
    ) -> String {
        let cars = incident.driverIDs.joined(separator: ", ")
        let carCount = incident.driverIDs.count
        let carPhrase = carCount == 1 ? "car \(cars)" : "\(carCount) cars (\(cars))"
        let wetPhrase = wetness > 0.75 ? " Conditions are wet, which makes recovery more dangerous." : ""

        switch decision {
        case .noAction:
            return "No action required."
        case .localYellow:
            return "Yellow flag in sector \(incident.sector): \(incident.kind.displayName.lowercased()) involving \(carPhrase). The track is not blocked and the car is still moving.\(wetPhrase)"
        case .virtualSafetyCar:
            return "Virtual Safety Car deployed because \(carPhrase) stopped in sector \(incident.sector). The car is off the racing line, so a full Safety Car is not needed — drivers must hold a delta instead.\(wetPhrase)"
        case .safetyCar:
            return "Safety Car deployed because the track is blocked in sector \(incident.sector) after a \(incident.kind.displayName.lowercased()) involving \(carPhrase). Marshals need the track at reduced speed to recover the car.\(wetPhrase)"
        case .redFlag:
            return "Red flag: the track is blocked in sector \(incident.sector) by a \(incident.kind.displayName.lowercased()) involving \(carPhrase). The session is suspended until the track is clear.\(wetPhrase)"
        }
    }

    /// Wie lange die Bergung dauert.
    private static func clearance(for incident: Incident, decision: RaceControlDecision) -> Double {
        var seconds: Double
        switch decision {
        case .noAction: seconds = 0
        case .localYellow: seconds = 30
        case .virtualSafetyCar: seconds = 75
        case .safetyCar: seconds = 150
        case .redFlag: seconds = 300
        }
        // Mehr beteiligte Autos = mehr Aufräumen.
        seconds += Double(max(0, incident.driverIDs.count - 1)) * 25
        if incident.blocksTrack { seconds += 30 }
        return seconds
    }
}
