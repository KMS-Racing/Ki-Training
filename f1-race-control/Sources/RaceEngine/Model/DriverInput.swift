import Foundation

/// Wie hart ein Fahrer gerade fährt.
///
/// Das ist der zentrale Kompromiss der Formel 1 und damit das, was ein Mensch hier
/// wirklich steuert: Wer drückt, ist schneller — verbraucht aber Reifen und Batterie
/// und macht eher Fehler. Wer schont, verliert jetzt Zeit und gewinnt sie später zurück.
///
/// Es gibt bewusst **kein Lenken**: Die Engine rechnet Rundenzeiten, keine Physik.
/// Ein Lenkrad würde hier nur so tun als ob.
public enum PushLevel: String, Codable, CaseIterable, Sendable {
    /// Reifen und Batterie schonen.
    case conserve
    /// Normales Renntempo.
    case normal
    /// Angriffstempo.
    case push
    /// Alles geben — kostet Batterie und Reifen, und Fehler passieren leichter.
    case attack

    public var displayName: String {
        switch self {
        case .conserve: return "CONSERVE"
        case .normal: return "NORMAL"
        case .push: return "PUSH"
        case .attack: return "ATTACK"
        }
    }

    /// Zeitgewinn (negativ) oder -verlust (positiv) pro Runde, in Sekunden.
    public var lapTimeDelta: Double {
        switch self {
        case .conserve: return 0.55
        case .normal: return 0.0
        case .push: return -0.30
        case .attack: return -0.65
        }
    }

    /// Faktor auf den Reifenverschleiß.
    public var wearFactor: Double {
        switch self {
        case .conserve: return 0.80
        case .normal: return 1.00
        case .push: return 1.25
        case .attack: return 1.55
        }
    }

    /// Wie sich die Batterie pro Runde verändert (Anteil von 1.0).
    ///
    /// Unter dem Reglement 2026 kommt rund die Hälfte der Leistung aus dem
    /// Elektroteil — Energie einteilen ist damit eine echte Entscheidung.
    public var batteryPerLap: Double {
        switch self {
        case .conserve: return 0.22
        case .normal: return 0.06
        case .push: return -0.12
        case .attack: return -0.34
        }
    }

    /// Faktor auf die Fehlerwahrscheinlichkeit.
    public var riskFactor: Double {
        switch self {
        case .conserve: return 0.75
        case .normal: return 1.00
        case .push: return 1.30
        case .attack: return 1.85
        }
    }

    /// Braucht diese Stufe Strom aus der Batterie?
    public var needsBattery: Bool {
        return batteryPerLap < 0
    }
}

/// Was ein Mensch an seinem Auto einstellen kann.
///
/// Bewusst klein gehalten: drei Entscheidungen, die im echten Rennen auch wirklich
/// über das Ergebnis bestimmen — Tempo, Boxenstopp und ob man angreift.
public struct DriverInput: Codable, Hashable, Sendable {
    public var pushLevel: PushLevel
    /// Gesetzt = beim nächsten Überfahren der Ziellinie an die Box, mit dieser Mischung.
    public var pitRequest: TyreCompound?
    /// Darf das Auto einen Angriff auf den Vordermann versuchen?
    /// Aus heißt: hinterherfahren und Reifen sparen.
    public var allowOvertake: Bool

    public init(
        pushLevel: PushLevel = .normal,
        pitRequest: TyreCompound? = nil,
        allowOvertake: Bool = true
    ) {
        self.pushLevel = pushLevel
        self.pitRequest = pitRequest
        self.allowOvertake = allowOvertake
    }

    public static let `default` = DriverInput()
}

/// Der Energiespeicher eines Autos.
public enum BatteryModel {
    /// Unter diesem Stand geht kein Angriffsmodus mehr.
    public static let minimumForBoost: Double = 0.05

    /// Was die gewünschte Stufe tatsächlich hergibt.
    ///
    /// Leere Batterie heißt: Der Knopf tut nichts mehr. Genau deshalb ist Einteilen
    /// eine Entscheidung und nicht einfach „immer Attack drücken“.
    public static func effective(_ level: PushLevel, battery: Double) -> PushLevel {
        if level.needsBattery && battery < minimumForBoost {
            return .normal
        }
        return level
    }

    /// Batteriestand nach einer Runde.
    public static func advance(battery: Double, level: PushLevel) -> Double {
        return min(1.0, max(0.0, battery + level.batteryPerLap))
    }
}
