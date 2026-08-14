import Foundation

/// Was für ein Zwischenfall passiert ist.
public enum IncidentKind: String, Codable, Hashable, Sendable {
    /// Dreher, fährt aber weiter.
    case spin
    /// Kurz neben der Strecke, verliert Zeit.
    case offTrack
    /// Berührung zwischen zwei Autos.
    case collision
    /// Schwerer Unfall, das Auto steht.
    case crash
    /// Technischer Defekt.
    case mechanical
    /// Reifenschaden.
    case puncture

    public var displayName: String {
        switch self {
        case .spin: return "SPIN"
        case .offTrack: return "OFF TRACK"
        case .collision: return "COLLISION"
        case .crash: return "CRASH"
        case .mechanical: return "TECHNICAL"
        case .puncture: return "PUNCTURE"
        }
    }
}

/// Wie schlimm es ist. Danach entscheidet der Race Director.
public enum IncidentSeverity: String, Codable, Hashable, Sendable, Comparable {
    case low
    case medium
    case high
    case extreme

    /// Rangfolge, damit man Schweregrade vergleichen kann.
    public var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .extreme: return 3
        }
    }

    public static func < (lhs: IncidentSeverity, rhs: IncidentSeverity) -> Bool {
        return lhs.order < rhs.order
    }

    public var displayName: String {
        return rawValue.uppercased()
    }
}

/// Ein Zwischenfall auf der Strecke — die Eingabe für den Race Director.
public struct Incident: Codable, Hashable, Sendable {
    public let lap: Int
    /// Alle beteiligten Autos.
    public let driverIDs: [String]
    public let kind: IncidentKind
    public let severity: IncidentSeverity
    /// In welchem Sektor (1…3).
    public let sector: Int
    /// Liegt Auto oder Trümmer so, dass die Strecke nicht mehr frei ist?
    public let blocksTrack: Bool
    /// Bleibt das Auto stehen (Ausfall) oder fährt es weiter?
    public let carStopped: Bool

    public init(
        lap: Int,
        driverIDs: [String],
        kind: IncidentKind,
        severity: IncidentSeverity,
        sector: Int,
        blocksTrack: Bool,
        carStopped: Bool
    ) {
        self.lap = lap
        self.driverIDs = driverIDs
        self.kind = kind
        self.severity = severity
        self.sector = sector
        self.blocksTrack = blocksTrack
        self.carStopped = carStopped
    }
}

/// Alles, was im Rennen passieren kann.
///
/// Das ist das Herz der ereignisgesteuerten Architektur: die Simulation *meldet* nur,
/// was geschehen ist. Wer darauf reagiert — Race Control, Timing, UI — entscheiden
/// die Empfänger selbst. Dadurch muss die Renn-Schleife nichts über die Anzeige wissen.
public enum RaceEvent: Codable, Hashable, Sendable {
    case raceStarted
    case lapCompleted(driverID: String, lap: Int, lapTime: Double)
    case fastestLap(driverID: String, lap: Int, lapTime: Double)
    case overtake(driverID: String, overtakenID: String, lap: Int, newPosition: Int)
    case pitStop(driverID: String, lap: Int, compound: TyreCompound, duration: Double)
    case incident(Incident)
    case penalty(driverID: String, lap: Int, seconds: Double, reason: String)
    case retirement(driverID: String, lap: Int, reason: String)
    case yellowFlag(sector: Int, lap: Int)
    case virtualSafetyCarDeployed(lap: Int, reason: String)
    case virtualSafetyCarEnding(lap: Int)
    case safetyCarDeployed(lap: Int, reason: String)
    case safetyCarEnding(lap: Int)
    case greenFlag(lap: Int)
    case redFlag(lap: Int, reason: String)
    case raceResumed(lap: Int)
    case weatherChanged(from: WeatherState, to: WeatherState, lap: Int)
    case raceFinished

    /// Kurzform fürs Log und für Tests, die die Ereignisfolge vergleichen.
    public var shortDescription: String {
        switch self {
        case .raceStarted:
            return "RACE_START"
        case .lapCompleted(let driverID, let lap, _):
            return "LAP:\(driverID):\(lap)"
        case .fastestLap(let driverID, let lap, _):
            return "FL:\(driverID):\(lap)"
        case .overtake(let driverID, let overtakenID, let lap, _):
            return "PASS:\(driverID)>\(overtakenID):\(lap)"
        case .pitStop(let driverID, let lap, let compound, _):
            return "PIT:\(driverID):\(lap):\(compound.rawValue)"
        case .incident(let incident):
            return "INC:\(incident.driverIDs.joined(separator: "+")):\(incident.kind.rawValue):\(incident.lap)"
        case .penalty(let driverID, let lap, let seconds, _):
            return "PEN:\(driverID):\(lap):\(seconds)"
        case .retirement(let driverID, let lap, _):
            return "DNF:\(driverID):\(lap)"
        case .yellowFlag(let sector, let lap):
            return "YEL:\(sector):\(lap)"
        case .virtualSafetyCarDeployed(let lap, _):
            return "VSC:\(lap)"
        case .virtualSafetyCarEnding(let lap):
            return "VSC_END:\(lap)"
        case .safetyCarDeployed(let lap, _):
            return "SC:\(lap)"
        case .safetyCarEnding(let lap):
            return "SC_END:\(lap)"
        case .greenFlag(let lap):
            return "GREEN:\(lap)"
        case .redFlag(let lap, _):
            return "RED:\(lap)"
        case .raceResumed(let lap):
            return "RESUME:\(lap)"
        case .weatherChanged(let from, let to, let lap):
            return "WX:\(from.rawValue)>\(to.rawValue):\(lap)"
        case .raceFinished:
            return "RACE_END"
        }
    }
}
