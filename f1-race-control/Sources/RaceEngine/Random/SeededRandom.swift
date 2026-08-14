import Foundation

/// Zufallszahlen, die sich wiederholen lassen.
///
/// Warum eigener Generator statt `Double.random`? Weil ein Rennen sonst bei jedem
/// Start anders ausgeht — und dann kann man weder testen noch ein Rennen nochmal
/// genau so nachfahren. Mit demselben Seed kommt hier **immer** dieselbe Zahlenfolge.
///
/// Verfahren: SplitMix64. Klein, schnell, gut durchmischt.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Kommazahl in `[0, 1)`.
    public mutating func unit() -> Double {
        // 53 Bit sind genau so viele, wie ein Double sauber darstellen kann.
        return Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Kommazahl zwischen `lower` und `upper`.
    public mutating func double(in range: ClosedRange<Double>) -> Double {
        return range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// Ganzzahl zwischen `lower` und `upper` (beide eingeschlossen).
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(span))
    }

    /// `true` mit der Wahrscheinlichkeit `probability` (0…1).
    public mutating func chance(_ probability: Double) -> Bool {
        if probability <= 0 { return false }
        if probability >= 1 { return true }
        return unit() < probability
    }

    /// Normalverteilte Zufallszahl (Box-Muller).
    ///
    /// Gebraucht für Rundenzeit-Schwankungen: die meisten Runden liegen nah beieinander,
    /// Ausreißer nach oben und unten sind selten — genau das macht eine Glockenkurve.
    public mutating func gaussian(mean: Double = 0, standardDeviation: Double = 1) -> Double {
        let u1 = Swift.max(unit(), 1e-12)   // log(0) wäre -unendlich
        let u2 = unit()
        let magnitude = (-2.0 * Foundation.log(u1)).squareRoot()
        return mean + standardDeviation * magnitude * Foundation.cos(2.0 * Double.pi * u2)
    }

    /// Ein zufälliges Element aus einer Liste.
    public mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[int(in: 0...(items.count - 1))]
    }
}

/// Die Teilsysteme, die würfeln dürfen.
///
/// Jedes bekommt seinen **eigenen** Zufallsstrom. Der Grund: würden sich alle aus
/// einem Topf bedienen, würde ein später ergänztes System (z.B. Boxenstopp-Patzer)
/// die Zahlenfolge aller anderen verschieben — und plötzlich fahren alle Tests
/// ein völlig anderes Rennen, obwohl sich an ihnen nichts geändert hat.
public enum RandomStream: UInt64, CaseIterable, Sendable {
    case lapTime = 1
    case weather = 2
    case incidents = 3
    case overtaking = 4
    case pitStops = 5
    case reliability = 6
    case raceControl = 7
    case qualifying = 8
}

/// Verteilt aus einem Haupt-Seed je einen eigenen Generator pro Teilsystem **und Auto**.
///
/// Warum auch pro Auto? Weil sonst die Reihenfolge, in der die Autos ihre Runde beenden,
/// darüber entscheidet, wer welche Zufallszahl bekommt. Diese Reihenfolge hängt aber an
/// der Schrittweite der Simulation — und damit würde dasselbe Rennen anders ausgehen,
/// je nachdem wie fein gerechnet wird. Mit einem eigenen Strom pro Auto zieht jeder
/// Fahrer immer seine eigenen Zahlen, egal was die anderen gerade tun.
public struct RandomSource {
    public let masterSeed: UInt64
    private var streams: [UInt64: SeededRandom]

    public init(masterSeed: UInt64) {
        self.masterSeed = masterSeed
        self.streams = [:]
    }

    /// Ein Schlüssel aus Teilsystem und Auto-Nummer.
    private static func key(_ stream: RandomStream, _ actor: Int) -> UInt64 {
        return stream.rawValue &* 1_000 &+ UInt64(actor &+ 1)
    }

    /// Vermischt Haupt-Seed und Teilsystem-Nummer zu einem eigenen Start-Seed.
    private static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var z = a &+ (b &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 33)) &* 0xFF51_AFD7_ED55_8CCD
        z = (z ^ (z >> 33)) &* 0xC4CE_B9FE_1A85_EC53
        return z ^ (z >> 33)
    }

    /// Zugriff auf den Generator eines Teilsystems für ein bestimmtes Auto.
    ///
    /// - Parameter actor: Die feste Nummer des Autos (Index in der Startaufstellung).
    ///   `0` steht für Dinge, die keinem Auto gehören — zum Beispiel das Wetter.
    ///
    /// `inout`, damit der Fortschritt des Generators erhalten bleibt.
    public mutating func with<T>(
        _ stream: RandomStream,
        actor: Int = 0,
        _ body: (inout SeededRandom) -> T
    ) -> T {
        let key = RandomSource.key(stream, actor)
        var generator = streams[key] ?? SeededRandom(seed: RandomSource.mix(masterSeed, key))
        let result = body(&generator)
        streams[key] = generator
        return result
    }
}
