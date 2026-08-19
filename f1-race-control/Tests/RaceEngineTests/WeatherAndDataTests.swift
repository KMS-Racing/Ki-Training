import XCTest
@testable import RaceEngine

/// Wetter, Stammdaten und die Streckenkarte.
final class WeatherAndDataTests: XCTestCase {

    // MARK: - Wetter

    func testOnlyLegalWeatherTransitions() throws {
        let circuit = try Fixtures.circuit("spa")
        var model = WeatherModel(circuit: circuit, startingWeather: .dry, variability: 1.0)
        var random = SeededRandom(seed: 1)
        var previous = model.conditions.state

        for _ in 0..<20_000 {
            if let next = model.update(deltaTime: 1.0, random: &random) {
                XCTAssertTrue(previous.allowedTransitions.contains(next),
                              "Übergang \(previous) → \(next) ist nicht erlaubt.")
                previous = next
            }
        }
    }

    func testNeverJumpsFromDryToHeavyRain() throws {
        let circuit = try Fixtures.circuit("spa")
        var model = WeatherModel(circuit: circuit, startingWeather: .dry, variability: 1.0)
        var random = SeededRandom(seed: 9)
        var previous = model.conditions.state

        for _ in 0..<20_000 {
            if let next = model.update(deltaTime: 1.0, random: &random) {
                if previous == .dry {
                    XCTAssertNotEqual(next, .heavyRain, "Aus heiterem Himmel kommt kein Wolkenbruch.")
                    XCTAssertNotEqual(next, .lightRain)
                }
                previous = next
            }
        }
    }

    func testWetnessStaysInBounds() throws {
        let circuit = try Fixtures.circuit("spa")
        var model = WeatherModel(circuit: circuit, startingWeather: .cloudy, variability: 1.0)
        var random = SeededRandom(seed: 4)

        for _ in 0..<20_000 {
            _ = model.update(deltaTime: 1.0, random: &random)
            let wetness = model.conditions.trackWetness
            XCTAssertGreaterThanOrEqual(wetness, 0)
            XCTAssertLessThanOrEqual(wetness, 1)
            XCTAssertFalse(wetness.isNaN)
        }
    }

    func testTrackLagsBehindTheSky() throws {
        let circuit = try Fixtures.circuit("spa")
        var model = WeatherModel(circuit: circuit, startingWeather: .heavyRain, variability: 0)
        var random = SeededRandom(seed: 1)

        // Bei Starkregen läuft die Strecke voll.
        for _ in 0..<300 { _ = model.update(deltaTime: 1.0, random: &random) }
        XCTAssertGreaterThan(model.conditions.trackWetness, 0.8)

        // Jetzt trocknet es ab — aber eben nicht sofort.
        var drying = WeatherModel(circuit: circuit, startingWeather: .drying, variability: 0)
        drying.forceWetnessForTesting(0.9)
        for _ in 0..<60 { _ = drying.update(deltaTime: 1.0, random: &random) }
        XCTAssertGreaterThan(drying.conditions.trackWetness, 0.5,
                             "Eine Minute nach dem Regen ist die Strecke noch nass.")
    }

    func testSoakingIsFasterThanDrying() throws {
        let circuit = try Fixtures.circuit("spa")
        var random = SeededRandom(seed: 1)

        var soaking = WeatherModel(circuit: circuit, startingWeather: .heavyRain, variability: 0)
        soaking.forceWetnessForTesting(0.0)
        var soakSeconds = 0
        while soaking.conditions.trackWetness < 0.8 && soakSeconds < 5000 {
            _ = soaking.update(deltaTime: 1.0, random: &random)
            soakSeconds += 1
        }

        var drying = WeatherModel(circuit: circuit, startingWeather: .dry, variability: 0)
        drying.forceWetnessForTesting(0.8)
        var drySeconds = 0
        while drying.conditions.trackWetness > 0.0 && drySeconds < 5000 {
            _ = drying.update(deltaTime: 1.0, random: &random)
            drySeconds += 1
        }

        XCTAssertGreaterThan(drySeconds, soakSeconds * 2,
                             "Abtrocknen dauert deutlich länger als Nasswerden.")
    }

    func testWetTrackIsMoreDangerous() throws {
        let circuit = try Fixtures.circuit("spa")
        let dry = WeatherModel(circuit: circuit, startingWeather: .dry, variability: 0)
        let wet = WeatherModel(circuit: circuit, startingWeather: .heavyRain, variability: 0)
        XCTAssertGreaterThan(wet.incidentFactor, dry.incidentFactor)
    }

