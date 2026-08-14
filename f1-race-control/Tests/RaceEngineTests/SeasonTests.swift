import XCTest
@testable import RaceEngine

/// Kalender, Saisonablauf, Meisterschaft und Speichern.
final class SeasonTests: XCTestCase {

    /// Kurze Rennen, damit eine ganze Saison in Sekunden durchläuft.
    private func makeSeason(seed: UInt64 = 2026, lengthFactor: Double = 0.12) -> Season {
        return Season(seed: seed, raceLengthFactor: lengthFactor)
    }

    // MARK: - Kalender

    func testCalendarHasTwentyFourRounds() {
        XCTAssertEqual(SeasonCalendar.year2026.count, 24)
        XCTAssertEqual(SeasonCalendar.year2026.map { $0.round }, Array(1...24),
                       "Die Runden müssen lückenlos von 1 bis 24 durchnummeriert sein.")
    }

    func testEveryCalendarCircuitExists() throws {
        let data = try Fixtures.data()
        for round in SeasonCalendar.year2026 {
            XCTAssertNotNil(data.circuit(id: round.circuitID),
                            "Runde \(round.round) verweist auf '\(round.circuitID)', das es nicht gibt.")
            XCTAssertFalse(round.name.isEmpty)
        }
    }

    func testNoCircuitAppearsTwice() {
        let ids = SeasonCalendar.year2026.map { $0.circuitID }
        XCTAssertEqual(Set(ids).count, ids.count, "Keine Strecke darf doppelt im Kalender stehen.")
    }

    // MARK: - Saisonablauf

    func testFreshSeasonStartsAtRoundOne() {
        let season = makeSeason()
        XCTAssertEqual(season.completedRounds, 0)
        XCTAssertFalse(season.isFinished)
        XCTAssertEqual(season.nextRound?.round, 1)
        XCTAssertEqual(season.nextRound?.circuitID, "melbourne")
    }

    func testEachWeekendAdvancesExactlyOneRound() throws {
        let data = try Fixtures.data()
        var season = makeSeason()

        for expected in 1...3 {
            let result = try SeasonEngine.simulateNextWeekend(season: &season, data: data)
            XCTAssertEqual(result.round, expected)
            XCTAssertEqual(season.completedRounds, expected)
            XCTAssertEqual(season.nextRound?.round, expected + 1)
        }
    }

    func testWeekendProducesQualifyingAndRace() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        let result = try SeasonEngine.simulateNextWeekend(season: &season, data: data)

