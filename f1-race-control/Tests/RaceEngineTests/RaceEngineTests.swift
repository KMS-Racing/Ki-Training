import XCTest
@testable import RaceEngine

/// Das Zusammenspiel im laufenden Rennen: Ende, Ausfälle, Strafen, Boxenstopps, Abstände.
final class RaceEngineTests: XCTestCase {

    // MARK: - Rennende

    func testRaceEndsAfterFinalLap() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 8))
        engine.runToCompletion()

        XCTAssertTrue(engine.isFinished, "Nach der letzten Runde muss das Rennen zu Ende sein.")
        let result = try XCTUnwrap(engine.result())
        let winner = try XCTUnwrap(result.winner)
        XCTAssertEqual(winner.lapsCompleted, 8)

        for entry in result.entries {
            XCTAssertLessThanOrEqual(entry.lapsCompleted, 8,
                                     "Niemand darf mehr Runden fahren als das Rennen lang ist.")
        }
    }

    func testFurtherAdvancingAfterFinishChangesNothing() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 6))
        engine.runToCompletion()

        let before = engine.snapshot().standings.map { $0.driverID }
        let eventCount = engine.events.log.count
        engine.advance(500)

        XCTAssertEqual(engine.snapshot().standings.map { $0.driverID }, before)
        XCTAssertEqual(engine.events.log.count, eventCount,
                       "Ein beendetes Rennen erzeugt keine neuen Ereignisse mehr.")
    }

    func testPositionsAreContiguous() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 6))
        engine.runToCompletion()
        let result = try XCTUnwrap(engine.result())
        XCTAssertEqual(result.entries.map { $0.position }, Array(1...result.entries.count),
                       "Die Platzierungen müssen lückenlos 1…n sein.")
    }

    // MARK: - Ausfall

    func testDNFRemovesDriverFromTheRace() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 15))
        engine.run(seconds: 200)

        let victim = try XCTUnwrap(engine.snapshot().standings.first).driverID
        let lapsAtRetirement = try XCTUnwrap(
            engine.snapshot().standings.first { $0.driverID == victim }
        ).lapsCompleted

        engine.forceRetirement(driverID: victim, reason: "POWER UNIT")

        let afterState = try XCTUnwrap(
            engine.snapshot().standings.first { $0.driverID == victim })
        XCTAssertEqual(afterState.status, .retired)
        XCTAssertEqual(afterState.retirementReason, "POWER UNIT")
        XCTAssertFalse(afterState.isActive)

        // Der Ausgefallene fährt nicht weiter.
        engine.run(seconds: 300)
        let laterState = try XCTUnwrap(
            engine.snapshot().standings.first { $0.driverID == victim })
        XCTAssertEqual(laterState.lapsCompleted, lapsAtRetirement,
                       "Ein ausgefallenes Auto legt keine Runden mehr zurück.")

        // Und er steht im Klassement hinter allen, die ins Ziel gekommen sind.
        engine.runToCompletion()
        let result = try XCTUnwrap(engine.result())
        let victimEntry = try XCTUnwrap(result.entries.first { $0.driverID == victim })
        XCTAssertEqual(victimEntry.status, .retired)
        XCTAssertEqual(victimEntry.points, 0, "Wer ausfällt, bekommt keine Punkte.")

        let finishers = result.entries.filter { $0.status == .finished }
        for finisher in finishers {
            XCTAssertLessThan(finisher.position, victimEntry.position)
        }
    }

    // MARK: - Strafen

    func testPenaltyIsAddedToTheFinalTime() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 8, seed: 7))
        engine.runToCompletion()
        let clean = try XCTUnwrap(engine.result())

        // Dasselbe Rennen, aber der Sieger bekommt kurz vor Schluss eine Strafe.
        let engine2 = RaceEngine(configuration: try Fixtures.configuration(laps: 8, seed: 7))
        let target = try XCTUnwrap(clean.winner).driverID
        engine2.run(until: { engine2.currentLap >= 8 })
        engine2.applyPenalty(driverID: target, seconds: 30, reason: "TRACK LIMITS")
        engine2.runToCompletion()

        let penalised = try XCTUnwrap(engine2.result())
        let entry = try XCTUnwrap(penalised.entries.first { $0.driverID == target })

        XCTAssertEqual(entry.penaltySeconds, 30, accuracy: 0.001)
        XCTAssertEqual(entry.classifiedTime, entry.rawTime + 30, accuracy: 0.01,
                       "Die gewertete Zeit ist Fahrzeit plus Strafe.")
        XCTAssertGreaterThan(entry.position, 1,
                             "30 Sekunden Strafe müssen den Sieger den Sieg kosten.")
    }

    func testPenaltyEventReachesRaceControl() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 5))
        engine.run(seconds: 60)
        engine.applyPenalty(driverID: "VER", seconds: 5, reason: "UNSAFE RELEASE")

        let penaltyMessages = engine.raceControl.messages.filter { $0.category == .penalty }
        XCTAssertEqual(penaltyMessages.count, 1)
        XCTAssertTrue(penaltyMessages[0].headline.contains("5 SECOND PENALTY"))
    }

    // MARK: - Boxenstopp

    func testPitStopChangesTyreAndResetsAge() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(circuitID: "bahrain", laps: 30, seed: 11))

        var sawPitStop = false
        var stoppedDriver: String?
        engine.events.subscribe { event in
            if case .pitStop(let driverID, _, _, let duration) = event {
                sawPitStop = true
                stoppedDriver = driverID
                XCTAssertGreaterThan(duration, 20, "Ein Stopp kostet Boxengasse plus Standzeit.")
            }
        }

        engine.run(until: { sawPitStop }, maxSeconds: 3000)
        XCTAssertTrue(sawPitStop, "In 30 Runden Bahrain muss jemand an die Box kommen.")

        let driverID = try XCTUnwrap(stoppedDriver)
        // Nach Abschluss des Stopps sind die Reifen frisch.
        engine.run(seconds: 60)
        let state = try XCTUnwrap(engine.snapshot().standings.first { $0.driverID == driverID })
        if state.status == .running {
            XCTAssertLessThan(state.tyres.age, 5, "Nach dem Stopp sind die Reifen fast neu.")
            XCTAssertGreaterThan(state.tyres.grip, 0.85)
            XCTAssertGreaterThanOrEqual(state.pitStops, 1)
        }
    }

    func testEveryoneStopsInADryRace() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(
            circuitID: "bahrain", laps: 25, seed: 5, weatherVariability: 0))
        engine.runToCompletion()
        let result = try XCTUnwrap(engine.result())

        let finishers = result.entries.filter { $0.status == .finished }
        XCTAssertGreaterThan(finishers.count, 10)
        for entry in finishers {
            XCTAssertGreaterThanOrEqual(entry.pitStops, 1,
                "\(entry.driverID) hat im Trockenrennen nie gewechselt — die Pflichtmischung fehlt.")
        }
    }

    func testPitStopsAreSpreadOverSeveralLaps() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(
            circuitID: "monza", laps: 30, seed: 42, weatherVariability: 0))

        var stopLaps: [Int] = []
        engine.events.subscribe { event in
            if case .pitStop(_, let lap, _, _) = event { stopLaps.append(lap) }
        }
        engine.runToCompletion()

        XCTAssertGreaterThan(stopLaps.count, 15, "Im Trockenrennen stoppt fast jeder einmal.")
        let distinctLaps = Set(stopLaps).count
        XCTAssertGreaterThanOrEqual(distinctLaps, 5, """
            Die Boxenstopps müssen sich über mehrere Runden verteilen — \
            gemessen: \(distinctLaps) verschiedene Runden aus \(stopLaps.count) Stopps. \
            Kommt das ganze Feld in derselben Runde herein, stimmt das Boxenfenster nicht.
            """)
    }

    // MARK: - Abstände und Timing

    func testGapsGrowDownTheOrder() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10))
        engine.run(seconds: 400)

        let standings = engine.snapshot().standings.filter { $0.isActive && $0.lapsDown == 0 }
        XCTAssertGreaterThan(standings.count, 5)
        XCTAssertEqual(standings[0].gapToLeader, 0, accuracy: 0.001,
                       "Der Führende hat keinen Rückstand auf sich selbst.")

        for index in 1..<standings.count {
            XCTAssertGreaterThanOrEqual(
                standings[index].gapToLeader, standings[index - 1].gapToLeader - 0.001,
                "Der Rückstand darf nach hinten nicht kleiner werden.")
            XCTAssertFalse(standings[index].gapToLeader.isNaN)
        }
    }

    func testIntervalMatchesGapDifference() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10))
        engine.run(seconds: 400)

        let standings = engine.snapshot().standings.filter { $0.isActive && $0.lapsDown == 0 }
        for index in 1..<standings.count {
            let expected = standings[index].gapToLeader - standings[index - 1].gapToLeader
            XCTAssertEqual(standings[index].interval, max(0, expected), accuracy: 0.01,
                           "Das Intervall ist die Differenz der Rückstände.")
        }
    }

    func testSectorTimesAddUpToTheLapTime() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 8))
        engine.run(seconds: 600)

        var checked = 0
        for state in engine.snapshot().standings {
            guard let lapTime = state.lastLapTime, state.lastSectors.count == 3 else { continue }
            let sum = state.lastSectors.reduce(0, +)
            XCTAssertEqual(sum, lapTime, accuracy: 0.01,
                           "Die Sektorzeiten müssen exakt die Rundenzeit ergeben.")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 5, "Es sollten Sektorzeiten vorliegen.")
    }

    func testLapProgressStaysNormalised() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 6))
        while !engine.isFinished {
            engine.advance(0.25)
            for state in engine.snapshot().standings {
                XCTAssertGreaterThanOrEqual(state.lapProgress, 0)
                XCTAssertLessThan(state.lapProgress, 1.0)
                XCTAssertFalse(state.lapProgress.isNaN)
            }
        }
    }

    func testStrongerDriversTendToFinishAhead() throws {
        // Über mehrere Rennen gemittelt muss Können sich durchsetzen —
        // sonst wäre die Simulation reines Würfeln.
        var verstappenTotal = 0
        var strollTotal = 0
        for seed in UInt64(1)...6 {
            let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10, seed: seed))
            engine.runToCompletion()
            let result = try XCTUnwrap(engine.result())
            verstappenTotal += try XCTUnwrap(result.entries.first { $0.driverID == "VER" }).position
            strollTotal += try XCTUnwrap(result.entries.first { $0.driverID == "STR" }).position
        }
        XCTAssertLessThan(verstappenTotal, strollTotal,
                          "Der stärkste Fahrer im stärksten Auto darf nicht regelmäßig hinter dem schwächsten landen.")
    }

    // MARK: - Punkte

    func testPointsFollowTheOfficialTable() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 6))
        engine.runToCompletion()
        let result = try XCTUnwrap(engine.result())

        let finishers = result.entries.filter { $0.status == .finished }
        guard finishers.count >= 11 else { throw XCTSkip("Zu wenige Zielankünfte für diesen Test.") }

        for (index, expected) in RaceResult.pointsTable.enumerated() {
            let entry = finishers[index]
            let bonus = entry.hasFastestLap ? 1 : 0
            XCTAssertEqual(entry.points, expected + bonus,
                           "Platz \(index + 1) muss \(expected) Punkte bekommen.")
        }
        XCTAssertEqual(finishers[10].points, 0, "Ab Platz 11 gibt es keine Punkte.")
    }

    func testFastestLapPointOnlyInsideTheTopTen() throws {
        for seed in UInt64(1)...5 {
            let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 8, seed: seed))
            engine.runToCompletion()
            let result = try XCTUnwrap(engine.result())
            guard let fastest = result.fastestLap else { continue }
            let entry = try XCTUnwrap(result.entries.first { $0.driverID == fastest.driverID })
            if entry.position > 10 || entry.status != .finished {
                let base = entry.position <= RaceResult.pointsTable.count && entry.status == .finished
                    ? RaceResult.pointsTable[entry.position - 1] : 0
                XCTAssertEqual(entry.points, base,
                               "Außerhalb der Top 10 gibt es keinen Extrapunkt für die schnellste Runde.")
            }
        }
    }

    func testConstructorPointsSumUpDriverPoints() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 6))
        engine.runToCompletion()
        let data = try Fixtures.data()
        let result = try XCTUnwrap(engine.result())

        let byTeam = result.constructorPoints(drivers: data.drivers)
        let driverTotal = result.entries.reduce(0) { $0 + $1.points }
        let teamTotal = byTeam.values.reduce(0, +)
        XCTAssertEqual(driverTotal, teamTotal)
    }

    // MARK: - Neutralisierung im laufenden Rennen

    func testInjectedIncidentTriggersNeutralisation() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 20))
        engine.run(seconds: 200)

        engine.injectIncident(Fixtures.incident(
            lap: engine.currentLap, drivers: ["BOT"],
            kind: .crash, severity: .high, blocksTrack: false, carStopped: true))

        XCTAssertTrue(engine.snapshot().trackStatus.isNeutralised,
                      "Ein stehendes Auto muss zu einer Neutralisierung führen.")
        XCTAssertNotNil(engine.directorJustification)
        XCTAssertTrue(engine.raceControl.messages.contains { $0.headline.contains("VSC DEPLOYED") })
    }

    func testNoOvertakingWhileNeutralised() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 30))
        engine.run(seconds: 200)

        var overtakesUnderVSC = 0
        engine.events.subscribe { event in
            if case .overtake = event {
                if engine.snapshot().trackStatus.isNeutralised {
                    overtakesUnderVSC += 1
                }
            }
        }

        engine.forceTrackStatus(.virtualSafetyCar(phase: .active), clearance: 600)
        engine.run(seconds: 300)

        XCTAssertTrue(engine.snapshot().trackStatus.isNeutralised, "Das VSC sollte noch laufen.")
        XCTAssertEqual(overtakesUnderVSC, 0, "Unter VSC darf nicht überholt werden.")
    }

    func testVSCHoldsTheFieldInPlace() throws {
        // Unter VSC hält das Feld die Positionen. Die **Zeit**abstände wachsen dabei
        // sogar — alle fahren langsamer, also dauert dieselbe Strecke länger. Genau
        // deshalb ist ein Boxenstopp unter VSC so billig.
        //
        // Geprüft wird also nicht „Abstand bleibt gleich“, sondern das, was wirklich
        // gelten muss: Alle Abstände wachsen um **denselben** Faktor, niemand holt auf
        // oder fällt zurück, und die Reihenfolge bleibt unverändert.
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 40, seed: 8))
        engine.run(seconds: 500)

        func gaps() -> [String: Double] {
            var result: [String: Double] = [:]
            for state in engine.snapshot().standings where state.status == .running && state.lapsDown == 0 {
                result[state.driverID] = state.gapToLeader
            }
            return result
        }
        func order() -> [String] {
            return engine.snapshot().standings
                .filter { $0.status == .running && $0.lapsDown == 0 }
                .map { $0.driverID }
        }

        let before = gaps()
        let orderBefore = order()
        XCTAssertGreaterThan(before.count, 8)
        XCTAssertGreaterThan(before.values.max() ?? 0, 3.0,
                             "Vor dem VSC muss das Feld auseinandergezogen sein.")

        engine.forceTrackStatus(.virtualSafetyCar(phase: .active), clearance: 600)
        engine.run(seconds: 240)

        let after = gaps()

        // Für jeden Fahrer: um welchen Faktor ist sein Rückstand gewachsen?
        var factors: [Double] = []
        for (driverID, gapBefore) in before where gapBefore > 1.0 {
            guard let gapAfter = after[driverID] else { continue }
            XCTAssertGreaterThan(gapAfter, 0.001,
                                 "\(driverID): Der Abstand darf unter VSC nicht auf null fallen.")
            factors.append(gapAfter / gapBefore)
        }

        XCTAssertGreaterThan(factors.count, 6)
        let smallest = factors.min() ?? 0
        let largest = factors.max() ?? 0
        XCTAssertGreaterThan(smallest, 1.0,
                             "Unter VSC wachsen die Zeitabstände, weil alle langsamer fahren.")
        XCTAssertLessThan(largest - smallest, 0.5, """
            Alle Abstände müssen um denselben Faktor wachsen \
            (kleinster \(smallest), größter \(largest)) — sonst hat jemand \
            unter VSC aufgeholt, und genau das darf nicht passieren.
            """)

        XCTAssertEqual(order(), orderBefore,
                       "Unter VSC darf sich die Reihenfolge nicht ändern.")
    }

    func testGapsAreNeverAllZero() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 20, seed: 3))
        engine.run(seconds: 300)
        engine.forceTrackStatus(.virtualSafetyCar(phase: .active), clearance: 300)
        engine.run(seconds: 60)

        let running = engine.snapshot().standings.filter { $0.status == .running && $0.position > 1 }
        let nonZero = running.filter { $0.gapToLeader > 0.001 }
        XCTAssertGreaterThan(nonZero.count, running.count / 2,
                             "Unter VSC dürfen nicht plötzlich alle bei +0.000 stehen.")
    }

    func testNeutralisationSlowsEveryoneDown() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 30, seed: 3))
        engine.run(seconds: 400)

        // Nur fahrende Autos zählen: ein ausgefallenes behält seine letzte Rundenzeit
        // für immer, und die stammt noch aus der grünen Phase.
        func fastestRunningLap() -> Double {
            return engine.snapshot().standings
                .filter { $0.status == .running }
                .compactMap { $0.lastLapTime }
                .min() ?? 0
        }

        let greenLap = fastestRunningLap()

        engine.forceTrackStatus(.virtualSafetyCar(phase: .active), clearance: 900)
        engine.run(seconds: 500)

        let neutralisedLap = fastestRunningLap()

        XCTAssertGreaterThan(neutralisedLap, greenLap * 1.2,
                             "Unter VSC müssen die Rundenzeiten deutlich steigen.")
    }

    func testRedFlagFreezesTheRace() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 30))
        engine.run(seconds: 300)

        engine.forceTrackStatus(.redFlag, clearance: 600)
        let before = engine.snapshot().standings.map { $0.raceProgress }
        engine.run(seconds: 120)
        let after = engine.snapshot().standings.map { $0.raceProgress }

        XCTAssertEqual(before, after, "Bei roter Flagge steht das Feld still.")
        XCTAssertGreaterThan(engine.raceTime, 300, "Die Uhr läuft trotzdem weiter.")
    }

    func testRedFlaggedRaceStillFinishes() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10))
        engine.run(seconds: 200)
        engine.forceTrackStatus(.redFlag, clearance: 60)
        engine.runToCompletion()

        XCTAssertTrue(engine.isFinished,
                      "Nach der Räumung muss das Rennen fortgesetzt und beendet werden.")
    }
}