    func testWetRaceIsSlowerThanDryRace() throws {
        let dry = RaceEngine(configuration: try Fixtures.configuration(
            circuitID: "spa", laps: 8, seed: 21, weather: .dry, weatherVariability: 0))
        let wet = RaceEngine(configuration: try Fixtures.configuration(
            circuitID: "spa", laps: 8, seed: 21, weather: .heavyRain, weatherVariability: 0))
        dry.runToCompletion()
        wet.runToCompletion()

        let dryWinner = try XCTUnwrap(dry.result()?.winner)
        let wetWinner = try XCTUnwrap(wet.result()?.winner)
        XCTAssertGreaterThan(wetWinner.classifiedTime, dryWinner.classifiedTime * 1.1,
                             "Ein Regenrennen dauert spürbar länger.")
    }

    // MARK: - Stammdaten

    func testDriversAndTeamsLoad() throws {
        let data = try Fixtures.data()
        XCTAssertEqual(data.drivers.count, 22, "Das Feld 2026 hat 22 Autos.")
        XCTAssertEqual(data.teams.count, 11, "2026 fahren 11 Teams.")
        XCTAssertGreaterThanOrEqual(data.circuits.count, 6)
    }

    func testEveryDriverBelongsToAKnownTeam() throws {
        let data = try Fixtures.data()
        let teamIDs = Set(data.teams.map { $0.id })
        for driver in data.drivers {
            XCTAssertTrue(teamIDs.contains(driver.teamID),
                          "\(driver.id) gehört zu Team '\(driver.teamID)', das es nicht gibt.")
        }
    }

    func testEveryTeamHasTwoDrivers() throws {
        let data = try Fixtures.data()
        for team in data.teams {
            let count = data.drivers.filter { $0.teamID == team.id }.count
            XCTAssertEqual(count, 2, "\(team.name) muss genau zwei Fahrer haben.")
        }
    }

    func testCarNumbersAreUnique() throws {
        let data = try Fixtures.data()
        let numbers = data.drivers.map { $0.number }
        XCTAssertEqual(Set(numbers).count, numbers.count, "Startnummern müssen eindeutig sein.")
    }

    func testRatingsAreInRange() throws {
        let data = try Fixtures.data()
        for driver in data.drivers {
            for (label, value) in [
                ("pace", driver.pace), ("consistency", driver.consistency),
                ("aggression", driver.aggression), ("overtaking", driver.overtaking),
                ("defending", driver.defending), ("wet", driver.wetPerformance),
                ("tyres", driver.tyreManagement),
            ] {
                XCTAssertTrue((0...100).contains(value),
                              "\(driver.id).\(label) = \(value) liegt außerhalb 0…100.")
            }
        }
    }

    // MARK: - Streckenkarte

    func testCircuitsAreWellFormed() throws {
        for circuit in try DataLoader.loadCircuits() {
            XCTAssertGreaterThan(circuit.layout.count, 100, "\(circuit.id) braucht eine feine Streckenlinie.")
            XCTAssertEqual(circuit.sectorSplits.count, 2, "Drei Sektoren = zwei Grenzen.")
            XCTAssertGreaterThan(circuit.baseLapTime, 30)
            XCTAssertGreaterThan(circuit.defaultLaps, 10)
            XCTAssertTrue((0...1).contains(circuit.overtakingDifficulty))

            for point in circuit.layout {
                XCTAssertTrue((0...1).contains(point.x), "\(circuit.id): x außerhalb 0…1")
                XCTAssertTrue((0...1).contains(point.y), "\(circuit.id): y außerhalb 0…1")
            }
        }
    }

    /// Keine Strecke darf durch sich selbst hindurchlaufen.
    ///
    /// Das ist nicht bloß Kosmetik. Die Engine setzt die Autos über den
    /// Rundenfortschritt auf die Linie; kreuzt die Linie sich, stehen zwei Autos an
    /// derselben Stelle, die auf der Strecke eine halbe Runde auseinander sind — und
    /// wer zuschaut, sieht einen Unfall, den es nicht gibt.
    ///
    /// Der Test kam, nachdem Silverstone sich in der ersten Fassung dreimal selbst
    /// geschnitten hatte. Aufgefallen ist das erst beim Hinsehen, nicht beim Rechnen.
    func testCircuitsDoNotCrossThemselves() throws {
        for circuit in try DataLoader.loadCircuits() {
            let points = circuit.layout
            let count = points.count
            var crossings = 0

            for i in 0..<count {
                let a1 = points[i]
                let a2 = points[(i + 1) % count]
                // `stride` statt `(i + 2)..<count`: Beim letzten Segment wäre die
                // untere Grenze größer als die obere, und ein Range stürzt dann ab.
                for j in stride(from: i + 2, to: count, by: 1) {
                    // Erstes und letztes Segment hängen zusammen — kein Schnitt.
                    if i == 0 && j == count - 1 { continue }
                    let b1 = points[j]
                    let b2 = points[(j + 1) % count]
                    if Self.segmentsCross(a1, a2, b1, b2) { crossings += 1 }
                }
            }

            XCTAssertEqual(crossings, 0,
                           "\(circuit.id): Die Streckenlinie kreuzt sich \(crossings)-mal.")
        }
    }

