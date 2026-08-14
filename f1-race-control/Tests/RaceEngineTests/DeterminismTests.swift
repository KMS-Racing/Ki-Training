import XCTest
@testable import RaceEngine

/// Reproduzierbarkeit — die Grundlage dafür, dass man überhaupt testen kann.
final class DeterminismTests: XCTestCase {

    func testSameSeedProducesIdenticalRace() throws {
        let first = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 4242))
        let second = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 4242))
        first.runToCompletion()
        second.runToCompletion()

        let a = try XCTUnwrap(first.result())
        let b = try XCTUnwrap(second.result())

        XCTAssertEqual(a.entries.map { $0.driverID }, b.entries.map { $0.driverID },
                       "Gleicher Seed muss dieselbe Reihenfolge ergeben.")
        XCTAssertEqual(a.entries.map { $0.points }, b.entries.map { $0.points })
        XCTAssertEqual(a.raceDuration, b.raceDuration, accuracy: 0.0001)

        for (left, right) in zip(a.entries, b.entries) {
            XCTAssertEqual(left.classifiedTime, right.classifiedTime, accuracy: 0.0001)
            XCTAssertEqual(left.pitStops, right.pitStops)
            XCTAssertEqual(left.lapsCompleted, right.lapsCompleted)
        }
    }

    func testSameSeedProducesIdenticalEventLog() throws {
        let first = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 99))
        let second = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 99))
        first.runToCompletion()
        second.runToCompletion()

        XCTAssertEqual(first.events.logSignature, second.events.logSignature,
                       "Auch die Ereignisfolge muss identisch sein.")
        XCTAssertGreaterThan(first.events.log.count, 50)
    }

    func testDifferentSeedsProduceDifferentRaces() throws {
        let first = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 1))
        let second = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 2))
        first.runToCompletion()
        second.runToCompletion()

        let a = try XCTUnwrap(first.result())
        let b = try XCTUnwrap(second.result())
        XCTAssertNotEqual(a.entries.map { $0.driverID }, b.entries.map { $0.driverID },
                          "Verschiedene Seeds sollen verschiedene Rennen ergeben.")
    }

    func testStepSizeDoesNotChangeTheOutcomeMuch() throws {
        // Feinere Schritte dürfen das Rennen nicht in ein völlig anderes verwandeln —
        // die Zufallszahlen hängen an den Runden, nicht an der Schrittweite.
        let coarse = RaceEngine(configuration: try Fixtures.configuration(laps: 10, seed: 77))
        let fine = RaceEngine(configuration: try Fixtures.configuration(laps: 10, seed: 77))

        while !coarse.isFinished { coarse.advance(0.5) }
        while !fine.isFinished { fine.advance(0.1) }

        let a = try XCTUnwrap(coarse.result())
        let b = try XCTUnwrap(fine.result())
        XCTAssertEqual(try XCTUnwrap(a.winner).driverID, try XCTUnwrap(b.winner).driverID,
                       "Der Sieger darf nicht von der Schrittweite abhängen.")
    }

    // MARK: - Der Zufallsgenerator selbst

    func testSeededRandomRepeats() {
        var a = SeededRandom(seed: 12345)
        var b = SeededRandom(seed: 12345)
        for _ in 0..<1000 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testUnitValuesStayInRange() {
        var random = SeededRandom(seed: 7)
        for _ in 0..<10_000 {
            let value = random.unit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testChanceIsRoughlyCorrect() {
        var random = SeededRandom(seed: 3)
        var hits = 0
        let rounds = 20_000
        for _ in 0..<rounds where random.chance(0.25) { hits += 1 }
        let rate = Double(hits) / Double(rounds)
        XCTAssertEqual(rate, 0.25, accuracy: 0.02)
    }

    func testGaussianIsCentred() {
        var random = SeededRandom(seed: 11)
        var total = 0.0
        let rounds = 20_000
        for _ in 0..<rounds { total += random.gaussian(mean: 0, standardDeviation: 1) }
        XCTAssertEqual(total / Double(rounds), 0, accuracy: 0.05)
    }

    func testStreamsAreIndependent() {
        var source = RandomSource(masterSeed: 5)
        let a = source.with(.incidents) { $0.next() }
        var other = RandomSource(masterSeed: 5)
        // Erst einen anderen Strom benutzen …
        _ = other.with(.weather) { $0.next() }
        _ = other.with(.pitStops) { $0.next() }
        let b = other.with(.incidents) { $0.next() }

        XCTAssertEqual(a, b, """
            Ein Teilsystem darf die Zufallsfolge eines anderen nicht verschieben — \
            sonst würde jede neue Funktion alle bestehenden Rennen verändern.
            """)
    }

    func testIntRangeIsInclusive() {
        var random = SeededRandom(seed: 2)
        var seen: Set<Int> = []
        for _ in 0..<500 { seen.insert(random.int(in: 1...3)) }
        XCTAssertEqual(seen, [1, 2, 3])
    }
}
