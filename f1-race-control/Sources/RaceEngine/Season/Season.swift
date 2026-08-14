import Foundation

/// Ein gefahrenes Wochenende: Qualifying und Rennen zusammen.
public struct RoundResult: Codable, Sendable, Identifiable {
    public let round: Int
    public let circuitID: String
    public let qualifying: QualifyingResult
    public let race: RaceResult

    public var id: Int { round }

    public init(round: Int, circuitID: String, qualifying: QualifyingResult, race: RaceResult) {
        self.round = round
        self.circuitID = circuitID
        self.qualifying = qualifying
        self.race = race
    }

    public var winner: String? {
        return race.entries.first { $0.status == .finished }?.driverID
    }

    public var poleSitter: String? {
        return qualifying.poleSitter
    }
}

/// Der komplette Stand einer Saison.
///
/// Enthält absichtlich **nur Ergebnisse**, keine berechnete Tabelle. Die Meisterschaft
/// wird bei Bedarf aus den Ergebnissen ausgerechnet (`Championship`). Damit kann sie
/// nie „auseinanderlaufen“, und man kann sie prüfen, ohne ein Rennen zu simulieren.
public struct Season: Codable, Sendable {
    public var year: Int
    /// Aus diesem Seed leitet sich jedes Wochenende ab. Gleicher Seed = gleiche Saison.
    public var seed: UInt64
    public var calendar: [SeasonRound]
    public var results: [RoundResult]

    public var aiStrength: Double
    public var weatherVariability: Double
    /// Anteil der vollen Renndistanz, z.B. `0.5` für halb so lange Rennen.
    public var raceLengthFactor: Double

    public init(
        year: Int = 2026,
        seed: UInt64 = 2026,
        calendar: [SeasonRound] = SeasonCalendar.year2026,
        results: [RoundResult] = [],
        aiStrength: Double = 0.9,
        weatherVariability: Double = 0.5,
        raceLengthFactor: Double = 1.0
    ) {
        self.year = year
        self.seed = seed
        self.calendar = calendar
        self.results = results
        self.aiStrength = aiStrength
        self.weatherVariability = weatherVariability
        self.raceLengthFactor = raceLengthFactor
    }

    public var completedRounds: Int {
        return results.count
    }

    public var isFinished: Bool {
        return results.count >= calendar.count
    }

    /// Das nächste zu fahrende Wochenende.
    public var nextRound: SeasonRound? {
        guard !isFinished else { return nil }
        return calendar.first { round in
            !results.contains { $0.round == round.round }
        }
    }

    public func result(forRound round: Int) -> RoundResult? {
        return results.first { $0.round == round }
    }

    /// Der Seed dieses Wochenendes.
    ///
    /// Jede Runde bekommt einen eigenen, aus Saison-Seed und Rundennummer gemischten
    /// Wert — sonst würde jedes Rennen der Saison identisch ablaufen.
    public func seed(forRound round: Int) -> UInt64 {
        var z = seed &+ (UInt64(round) &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 33)) &* 0xFF51_AFD7_ED55_8CCD
        z = (z ^ (z >> 33)) &* 0xC4CE_B9FE_1A85_EC53
        return z ^ (z >> 33)
    }
}
