import Foundation

/// Ein Fahrer im Schlussklassement.
public struct RaceResultEntry: Codable, Hashable, Sendable, Identifiable {
    public let driverID: String
    public var id: String { driverID }

    public let position: Int
    public let gridPosition: Int
    public let lapsCompleted: Int
    /// Gefahrene Zeit ohne Strafen.
    public let rawTime: Double
    /// Gewertete Zeit — mit aufgeschlagenen Strafsekunden.
    public let classifiedTime: Double
    public let penaltySeconds: Double
    public let status: DriverStatus
    public let retirementReason: String?
    public let points: Int
    public let pitStops: Int
    public let bestLapTime: Double?
    public let hasFastestLap: Bool
    public let finalCompound: TyreCompound

    /// Positionen gewonnen (positiv) oder verloren.
    public var positionChange: Int {
        return gridPosition - position
    }

    public var isClassified: Bool {
        return status == .finished
    }
}

/// Das Ergebnis eines kompletten Rennens.
public struct RaceResult: Sendable {
    public let circuitName: String
    public let totalLaps: Int
    public let raceDuration: Double
    public let entries: [RaceResultEntry]
    public let fastestLap: FastestLap?

    /// Punkte für die ersten zehn — das aktuelle Formel-1-System.
    public static let pointsTable: [Int] = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
    /// Ein Extrapunkt für die schnellste Runde, aber nur aus den Top 10.
    public static let fastestLapPointCutoff = 10

    public var winner: RaceResultEntry? {
        return entries.first
    }

    public var podium: [RaceResultEntry] {
        return Array(entries.prefix(3))
    }

    public var retirements: [RaceResultEntry] {
        return entries.filter { $0.status == .retired }
    }

    public var totalPitStops: Int {
        return entries.reduce(0) { $0 + $1.pitStops }
    }

    /// Punkte je Team.
    public func constructorPoints(drivers: [Driver]) -> [String: Int] {
        var teamOf: [String: String] = [:]
        for driver in drivers { teamOf[driver.id] = driver.teamID }

        var totals: [String: Int] = [:]
        for entry in entries {
            guard let team = teamOf[entry.driverID] else { continue }
            totals[team, default: 0] += entry.points
        }
        return totals
    }

    /// Klassement aus dem Endstand der Simulation bauen.
    ///
    /// Hier werden zum Schluss die **Zeitstrafen aufgeschlagen** — genau das kann noch
    /// Positionen verschieben. Ein Fahrer, der 2 Sekunden vor dem Nächsten ins Ziel kommt,
    /// aber 5 Sekunden Strafe offen hat, verliert den Platz nachträglich.
    static func build(
        cars: [CarSim],
        configuration: RaceConfiguration,
        fastestLap: FastestLap?,
        raceTime: Double
    ) -> RaceResult {

        let finishers = cars.filter { $0.status == .finished }
        let others = cars.filter { $0.status != .finished }

        // Gewertete Zeit = Fahrzeit + offene Strafen.
        func classified(_ car: CarSim) -> Double {
            return (car.crossingTimes.last ?? raceTime) + car.penaltySeconds
        }

        let rankedFinishers = finishers.sorted { lhs, rhs in
            if lhs.lapsCompleted != rhs.lapsCompleted {
                return lhs.lapsCompleted > rhs.lapsCompleted
            }
            let lhsTime = classified(lhs)
            let rhsTime = classified(rhs)
            if lhsTime != rhsTime { return lhsTime < rhsTime }
            return lhs.driver.id < rhs.driver.id
        }

        let rankedOthers = others.sorted { lhs, rhs in
            if lhs.lapsCompleted != rhs.lapsCompleted {
                return lhs.lapsCompleted > rhs.lapsCompleted
            }
            return lhs.driver.id < rhs.driver.id
        }

        let ordered = rankedFinishers + rankedOthers

        // Bekommt der Fahrer mit der schnellsten Runde seinen Extrapunkt?
        var fastestLapBonusGoesTo: String? = nil
        if let fastest = fastestLap {
            if let index = rankedFinishers.firstIndex(where: { $0.driver.id == fastest.driverID }),
               index < fastestLapPointCutoff {
                fastestLapBonusGoesTo = fastest.driverID
            }
        }

        var entries: [RaceResultEntry] = []
        for (index, car) in ordered.enumerated() {
            let position = index + 1
            var points = 0
            if car.status == .finished, position <= pointsTable.count {
                points = pointsTable[position - 1]
            }
            if car.driver.id == fastestLapBonusGoesTo {
                points += 1
            }

            entries.append(RaceResultEntry(
                driverID: car.driver.id,
                position: position,
                gridPosition: car.gridPosition,
                lapsCompleted: car.lapsCompleted,
                rawTime: car.crossingTimes.last ?? 0,
                classifiedTime: classified(car),
                penaltySeconds: car.penaltySeconds,
                status: car.status,
                retirementReason: car.retirementReason,
                points: points,
                pitStops: car.pitStops,
                bestLapTime: car.bestLapTime,
                hasFastestLap: car.driver.id == fastestLap?.driverID,
                finalCompound: car.tyres.compound
            ))
        }

        return RaceResult(
            circuitName: configuration.circuit.name,
            totalLaps: configuration.laps,
            raceDuration: raceTime,
            entries: entries,
            fastestLap: fastestLap
        )
    }
}
