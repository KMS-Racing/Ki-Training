import Foundation

/// Die Phase einer Neutralisierung (VSC oder Safety Car).
public enum NeutralisationPhase: String, Codable, Hashable, Sendable {
    /// Gerade ausgerufen, die Autos bremsen noch ab.
    case deploying
    /// Läuft.
    case active
    /// Der Countdown zur Freigabe läuft.
    case ending
}

/// Der Streckenzustand — was die Rennleitung gerade zeigt.
public enum TrackStatus: Codable, Hashable, Sendable {
    case green
    case yellow(sector: Int)
    case virtualSafetyCar(phase: NeutralisationPhase)
    case safetyCar(phase: NeutralisationPhase)
    case redFlag
    case finished

    public var displayName: String {
        switch self {
        case .green: return "GREEN FLAG"
        case .yellow(let sector): return "YELLOW FLAG SECTOR \(sector)"
        case .virtualSafetyCar: return "VIRTUAL SAFETY CAR"
        case .safetyCar: return "SAFETY CAR"
        case .redFlag: return "RED FLAG"
        case .finished: return "CHEQUERED FLAG"
        }
    }

    /// Ist das Rennen gerade neutralisiert (VSC oder SC)?
    public var isNeutralised: Bool {
        switch self {
        case .virtualSafetyCar, .safetyCar: return true
        default: return false
        }
    }

    /// Darf überholt werden? Unter Gelb, VSC und SC ist Überholen verboten.
    public var allowsOvertaking: Bool {
        switch self {
        case .green: return true
        case .yellow: return false
        case .virtualSafetyCar, .safetyCar: return false
        case .redFlag, .finished: return false
        }
    }

    /// Um welchen Faktor die Rundenzeit steigt.
    ///
    /// Unter VSC muss ein Delta eingehalten werden (rund 40 % langsamer), hinter dem
    /// Safety Car fährt das Feld noch langsamer im Pulk.
    public var lapTimeMultiplier: Double {
        switch self {
        case .green: return 1.0
        case .yellow: return 1.05
        case .virtualSafetyCar: return 1.40
        case .safetyCar: return 1.60
        case .redFlag, .finished: return 1.0
        }
    }

    /// Läuft das Rennen überhaupt?
    public var isRunning: Bool {
        switch self {
        case .redFlag, .finished: return false
        default: return true
        }
    }
}

/// Was ein Auto gerade tut.
public enum DriverStatus: String, Codable, Hashable, Sendable {
    case running
    /// Fährt gerade durch die Boxengasse.
    case inPitLane
    /// Ausgefallen.
    case retired
    /// Hat die Zielflagge gesehen.
    case finished
}

/// Der komplette Zustand eines Autos zu einem Zeitpunkt.
public struct DriverState: Codable, Hashable, Sendable, Identifiable {
    public var driverID: String
    public var id: String { driverID }

    public var position: Int
    public var gridPosition: Int
    public var lapsCompleted: Int
    /// Fortschritt auf der aktuellen Runde, 0…1. Damit setzt die Track Map das Auto.
    public var lapProgress: Double
    /// Gefahrene Rennzeit in Sekunden (ohne Strafen).
    public var totalTime: Double

    public var lastLapTime: Double?
    public var bestLapTime: Double?
    /// Sektorzeiten der zuletzt beendeten Runde.
    public var lastSectors: [Double]

    public var tyres: TyreSet
    public var status: DriverStatus
    public var retirementReason: String?
    public var pitStops: Int

    /// Rückstand auf den Führenden in Sekunden.
    public var gapToLeader: Double
    /// Rückstand auf den Vordermann in Sekunden.
    public var interval: Double
    /// Um wie viele Runden überrundet (0 = in der Führungsrunde).
    public var lapsDown: Int
    /// Aufaddierte Zeitstrafen in Sekunden.
    public var penaltySeconds: Double
    public var hasFastestLap: Bool
    /// Mit welchem Tempo gerade gefahren wird.
    public var pushLevel: PushLevel
    /// Ladestand des Energiespeichers, 0…1.
    public var battery: Double
    /// Sitzt hier ein Mensch am Steuer?
    public var isHumanControlled: Bool

    public init(
        driverID: String,
        position: Int,
        gridPosition: Int,
        lapsCompleted: Int = 0,
        lapProgress: Double = 0,
        totalTime: Double = 0,
        lastLapTime: Double? = nil,
        bestLapTime: Double? = nil,
        lastSectors: [Double] = [],
        tyres: TyreSet,
        status: DriverStatus = .running,
        retirementReason: String? = nil,
        pitStops: Int = 0,
        gapToLeader: Double = 0,
        interval: Double = 0,
        lapsDown: Int = 0,
        penaltySeconds: Double = 0,
        hasFastestLap: Bool = false,
        pushLevel: PushLevel = .normal,
        battery: Double = 1.0,
        isHumanControlled: Bool = false
    ) {
        self.driverID = driverID
        self.position = position
        self.gridPosition = gridPosition
        self.lapsCompleted = lapsCompleted
        self.lapProgress = lapProgress
        self.totalTime = totalTime
        self.lastLapTime = lastLapTime
        self.bestLapTime = bestLapTime
        self.lastSectors = lastSectors
        self.tyres = tyres
        self.status = status
        self.retirementReason = retirementReason
        self.pitStops = pitStops
        self.gapToLeader = gapToLeader
        self.interval = interval
        self.lapsDown = lapsDown
        self.penaltySeconds = penaltySeconds
        self.hasFastestLap = hasFastestLap
        self.pushLevel = pushLevel
        self.battery = battery
        self.isHumanControlled = isHumanControlled
    }

    /// Gesamtfortschritt im Rennen — Runden plus angefangene Runde.
    /// Danach wird die Reihenfolge im Feld bestimmt.
    public var raceProgress: Double {
        return Double(lapsCompleted) + lapProgress
    }

    /// Positionen gewonnen (positiv) oder verloren (negativ) gegenüber dem Start.
    public var positionChange: Int {
        return gridPosition - position
    }

    /// Fährt das Auto noch mit?
    public var isActive: Bool {
        return status == .running || status == .inPitLane
    }
}