        XCTAssertEqual(result.qualifying.entries.count, data.drivers.count)
        XCTAssertNotNil(result.poleSitter)
        XCTAssertNotNil(result.winner)
        XCTAssertEqual(result.race.entries.count, data.drivers.count)
    }

    func testRaceStartsFromTheQualifyingGrid() throws {
        let data = try Fixtures.data()
        let season = makeSeason()
        let setup = try SeasonEngine.prepareNextWeekend(season: season, data: data)
        XCTAssertEqual(setup.raceConfiguration.startingGrid, setup.qualifying.grid,
                       "Das Rennen muss genau in der Qualifying-Reihenfolge starten.")
    }

    func testFinishedSeasonRefusesAnotherRace() throws {
        let data = try Fixtures.data()
        var season = Season(seed: 5, calendar: Array(SeasonCalendar.year2026.prefix(2)),
                            raceLengthFactor: 0.12)

        try SeasonEngine.simulateRemainingSeason(season: &season, data: data)
        XCTAssertTrue(season.isFinished)
        XCTAssertEqual(season.completedRounds, 2)
        XCTAssertNil(season.nextRound)

        XCTAssertThrowsError(try SeasonEngine.simulateNextWeekend(season: &season, data: data)) { error in
            XCTAssertEqual("\(error)", "\(SeasonError.seasonFinished)")
        }
        XCTAssertEqual(season.completedRounds, 2, "Nach dem Finale kommt nichts mehr dazu.")
    }

    func testSameSeedProducesSameSeason() throws {
        let data = try Fixtures.data()
        var first = makeSeason(seed: 77)
        var second = makeSeason(seed: 77)
        for _ in 0..<3 {
            try SeasonEngine.simulateNextWeekend(season: &first, data: data)
            try SeasonEngine.simulateNextWeekend(season: &second, data: data)
        }
        XCTAssertEqual(first.results.map { $0.winner }, second.results.map { $0.winner })
        XCTAssertEqual(first.results.map { $0.poleSitter }, second.results.map { $0.poleSitter })
    }

    func testEachRoundIsADifferentRace() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        for _ in 0..<5 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }
        let grids = season.results.map { $0.qualifying.grid }
        XCTAssertEqual(Set(grids).count, grids.count,
                       "Jede Runde braucht eine eigene Startaufstellung.")
    }

    // MARK: - Meisterschaft

    func testEmptySeasonGivesZeroedTable() throws {
        let data = try Fixtures.data()
        let table = Championship.drivers(from: [], drivers: data.drivers)

        XCTAssertEqual(table.count, data.drivers.count)
        XCTAssertTrue(table.allSatisfy { $0.points == 0 && $0.races == 0 })
        XCTAssertEqual(table.map { $0.position }, Array(1...data.drivers.count))
        XCTAssertNil(table[0].averageFinish)
    }

    func testChampionshipPointsMatchTheSumOfRaces() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        for _ in 0..<5 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }

        let table = Championship.drivers(from: season.results, drivers: data.drivers)

        for entry in table {
            let expected = season.results.reduce(0) { total, round in
                total + (round.race.entries.first { $0.driverID == entry.driverID }?.points ?? 0)
            }
            XCTAssertEqual(entry.points, expected,
                           "\(entry.driverID): Tabelle sagt \(entry.points), Rennen ergeben \(expected).")
        }
    }

    func testTableIsSortedByPointsThenWins() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        for _ in 0..<6 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }

        let table = Championship.drivers(from: season.results, drivers: data.drivers)
        for index in 1..<table.count {
            let above = table[index - 1]
            let below = table[index]
            XCTAssertGreaterThanOrEqual(above.points, below.points)
            if above.points == below.points {
                XCTAssertGreaterThanOrEqual(above.wins, below.wins,
                                            "Bei Punktgleichheit entscheiden die Siege.")
            }
        }
        XCTAssertEqual(table.map { $0.position }, Array(1...table.count))
    }

    func testWinsPodiumsPolesAndDnfsAreCountedCorrectly() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        for _ in 0..<6 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }
        let table = Championship.drivers(from: season.results, drivers: data.drivers)

        // Gegenrechnung direkt aus den Ergebnissen.
        for entry in table {
            var wins = 0, podiums = 0, poles = 0, dnfs = 0, races = 0
            for round in season.results {
                if round.poleSitter == entry.driverID { poles += 1 }
                guard let line = round.race.entries.first(where: { $0.driverID == entry.driverID })
                else { continue }
                races += 1
                if line.status == .retired { dnfs += 1 }
                if line.status == .finished && line.position == 1 { wins += 1 }
                if line.status == .finished && line.position <= 3 { podiums += 1 }
            }
            XCTAssertEqual(entry.wins, wins, "\(entry.driverID) Siege")
            XCTAssertEqual(entry.podiums, podiums, "\(entry.driverID) Podien")
            XCTAssertEqual(entry.poles, poles, "\(entry.driverID) Poles")
            XCTAssertEqual(entry.dnfs, dnfs, "\(entry.driverID) Ausfälle")
            XCTAssertEqual(entry.races, races, "\(entry.driverID) Rennen")
        }

        // Pro Rennen genau ein Sieger und eine Pole.
        XCTAssertEqual(table.reduce(0) { $0 + $1.wins }, season.results.count)
        XCTAssertEqual(table.reduce(0) { $0 + $1.poles }, season.results.count)
    }

    func testConstructorPointsAreTheSumOfBothDrivers() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        for _ in 0..<5 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }

        let driverTable = Championship.drivers(from: season.results, drivers: data.drivers)
        let teamTable = Championship.constructors(
            from: season.results, drivers: data.drivers, teams: data.teams)

        XCTAssertEqual(teamTable.count, data.teams.count)

        for team in teamTable {
            let expected = data.drivers
                .filter { $0.teamID == team.teamID }
                .compactMap { driver in driverTable.first { $0.driverID == driver.id }?.points }
                .reduce(0, +)
            XCTAssertEqual(team.points, expected, "\(team.teamID)")
        }

        XCTAssertEqual(teamTable.reduce(0) { $0 + $1.points },
                       driverTable.reduce(0) { $0 + $1.points })
    }

    func testStatisticsArePlausible() throws {
        let data = try Fixtures.data()
        var season = makeSeason()
        for _ in 0..<6 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }
        let table = Championship.drivers(from: season.results, drivers: data.drivers)

        for entry in table where entry.races > 0 {
            if let average = entry.averageFinish {
                XCTAssertGreaterThanOrEqual(average, 1)
                XCTAssertLessThanOrEqual(average, Double(data.drivers.count))
            }
            if let lap = entry.averageLapTime {
                XCTAssertGreaterThan(lap, 40, "Eine mittlere Rundenzeit unter 40 s ist unmöglich.")
                XCTAssertLessThan(lap, 400)
            }
            if let best = entry.bestFinish {
                XCTAssertTrue((1...data.drivers.count).contains(best))
            }
            XCTAssertGreaterThanOrEqual(entry.totalPitStops, 0)
            XCTAssertLessThanOrEqual(entry.wins, entry.podiums)
        }
    }

    // MARK: - Speichern und Laden

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("f1-season-test-\(UUID().uuidString)")
        return url
    }

    func testSaveAndLoadRoundTrip() throws {
        let data = try Fixtures.data()
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        var season = makeSeason(seed: 99)
        for _ in 0..<3 {
            try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        }

        try SeasonStore.save(season, in: folder)
        XCTAssertTrue(SeasonStore.exists(in: folder))

        let loaded = try XCTUnwrap(SeasonStore.load(in: folder))
        XCTAssertEqual(loaded.seed, season.seed)
        XCTAssertEqual(loaded.year, season.year)
        XCTAssertEqual(loaded.completedRounds, season.completedRounds)
        XCTAssertEqual(loaded.calendar.map { $0.circuitID }, season.calendar.map { $0.circuitID })
        XCTAssertEqual(loaded.results.map { $0.winner }, season.results.map { $0.winner })
        XCTAssertEqual(loaded.results.map { $0.poleSitter }, season.results.map { $0.poleSitter })

        // Und die Tabelle stimmt nach dem Laden noch.
        let before = Championship.drivers(from: season.results, drivers: data.drivers)
        let after = Championship.drivers(from: loaded.results, drivers: data.drivers)
        XCTAssertEqual(before.map { $0.driverID }, after.map { $0.driverID })
        XCTAssertEqual(before.map { $0.points }, after.map { $0.points })
    }

    func testLoadingWithoutSavedSeasonReturnsNil() throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertFalse(SeasonStore.exists(in: folder))
        XCTAssertNil(try SeasonStore.load(in: folder))
    }

    func testSavedSeasonCanBeContinued() throws {
        let data = try Fixtures.data()
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        var season = makeSeason(seed: 4242)
        try SeasonEngine.simulateNextWeekend(season: &season, data: data)
        try SeasonStore.save(season, in: folder)

        // Wie nach einem Neustart der App: laden und weiterfahren.
        var reloaded = try XCTUnwrap(SeasonStore.load(in: folder))
        try SeasonEngine.simulateNextWeekend(season: &reloaded, data: data)

        XCTAssertEqual(reloaded.completedRounds, 2)
        XCTAssertEqual(reloaded.results[0].winner, season.results[0].winner,
                       "Das erste Rennen darf sich durch das Weiterfahren nicht ändern.")
    }

    func testDeleteRemovesTheSeason() throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try SeasonStore.save(makeSeason(), in: folder)
        XCTAssertTrue(SeasonStore.exists(in: folder))
        try SeasonStore.delete(in: folder)
        XCTAssertFalse(SeasonStore.exists(in: folder))
    }

    // MARK: - Ganze Saison

    func testFullSeasonProducesAChampion() throws {
        let data = try Fixtures.data()
        var season = makeSeason(seed: 2026, lengthFactor: 0.10)

        try SeasonEngine.simulateRemainingSeason(season: &season, data: data)

        XCTAssertTrue(season.isFinished)
        XCTAssertEqual(season.completedRounds, 24)

        let table = Championship.drivers(from: season.results, drivers: data.drivers)
        let champion = try XCTUnwrap(table.first)
        XCTAssertGreaterThan(champion.points, 0, "Der Meister muss Punkte haben.")
        XCTAssertEqual(table.reduce(0) { $0 + $1.wins }, 24)

        // Die Poles dürfen nicht alle an einen gehen — sonst stimmt am Qualifying etwas nicht.
        let polesitters = Set(season.results.compactMap { $0.poleSitter })
        XCTAssertGreaterThan(polesitters.count, 2,
                             "Über 24 Rennen sollten mehrere Fahrer auf der Pole stehen.")

        // Und es sollten mehrere verschiedene Sieger dabei sein.
        let winners = Set(season.results.compactMap { $0.winner })
        XCTAssertGreaterThan(winners.count, 1)
    }
}
