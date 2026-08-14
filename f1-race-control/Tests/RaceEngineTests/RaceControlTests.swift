import XCTest
@testable import RaceEngine

/// VSC, Safety Car, Rote Flagge und die Entscheidungen des Race Directors.
final class RaceControlTests: XCTestCase {

    // MARK: - Race Director

    func testMinorIncidentGivesYellowFlagOnly() {
        let verdict = RaceDirector.evaluate(
            incident: Fixtures.incident(kind: .spin, severity: .medium,
                                        blocksTrack: false, carStopped: false),
            currentStatus: .green, wetness: 0, lapsRemaining: 30, runningCars: 20
        )
        XCTAssertEqual(verdict.decision, .localYellow)
        XCTAssertFalse(verdict.justification.isEmpty)
    }

    func testStoppedCarOffTrackGivesVSC() {
        let verdict = RaceDirector.evaluate(
            incident: Fixtures.incident(blocksTrack: false, carStopped: true),
            currentStatus: .green, wetness: 0, lapsRemaining: 30, runningCars: 20
        )
        XCTAssertEqual(verdict.decision, .virtualSafetyCar)
        XCTAssertTrue(verdict.justification.contains("Virtual Safety Car"))
    }

    func testBlockedTrackGivesSafetyCar() {
        let verdict = RaceDirector.evaluate(
            incident: Fixtures.incident(blocksTrack: true, carStopped: true),
            currentStatus: .green, wetness: 0, lapsRemaining: 30, runningCars: 20
        )
        XCTAssertEqual(verdict.decision, .safetyCar)
    }

    func testMultiCarPileUpGivesRedFlag() {
        let verdict = RaceDirector.evaluate(
            incident: Fixtures.incident(drivers: ["VER", "NOR", "LEC"],
                                        blocksTrack: true, carStopped: true),
            currentStatus: .green, wetness: 0, lapsRemaining: 30, runningCars: 20
        )
        XCTAssertEqual(verdict.decision, .redFlag)
    }

    func testWetConditionsEscalateOneLevel() {
        let dry = RaceDirector.evaluate(
            incident: Fixtures.incident(blocksTrack: false, carStopped: true),
            currentStatus: .green, wetness: 0.1, lapsRemaining: 30, runningCars: 20
        )
        let wet = RaceDirector.evaluate(
            incident: Fixtures.incident(blocksTrack: false, carStopped: true),
            currentStatus: .green, wetness: 0.9, lapsRemaining: 30, runningCars: 20
        )
        XCTAssertEqual(dry.decision, .virtualSafetyCar)
        XCTAssertEqual(wet.decision, .safetyCar, "Auf nasser Strecke wird eine Stufe schärfer entschieden.")
    }

    func testNoRedFlagInTheClosingLaps() {
        let verdict = RaceDirector.evaluate(
            incident: Fixtures.incident(drivers: ["VER", "NOR", "LEC"],
                                        blocksTrack: true, carStopped: true),
            currentStatus: .green, wetness: 0, lapsRemaining: 2, runningCars: 20
        )
        XCTAssertEqual(verdict.decision, .safetyCar,
                       "Kurz vor Schluss wird nicht mehr abgebrochen.")
    }

    func testNoDowngradeWhenSomethingStricterAlreadyApplies() {
        let verdict = RaceDirector.evaluate(
            incident: Fixtures.incident(blocksTrack: false, carStopped: true),
            currentStatus: .safetyCar(phase: .active),
            wetness: 0, lapsRemaining: 30, runningCars: 20
        )
        XCTAssertEqual(verdict.decision, .noAction)
    }

    func testDecisionIsDeterministic() {
        let incident = Fixtures.incident(blocksTrack: true, carStopped: true)
        let a = RaceDirector.evaluate(incident: incident, currentStatus: .green,
                                      wetness: 0.3, lapsRemaining: 20, runningCars: 18)
        let b = RaceDirector.evaluate(incident: incident, currentStatus: .green,
                                      wetness: 0.3, lapsRemaining: 20, runningCars: 18)
        XCTAssertEqual(a, b, "Gleiche Lage muss immer zur gleichen Anordnung führen.")
    }

    // MARK: - VSC-Ablauf

