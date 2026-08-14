import XCTest
@testable import RaceEngine

/// Qualifying: Ablauf, Startaufstellung und Reproduzierbarkeit.
final class QualifyingTests: XCTestCase {

    private func runQualifying(
        circuitID: String = "monza",
        seed: UInt64 = 42,
        weather: WeatherConditions = WeatherConditions()
    ) throws -> (QualifyingResult, RaceData) {
        let data = try Fixtures.data()
        let circuit = try Fixtures.circuit(circuitID)
        let result = QualifyingSimulator.run(
            circuit: circuit,
            drivers: data.drivers,
            teams: data.teams,
            weather: weather,
            aiStrength: 0.9,
            seed: seed
        )
        return (result, data)
    }

    // MARK: - Aufbau der Session

    func testEliminationCountsForDifferentFieldSizes() {
        // Der letzte Abschnitt hat immer 10 Fahrer, der Rest wird aufgeteilt.
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 22).q1, 6)
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 22).q2, 6)
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 20).q1, 5)
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 20).q2, 5)
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 24).q1, 7)
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 24).q2, 7)

        // Kleines Feld: niemand scheidet aus.
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 8).q1, 0)
        XCTAssertEqual(QualifyingSimulator.eliminationCounts(fieldSize: 8).q2, 0)
    }

    func testEveryDriverGetsExactlyOneGridSlot() throws {
        let (result, data) = try runQualifying()

        XCTAssertEqual(result.entries.count, data.drivers.count)
        XCTAssertEqual(result.grid.count, data.drivers.count)
        XCTAssertEqual(Set(result.grid).count, data.drivers.count,
                       "Kein Fahrer darf doppelt in der Aufstellung stehen.")
        XCTAssertEqual(result.entries.map { $0.position }, Array(1...data.drivers.count),
                       "Die Startplätze müssen lückenlos 1…n sein.")
    }

    func testSegmentSizesAreCorrect() throws {
        let (result, _) = try runQualifying()

        XCTAssertEqual(result.eliminated(in: .q3).count, QualifyingSimulator.finalSegmentSize,
                       "In Q3 stehen genau 10 Fahrer.")
        XCTAssertEqual(result.eliminated(in: .q2).count, 6)
        XCTAssertEqual(result.eliminated(in: .q1).count, 6)
    }

    func testEliminatedDriversTakeTheBackOfTheGrid() throws {
        let (result, _) = try runQualifying()

        for entry in result.entries {
            switch entry.eliminatedIn {
            case .q3:
                XCTAssertLessThanOrEqual(entry.position, 10)
            case .q2:
                XCTAssertTrue((11...16).contains(entry.position),
                              "In Q2 Ausgeschiedene starten auf 11–16, nicht \(entry.position).")
            case .q1:
                XCTAssertTrue((17...22).contains(entry.position),
                              "In Q1 Ausgeschiedene starten auf 17–22, nicht \(entry.position).")
            }
        }
    }

    func testTimesExistOnlyForSegmentsActuallyDriven() throws {
        let (result, _) = try runQualifying()

        for entry in result.entries {
            XCTAssertNotNil(entry.q1Time, "Jeder fährt Q1.")
            switch entry.eliminatedIn {
            case .q1:
                XCTAssertNil(entry.q2Time)
                XCTAssertNil(entry.q3Time)
            case .q2:
                XCTAssertNotNil(entry.q2Time)
                XCTAssertNil(entry.q3Time)
            case .q3:
                XCTAssertNotNil(entry.q2Time)
                XCTAssertNotNil(entry.q3Time)
            }
        }
    }

    func testQ3OrderMatchesQ3Times() throws {
        let (result, _) = try runQualifying()
        let finalists = result.entries.filter { $0.eliminatedIn == .q3 }

        for index in 1..<finalists.count {
            let previous = try XCTUnwrap(finalists[index - 1].q3Time)
            let current = try XCTUnwrap(finalists[index].q3Time)
            XCTAssertLessThanOrEqual(previous, current,
                                     "Die Startplätze 1–10 folgen den Q3-Zeiten.")
        }
    }

    func testPoleSitterIsTheFastestInQ3() throws {
        let (result, _) = try runQualifying()
        let pole = try XCTUnwrap(result.poleSitter)
        XCTAssertEqual(result.entries.first?.driverID, pole)
        XCTAssertEqual(result.entries.first?.position, 1)

        let fastestQ3 = result.entries.compactMap { $0.q3Time }.min()
        XCTAssertEqual(result.entries.first?.q3Time, fastestQ3)
    }

    func testLapTimesArePlausible() throws {
        let (result, _) = try runQualifying()
        let circuit = try Fixtures.circuit("monza")

        for entry in result.entries {
            let time = try XCTUnwrap(entry.q1Time)
            XCTAssertGreaterThan(time, circuit.baseLapTime * 0.95,
                                 "Niemand fährt schneller als das theoretische Optimum.")
            XCTAssertLessThan(time, circuit.baseLapTime + 8,
                              "Auch der Langsamste liegt nicht acht Sekunden zurück.")
        }
    }

    // MARK: - Reproduzierbarkeit

    func testSameSeedProducesSameGrid() throws {
        let (first, _) = try runQualifying(seed: 1234)
        let (second, _) = try runQualifying(seed: 1234)
        XCTAssertEqual(first.grid, second.grid)
        XCTAssertEqual(first.poleTime, second.poleTime)
    }

    func testDifferentSeedsProduceDifferentGrids() throws {
        let (first, _) = try runQualifying(seed: 1)
        let (second, _) = try runQualifying(seed: 2)
        XCTAssertNotEqual(first.grid, second.grid)
    }

    func testGridVariesAcrossTheSeason() throws {
        // Der eigentliche Zweck des Qualifyings: nicht in jedem Rennen dieselbe
        // Aufstellung. Sonst wäre die Meisterschaft von vornherein entschieden.
        var poles: Set<String> = []
        var grids: Set<[String]> = []
        for round in UInt64(1)...12 {
            let (result, _) = try runQualifying(seed: round &* 7919)
            poles.insert(result.poleSitter ?? "")
            grids.insert(result.grid)
        }
        XCTAssertEqual(grids.count, 12, "Jedes Wochenende muss eine eigene Aufstellung haben.")
        XCTAssertGreaterThan(poles.count, 1, "Die Pole darf nicht immer derselbe holen.")
    }

    // MARK: - Plausibilität

    func testStrongPackagesQualifyAhead() throws {
        // Über viele Sessions gemittelt muss sich Auto und Fahrer durchsetzen.
        var verstappen = 0
        var stroll = 0
        for round in UInt64(1)...15 {
            let (result, _) = try runQualifying(seed: round &* 104_729)
            verstappen += try XCTUnwrap(result.entries.first { $0.driverID == "VER" }).position
            stroll += try XCTUnwrap(result.entries.first { $0.driverID == "STR" }).position
        }
        XCTAssertLessThan(verstappen, stroll,
                          "Das stärkste Paket darf im Mittel nicht hinter dem schwächsten qualifizieren.")
    }

    func testWetQualifyingFavoursRainSpecialists() throws {
        // Im Regen zählt wetPerformance statt pace. Hamilton (wet 96) muss sich
        // gegenüber trockenen Bedingungen relativ verbessern.
        let dry = WeatherConditions(state: .dry, trackWetness: 0)
        let wet = WeatherConditions(state: .heavyRain, trackWetness: 0.9)

        var dryTotal = 0
        var wetTotal = 0
        for round in UInt64(1)...15 {
            let seed = round &* 31_337
            let (dryResult, _) = try runQualifying(seed: seed, weather: dry)
            let (wetResult, _) = try runQualifying(seed: seed, weather: wet)
            dryTotal += try XCTUnwrap(dryResult.entries.first { $0.driverID == "HAM" }).position
            wetTotal += try XCTUnwrap(wetResult.entries.first { $0.driverID == "HAM" }).position
        }
        XCTAssertLessThan(wetTotal, dryTotal,
                          "Ein Regenspezialist muss im Nassen im Mittel weiter vorn stehen.")
    }

    func testWetQualifyingIsSlower() throws {
        let (dry, _) = try runQualifying(weather: WeatherConditions(state: .dry, trackWetness: 0))
        let (wet, _) = try runQualifying(
            weather: WeatherConditions(state: .heavyRain, trackWetness: 0.9))

        let dryPole = try XCTUnwrap(dry.poleTime)
        let wetPole = try XCTUnwrap(wet.poleTime)
        XCTAssertGreaterThan(wetPole, dryPole * 1.1,
                             "Eine Regenrunde muss deutlich langsamer sein.")
    }

    func testTrackGetsFasterThroughTheSession() {
        XCTAssertGreaterThan(QualifyingSegment.q1.trackEvolution,
                             QualifyingSegment.q2.trackEvolution)
        XCTAssertGreaterThan(QualifyingSegment.q2.trackEvolution,
                             QualifyingSegment.q3.trackEvolution)
    }

    func testGridFeedsStraightIntoTheRace() throws {
        let (qualifying, data) = try runQualifying()
        let configuration = RaceConfiguration(
            circuit: try Fixtures.circuit(),
            drivers: data.drivers,
            teams: data.teams,
            laps: 5,
            startingGrid: qualifying.grid,
            seed: 1
        )
        let engine = RaceEngine(configuration: configuration)

        // Zu Beginn entspricht die Reihenfolge der Startaufstellung.
        let startOrder = engine.snapshot().standings
            .sorted { $0.gridPosition < $1.gridPosition }
            .map { $0.driverID }
        XCTAssertEqual(startOrder, qualifying.grid)
    }
}
