import XCTest
@testable import RaceEngine

/// Gemeinsame Bausteine für die Tests.
enum Fixtures {

    /// Die echten Stammdaten aus dem Paket.
    static func data() throws -> RaceData {
        return try DataLoader.loadAll()
    }

    static func circuit(_ id: String = "monza") throws -> Circuit {
        let all = try DataLoader.loadCircuits()
        guard let found = all.first(where: { $0.id == id }) else {
            throw XCTSkip("Strecke '\(id)' fehlt in den Stammdaten.")
        }
        return found
    }

    /// Eine ganz normale Rennkonfiguration.
    static func configuration(
        circuitID: String = "monza",
        laps: Int = 12,
        seed: UInt64 = 42,
        weather: WeatherState = .dry,
        aiStrength: Double = 0.9,
        weatherVariability: Double = 0.0
    ) throws -> RaceConfiguration {
        let data = try Self.data()
        return RaceConfiguration(
            circuit: try circuit(circuitID),
            drivers: data.drivers,
            teams: data.teams,
            laps: laps,
            startingWeather: weather,
            aiStrength: aiStrength,
            weatherVariability: weatherVariability,
            seed: seed
        )
    }

    /// Ein Testfahrer mit frei wählbaren Werten.
    static func driver(
        id: String = "TST",
        pace: Double = 90,
        consistency: Double = 90,
        aggression: Double = 75,
        overtaking: Double = 85,
        defending: Double = 85,
        wet: Double = 85,
        tyreManagement: Double = 85,
        teamID: String = "testteam"
    ) -> Driver {
        return Driver(
            id: id, name: "Test \(id)", number: 99, teamID: teamID,
            pace: pace, consistency: consistency, aggression: aggression,
            overtaking: overtaking, defending: defending,
            wetPerformance: wet, tyreManagement: tyreManagement
        )
    }

    static func team(
        id: String = "testteam",
        carPerformance: Double = 90,
        reliability: Double = 95,
        pitCrewSkill: Double = 85
    ) -> Team {
        return Team(
            id: id, name: "Test Team", colorHex: "#FFFFFF",
            carPerformance: carPerformance, reliability: reliability, pitCrewSkill: pitCrewSkill
        )
    }

    /// Ein Zwischenfall mit genau den Eigenschaften, die ein Test braucht.
    static func incident(
        lap: Int = 5,
        drivers: [String] = ["VER"],
        kind: IncidentKind = .crash,
        severity: IncidentSeverity = .high,
        sector: Int = 1,
        blocksTrack: Bool = false,
        carStopped: Bool = true
    ) -> Incident {
        return Incident(
            lap: lap, driverIDs: drivers, kind: kind, severity: severity,
            sector: sector, blocksTrack: blocksTrack, carStopped: carStopped
        )
    }
}

extension RaceEngine {
    /// Das Rennen um `seconds` Sekunden weiterlaufen lassen, in feinen Schritten.
    func run(seconds: Double, step: Double = 0.25) {
        var elapsed = 0.0
        while elapsed < seconds && !isFinished {
            advance(step)
            elapsed += step
        }
    }

    /// Weiterlaufen, bis eine Bedingung eintritt (oder die Zeit abgelaufen ist).
    /// - Returns: `true`, wenn die Bedingung erreicht wurde.
    @discardableResult
    func run(until condition: () -> Bool, maxSeconds: Double = 4000, step: Double = 0.25) -> Bool {
        var elapsed = 0.0
        while elapsed < maxSeconds && !isFinished {
            if condition() { return true }
            advance(step)
            elapsed += step
        }
        return condition()
    }
}