    func testVSCActivatesAndCountsDownToGreen() {
        let system = SafetyCarSystem()
        let verdict = DirectorVerdict(decision: .virtualSafetyCar,
                                      justification: "Test", clearanceSeconds: 40)

        let deployEvents = system.apply(verdict: verdict, lap: 10)
        XCTAssertTrue(system.status.isNeutralised, "Nach der Anordnung muss VSC gelten.")
        XCTAssertEqual(deployEvents.count, 1)

        // Während VSC ist Überholen gesperrt und alle fahren langsamer.
        XCTAssertFalse(system.status.allowsOvertaking)
        XCTAssertGreaterThan(system.status.lapTimeMultiplier, 1.2)

        // Ausrollphase → aktiv.
        _ = system.update(deltaTime: 10, lap: 10)
        if case .virtualSafetyCar(let phase) = system.status {
            XCTAssertEqual(phase, .active)
        } else {
            XCTFail("VSC sollte aktiv sein.")
        }

        // Mindestdauer aussitzen, dann muss die Endphase kommen.
        var sawEnding = false
        for _ in 0..<400 {
            let events = system.update(deltaTime: 0.25, lap: 10)
            if events.contains(where: { if case .virtualSafetyCarEnding = $0 { return true }; return false }) {
                sawEnding = true
                break
            }
        }
        XCTAssertTrue(sawEnding, "Nach der Bergung muss das VSC angekündigt enden.")

        // Der Countdown zählt sichtbar herunter.
        var seenCounts: Set<Int> = []
        var sawGreen = false
        for _ in 0..<80 {
            let events = system.update(deltaTime: 0.25, lap: 10)
            if let value = system.countdown { seenCounts.insert(value) }
            if events.contains(where: { if case .greenFlag = $0 { return true }; return false }) {
                sawGreen = true
                break
            }
        }
        XCTAssertTrue(sawGreen, "Am Ende muss die grüne Flagge kommen.")
        XCTAssertEqual(system.status, .green)
        XCTAssertTrue(seenCounts.contains(5) && seenCounts.contains(1),
                      "Der Countdown 5…1 muss sichtbar sein, gesehen: \(seenCounts.sorted())")
    }

    func testVSCRespectsMinimumDuration() {
        let system = SafetyCarSystem()
        // Bergung praktisch sofort fertig — das VSC muss trotzdem eine Weile stehen.
        _ = system.apply(verdict: DirectorVerdict(decision: .virtualSafetyCar,
                                                  justification: "Test", clearanceSeconds: 1),
                         lap: 5)
        for _ in 0..<100 {   // 25 Sekunden
            _ = system.update(deltaTime: 0.25, lap: 5)
        }
        XCTAssertTrue(system.status.isNeutralised,
                      "Ein VSC endet nicht nach wenigen Sekunden.")
    }

    func testSafetyCarChangesRaceState() {
        let system = SafetyCarSystem()
        _ = system.apply(verdict: DirectorVerdict(decision: .safetyCar,
                                                  justification: "Test", clearanceSeconds: 60),
                         lap: 8)
        guard case .safetyCar = system.status else {
            return XCTFail("Safety Car sollte gelten.")
        }
        XCTAssertFalse(system.status.allowsOvertaking)
        XCTAssertGreaterThan(system.status.lapTimeMultiplier,
                             TrackStatus.virtualSafetyCar(phase: .active).lapTimeMultiplier,
                             "Hinter dem Safety Car ist es langsamer als unter VSC.")
    }

    func testRedFlagSuspendsAndCanResume() {
        let system = SafetyCarSystem()
        _ = system.apply(verdict: DirectorVerdict(decision: .redFlag,
                                                  justification: "Test", clearanceSeconds: 30),
                         lap: 15)
        XCTAssertEqual(system.status, .redFlag)
        XCTAssertFalse(system.status.isRunning, "Bei roter Flagge läuft das Rennen nicht.")

        let events = system.resumeFromRedFlag(lap: 15)
        XCTAssertTrue(events.contains(where: { if case .raceResumed = $0 { return true }; return false }))
        XCTAssertTrue(system.status.isNeutralised,
                      "Nach der roten Flagge wird hinter dem Safety Car neu gestartet.")
    }

    // MARK: - Meldungen

    func testMessagesAreFormattedLikeRealRaceControl() throws {
        let data = try Fixtures.data()
        let control = RaceControl(drivers: data.drivers)

        control.handle(.virtualSafetyCarDeployed(lap: 18, reason: "Car stopped."))
        control.handle(.penalty(driverID: "HAM", lap: 31, seconds: 5, reason: "TRACK LIMITS"))

        XCTAssertEqual(control.messages.count, 2)
        XCTAssertTrue(control.messages[0].displayLine.hasPrefix("LAP 18 / VSC DEPLOYED"))

        let penalty = control.messages[1]
        XCTAssertEqual(penalty.category, .penalty)
        XCTAssertTrue(penalty.displayLine.contains("5 SECOND PENALTY"))
        XCTAssertTrue(penalty.displayLine.contains("CAR 44"), penalty.displayLine)
    }

    func testMessagesAreNumberedInOrder() throws {
        let data = try Fixtures.data()
        let control = RaceControl(drivers: data.drivers)
        for lap in 1...5 {
            control.handle(.greenFlag(lap: lap))
        }
        XCTAssertEqual(control.messages.map { $0.id }, [1, 2, 3, 4, 5])
        XCTAssertEqual(control.messages.map { $0.lap }, [1, 2, 3, 4, 5])
    }

    func testLapTimeFormatting() {
        XCTAssertEqual(RaceControl.formatLapTime(83.412), "1:23.412")
        XCTAssertEqual(RaceControl.formatLapTime(0), "—")
        XCTAssertEqual(RaceControl.formatGap(1.824), "+1.824")
    }
}