    /// Die Strecken müssen unterschiedliche Proportionen haben.
    ///
    /// Vorher wurde jeder Umriss getrennt in x und y auf 0…1 gestreckt. Dadurch hatten
    /// alle 24 dasselbe Seitenverhältnis, und die Karten waren nicht auseinanderzuhalten.
    /// Jetzt skalieren beide Achsen mit demselben Faktor — Montreal ist eine lange,
    /// schmale Insel, Monza ist hoch und schmal, und das sieht man auch.
    func testCircuitsKeepTheirProportions() throws {
        let circuits = try DataLoader.loadCircuits()

        func aspect(_ id: String) throws -> Double {
            let circuit = try XCTUnwrap(circuits.first { $0.id == id }, "\(id) fehlt.")
            let xs = circuit.layout.map(\.x)
            let ys = circuit.layout.map(\.y)
            let width = xs.max()! - xs.min()!
            let height = ys.max()! - ys.min()!
            return width / height
        }

        XCTAssertGreaterThan(try aspect("montreal"), 3.0,
                             "Montreal ist eine lange, schmale Insel.")
        XCTAssertGreaterThan(try aspect("jeddah"), 3.0,
                             "Jeddah ist sehr lang und sehr schmal.")
        XCTAssertLessThan(try aspect("monza"), 0.8,
                          "Monza ist höher als breit.")

        // Und die Bandbreite insgesamt: Wären alle gleich gestreckt, läge hier 1.
        let alle = try circuits.map { try aspect($0.id) }
        XCTAssertGreaterThan(alle.max()! / alle.min()!, 5.0,
                             "Die Strecken haben zu ähnliche Proportionen.")
    }

    /// Schneiden sich die Strecken a1→a2 und b1→b2 in ihrem Inneren?
    ///
    /// Berührungen genau an den Endpunkten zählen nicht — benachbarte Segmente einer
    /// Linie teilen sich ja immer einen Punkt.
    private static func segmentsCross(_ a1: TrackPoint, _ a2: TrackPoint,
                                      _ b1: TrackPoint, _ b2: TrackPoint) -> Bool {
        let d1x = a2.x - a1.x, d1y = a2.y - a1.y
        let d2x = b2.x - b1.x, d2y = b2.y - b1.y
        let denominator = d1x * d2y - d1y * d2x
        guard abs(denominator) > 1e-12 else { return false }   // parallel

        let t = ((b1.x - a1.x) * d2y - (b1.y - a1.y) * d2x) / denominator
        let u = ((b1.x - a1.x) * d1y - (b1.y - a1.y) * d1x) / denominator
        return t > 1e-9 && t < 1 - 1e-9 && u > 1e-9 && u < 1 - 1e-9
    }

    func testTrackPositionIsContinuousAndClosed() throws {
        let circuit = try Fixtures.circuit("monza")
        let start = circuit.position(at: 0)
        let end = circuit.position(at: 1.0)
        XCTAssertEqual(start.x, end.x, accuracy: 0.0001, "Die Runde muss sich schließen.")
        XCTAssertEqual(start.y, end.y, accuracy: 0.0001)

        var previous = start
        for step in stride(from: 0.0, through: 1.0, by: 0.001) {
            let point = circuit.position(at: step)
            let distance = ((point.x - previous.x) * (point.x - previous.x)
                          + (point.y - previous.y) * (point.y - previous.y)).squareRoot()
            XCTAssertLessThan(distance, 0.05, "Das Auto darf auf der Karte nicht springen.")
            previous = point
        }
    }

    func testSectorSplitsCoverTheWholeLap() throws {
        let circuit = try Fixtures.circuit("monza")
        XCTAssertEqual(circuit.sector(at: 0.1), 1)
        XCTAssertEqual(circuit.sector(at: 0.5), 2)
        XCTAssertEqual(circuit.sector(at: 0.9), 3)
    }
}
