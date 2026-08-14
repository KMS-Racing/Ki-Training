import Foundation

/// Die fünf Reifenmischungen.
///
/// Die Grundregel der Formel 1: weicher = mehr Grip, aber schneller kaputt.
/// Genau das steckt in `dryLapDelta` (Tempo) und `baseWearPerLap` (Haltbarkeit).
public enum TyreCompound: String, Codable, CaseIterable, Sendable {
    case soft
    case medium
    case hard
    case intermediate
    case wet

    /// Der Buchstabe im Timing Tower.
    public var letter: String {
        switch self {
        case .soft: return "S"
        case .medium: return "M"
        case .hard: return "H"
        case .intermediate: return "I"
        case .wet: return "W"
        }
    }

    public var displayName: String {
        switch self {
        case .soft: return "Soft"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .intermediate: return "Intermediate"
        case .wet: return "Wet"
        }
    }

    /// Slick = Trockenreifen, kein Profil.
    public var isSlick: Bool {
        switch self {
        case .soft, .medium, .hard: return true
        case .intermediate, .wet: return false
        }
    }

    /// Tempo-Vorteil bzw. -Nachteil auf trockener Strecke, in Sekunden pro Runde.
    /// Medium ist der Nullpunkt.
    public var dryLapDelta: Double {
        switch self {
        case .soft: return -0.60
        case .medium: return 0.0
        case .hard: return 0.55
        case .intermediate: return 3.50
        case .wet: return 6.00
        }
    }

    /// Wie viel Reifenleben eine Runde kostet (Anteil von 1.0).
    /// `0.055` heißt: nach etwa 18 Runden ist der Reifen durch.
    public var baseWearPerLap: Double {
        switch self {
        case .soft: return 0.055
        case .medium: return 0.038
        case .hard: return 0.027
        case .intermediate: return 0.045
        case .wet: return 0.040
        }
    }

    /// Bei welcher Streckennässe (0…1) dieser Reifen am besten funktioniert.
    public var optimalWetness: Double {
        switch self {
        case .soft, .medium, .hard: return 0.0
        case .intermediate: return 0.40
        case .wet: return 0.85
        }
    }

    /// Wie weit man von der idealen Nässe abweichen darf, bevor es richtig weh tut.
    public var wetnessTolerance: Double {
        switch self {
        case .soft, .medium, .hard: return 0.12
        case .intermediate: return 0.28
        case .wet: return 0.30
        }
    }

    /// Die für diese Streckennässe sinnvollste Mischung.
    /// Wird von der KI-Boxenstrategie und beim Rennstart benutzt.
    public static func best(forWetness wetness: Double) -> TyreCompound {
        if wetness >= 0.62 { return .wet }
        if wetness >= 0.22 { return .intermediate }
        return .medium
    }
}

/// Ein konkreter Reifensatz an einem Auto.
public struct TyreSet: Codable, Hashable, Sendable {
    public var compound: TyreCompound
    /// Gefahrene Runden auf diesem Satz.
    public var age: Int
    /// Betriebstemperatur in °C. Außerhalb des Fensters gibt es weniger Grip.
    public var temperature: Double
    /// Abnutzung von 0 (neu) bis 1 (durch).
    public var wear: Double
    /// Aktueller Grip von 0 bis 1. Wird vom `TyreModel` nachgeführt.
    public var grip: Double

    public init(
        compound: TyreCompound,
        age: Int = 0,
        temperature: Double = 90,
        wear: Double = 0,
        grip: Double = 1
    ) {
        self.compound = compound
        self.age = age
        self.temperature = temperature
        self.wear = wear
        self.grip = grip
    }

    /// Frischer Satz derselben Mischung.
    public static func fresh(_ compound: TyreCompound) -> TyreSet {
        return TyreSet(compound: compound, age: 0, temperature: 90, wear: 0, grip: 1)
    }

    /// Reifen am Ende („die Klippe“) — die UI warnt ab hier.
    public var isCritical: Bool {
        return wear > 0.80
    }
}
