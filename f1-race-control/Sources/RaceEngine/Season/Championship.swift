import Foundation

/// Ein Fahrer in der Meisterschaftstabelle — mit allen Statistiken.
public struct ChampionshipEntry: Codable, Hashable, Sendable, Identifiable {
    public let driverID: String
    public var id: String { driverID }

    public let position: Int
    public let points: Int

    // --- Statistik ---
    /// Bestrittene Rennen.
    public let races: Int
    public let wins: Int
    public let podiums: Int
    public let poles: Int
    public let fastestLaps: Int
    public let dnfs: Int
    public let totalPitStops: Int
    /// Bester Zielplatz der Saison.
    public let bestFinish: Int?
    /// Mittlere Platzierung über alle Rennen.
    public let averageFinish: Double?
    /// Mittlere Rundenzeit über alle Rennen (Rennzeit geteilt durch Runden).
    public let averageLapTime: Double?
    /// Schnellste Einzelrunde der Saison.
    public let bestLapTime: Double?
}

/// Ein Team in der Konstrukteurswertung.
public struct ConstructorEntry: Codable, Hashable, Sendable, Identifiable {
    public let teamID: String
    public var id: String { teamID }

    public let position: Int
    public let points: Int
    public let wins: Int
    public let podiums: Int
    public let poles: Int
    public let dnfs: Int
}

/// Rechnet die Meisterschaft aus den gefahrenen Rennen aus.
///
/// Absichtlich **nicht** mitlaufend hochgezählt, sondern jedes Mal neu aus den
/// Ergebnissen berechnet. Das kostet praktisch nichts, kann nie aus dem Tritt geraten,
/// und man kann die Tabelle testen, ohne ein einziges Rennen zu simulieren.
public enum Championship {

    // MARK: - Fahrerwertung

    public static func drivers(from results: [RoundResult], drivers: [Driver]) -> [ChampionshipEntry] {
        var accumulator: [String: Accumulator] = [:]
        for driver in drivers {
            accumulator[driver.id] = Accumulator()
        }

        for round in results {
            let pole = round.qualifying.poleSitter
            for entry in round.race.entries {
                guard var box = accumulator[entry.driverID] else { continue }
                box.add(entry: entry, isPole: entry.driverID == pole, totalLaps: round.race.totalLaps)
                accumulator[entry.driverID] = box
            }
        }

        // Feste Reihenfolge aus der Fahrerliste, dann sortieren — nie über ein
        // Dictionary iterieren, sonst wäre das Ergebnis von Lauf zu Lauf anders.
        let unsorted: [(Driver, Accumulator)] = drivers.compactMap { driver in
            guard let box = accumulator[driver.id] else { return nil }
            return (driver, box)
        }

        let ranked = unsorted.sorted { lhs, rhs in
            if lhs.1.points != rhs.1.points { return lhs.1.points > rhs.1.points }
            if lhs.1.wins != rhs.1.wins { return lhs.1.wins > rhs.1.wins }
            if lhs.1.podiums != rhs.1.podiums { return lhs.1.podiums > rhs.1.podiums }
            return lhs.0.id < rhs.0.id
        }

        return ranked.enumerated().map { index, pair in
            pair.1.makeEntry(driverID: pair.0.id, position: index + 1)
        }
    }

    // MARK: - Konstrukteurswertung

    public static func constructors(
        from results: [RoundResult],
        drivers: [Driver],
        teams: [Team]
    ) -> [ConstructorEntry] {
        var teamOf: [String: String] = [:]
        for driver in drivers { teamOf[driver.id] = driver.teamID }

        var points: [String: Int] = [:]
        var wins: [String: Int] = [:]
        var podiums: [String: Int] = [:]
        var poles: [String: Int] = [:]
        var dnfs: [String: Int] = [:]
        for team in teams {
            points[team.id] = 0; wins[team.id] = 0; podiums[team.id] = 0
            poles[team.id] = 0; dnfs[team.id] = 0
        }

        for round in results {
            if let pole = round.qualifying.poleSitter, let team = teamOf[pole] {
                poles[team, default: 0] += 1
            }
            for entry in round.race.entries {
                guard let team = teamOf[entry.driverID] else { continue }
                points[team, default: 0] += entry.points
                if entry.status == .retired { dnfs[team, default: 0] += 1 }
                guard entry.status == .finished else { continue }
                if entry.position == 1 { wins[team, default: 0] += 1 }
                if entry.position <= 3 { podiums[team, default: 0] += 1 }
            }
        }

        let ranked = teams.sorted { lhs, rhs in
            let lhsPoints = points[lhs.id] ?? 0
            let rhsPoints = points[rhs.id] ?? 0
            if lhsPoints != rhsPoints { return lhsPoints > rhsPoints }
            let lhsWins = wins[lhs.id] ?? 0
            let rhsWins = wins[rhs.id] ?? 0
            if lhsWins != rhsWins { return lhsWins > rhsWins }
            return lhs.id < rhs.id
        }

        return ranked.enumerated().map { index, team in
            ConstructorEntry(
                teamID: team.id,
                position: index + 1,
                points: points[team.id] ?? 0,
                wins: wins[team.id] ?? 0,
                podiums: podiums[team.id] ?? 0,
                poles: poles[team.id] ?? 0,
                dnfs: dnfs[team.id] ?? 0
            )
        }
    }

    // MARK: - Sammelbehälter

    /// Zählt die Werte eines Fahrers über die Saison zusammen.
    private struct Accumulator {
        var points = 0
        var races = 0
        var wins = 0
        var podiums = 0
        var poles = 0
        var fastestLaps = 0
        var dnfs = 0
        var pitStops = 0
        var bestFinish: Int?
        var finishPositions: [Int] = []
        var lapTimeSum = 0.0
        var lapTimeCount = 0
        var bestLap: Double?

        mutating func add(entry: RaceResultEntry, isPole: Bool, totalLaps: Int) {
            races += 1
            points += entry.points
            pitStops += entry.pitStops
            if isPole { poles += 1 }
            if entry.hasFastestLap { fastestLaps += 1 }

            if let lap = entry.bestLapTime {
                if bestLap == nil || lap < bestLap! { bestLap = lap }
            }

            switch entry.status {
            case .retired:
                dnfs += 1
            case .finished:
                finishPositions.append(entry.position)
                if bestFinish == nil || entry.position < bestFinish! { bestFinish = entry.position }
                if entry.position == 1 { wins += 1 }
                if entry.position <= 3 { podiums += 1 }
                // Mittlere Rundenzeit dieses Rennens: gefahrene Zeit durch Runden.
                if entry.lapsCompleted > 0, entry.rawTime > 0 {
                    lapTimeSum += entry.rawTime / Double(entry.lapsCompleted)
                    lapTimeCount += 1
                }
            default:
                break
            }
        }

        func makeEntry(driverID: String, position: Int) -> ChampionshipEntry {
            let average: Double? = finishPositions.isEmpty
                ? nil
                : Double(finishPositions.reduce(0, +)) / Double(finishPositions.count)
            let averageLap: Double? = lapTimeCount == 0 ? nil : lapTimeSum / Double(lapTimeCount)

            return ChampionshipEntry(
                driverID: driverID,
                position: position,
                points: points,
                races: races,
                wins: wins,
                podiums: podiums,
                poles: poles,
                fastestLaps: fastestLaps,
                dnfs: dnfs,
                totalPitStops: pitStops,
                bestFinish: bestFinish,
                averageFinish: average,
                averageLapTime: averageLap,
                bestLapTime: bestLap
            )
        }
    }
}
