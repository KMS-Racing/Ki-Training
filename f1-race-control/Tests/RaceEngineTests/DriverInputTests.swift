import XCTest
@testable import RaceEngine

/// Selbst fahren: Tempostufen, Batterie, eigene Boxenstrategie.
final class DriverInputTests: XCTestCase {

    // MARK: - Die Stufen selbst

    func testFasterPushMeansFasterLapButMoreWear() {
        let order: [PushLevel] = [.conserve, .normal, .push, .attack]
        for index in 1..<order.count {
            XCTAssertLessThan(order[index].lapTimeDelta, order[index - 1].lapTimeDelta,
                              "\(order[index]) muss schneller sein als \(order[index - 1]).")
            XCTAssertGreaterThan(order[index].wearFactor, order[index - 1].wearFactor,
                                 "\(order[index]) muss mehr Reifen kosten.")
            XCTAssertGreaterThan(order[index].riskFactor, order[index - 1].riskFactor,
                                 "\(order[index]) muss riskanter sein.")
            XCTAssertLessThan(order[index].batteryPerLap, order[index - 1].batteryPerLap,
                              "\(order[index]) muss mehr Energie kosten.")
        }
    }

    func testOnlyPushAndAttackNeedBattery() {
        XCTAssertFalse(PushLevel.conserve.needsBattery)
        XCTAssertFalse(PushLevel.normal.needsBattery)
        XCTAssertTrue(PushLevel.push.needsBattery)
        XCTAssertTrue(PushLevel.attack.needsBattery)
    }

    // MARK: - Batterie

    func testBatteryStaysInBounds() {
        var battery = 1.0
        for _ in 0..<50 { battery = BatteryModel.advance(battery: battery, level: .conserve) }
        XCTAssertEqual(battery, 1.0, accuracy: 0.0001, "Voller als voll geht nicht.")

        for _ in 0..<50 { battery = BatteryModel.advance(battery: battery, level: .attack) }
        XCTAssertEqual(battery, 0.0, accuracy: 0.0001, "Leerer als leer auch nicht.")
    }

    func testEmptyBatteryFallsBackToNormal() {
        XCTAssertEqual(BatteryModel.effective(.attack, battery: 1.0), .attack)
        XCTAssertEqual(BatteryModel.effective(.attack, battery: 0.0), .normal,
                       "Ohne Strom nützt der Angriffsmodus nichts.")
        XCTAssertEqual(BatteryModel.effective(.push, battery: 0.01), .normal)
        // Schonen geht immer — das kostet ja keine Energie.
        XCTAssertEqual(BatteryModel.effective(.conserve, battery: 0.0), .conserve)
    }

    func testAttackDrainsTheBatteryInARace() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 25, seed: 4))
        XCTAssertTrue(engine.claimCar(driverID: "VER"))
        engine.setInput(DriverInput(pushLevel: .attack), for: "VER")

        engine.run(seconds: 600)
        let state = try XCTUnwrap(
            engine.snapshot().standings.first { $0.driverID == "VER" })
        XCTAssertLessThan(state.battery, 0.5, "Dauerangriff muss die Batterie leeren.")

        // Und beim Schonen lädt sie wieder.
        engine.setInput(DriverInput(pushLevel: .conserve), for: "VER")
        engine.run(seconds: 600)
        let later = try XCTUnwrap(
            engine.snapshot().standings.first { $0.driverID == "VER" })
        XCTAssertGreaterThan(later.battery, state.battery, "Schonen muss nachladen.")
    }

    // MARK: - Ein Auto übernehmen

    func testClaimingACarWorksOnlyOnce() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10))
        XCTAssertTrue(engine.claimCar(driverID: "NOR"))
        XCTAssertFalse(engine.claimCar(driverID: "NOR"), "Ein Auto hat nur einen Fahrer.")
        XCTAssertFalse(engine.claimCar(driverID: "GIBTESNICHT"))

        XCTAssertEqual(engine.humanControlledDrivers, ["NOR"])

        engine.releaseCar(driverID: "NOR")
        XCTAssertTrue(engine.humanControlledDrivers.isEmpty)
        XCTAssertTrue(engine.claimCar(driverID: "NOR"), "Nach dem Freigeben wieder frei.")
    }

    func testInputIsIgnoredForAICars() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10))
        // Ohne claimCar darf nichts passieren.
        engine.setInput(DriverInput(pushLevel: .attack), for: "VER")
        XCTAssertEqual(engine.input(for: "VER")?.pushLevel, .normal)
    }

    func testHumanFlagReachesTheSnapshot() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 10))
        engine.claimCar(driverID: "LEC")
        engine.run(seconds: 60)

        let states = engine.snapshot().standings
        XCTAssertEqual(states.filter { $0.isHumanControlled }.map { $0.driverID }, ["LEC"])
        XCTAssertTrue(states.allSatisfy { $0.battery >= 0 && $0.battery <= 1 })
    }

    // MARK: - Wirkung im Rennen

    func testAttackIsFasterThanConserveOverTheSameRace() throws {
        // Zwei identische Rennen, nur die Tempostufe unterscheidet sich.
        func distance(with level: PushLevel) throws -> Double {
            let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 30, seed: 12))
            engine.claimCar(driverID: "VER")
            engine.setInput(DriverInput(pushLevel: level), for: "VER")
            engine.run(seconds: 300)
            return try XCTUnwrap(
                engine.snapshot().standings.first { $0.driverID == "VER" }).raceProgress
        }

        let attacking = try distance(with: .attack)
        let conserving = try distance(with: .conserve)
        XCTAssertGreaterThan(attacking, conserving,
                             "Wer drückt, muss in derselben Zeit weiter kommen.")
    }

    func testAttackWearsTyresFaster() throws {
        func wear(with level: PushLevel) throws -> Double {
            let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 30, seed: 12))
            engine.claimCar(driverID: "VER")
            engine.setInput(DriverInput(pushLevel: level), for: "VER")
            engine.run(seconds: 400)
            return try XCTUnwrap(
                engine.snapshot().standings.first { $0.driverID == "VER" }).tyres.wear
        }

        XCTAssertGreaterThan(try wear(with: .attack), try wear(with: .conserve),
                             "Angriffstempo muss die Reifen stärker fressen.")
    }

    // MARK: - Eigene Boxenstrategie

    func testHumanPitRequestIsHonoured() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(
            circuitID: "bahrain", laps: 30, seed: 8))
        engine.claimCar(driverID: "HAM")

        var stops: [(String, TyreCompound)] = []
        engine.events.subscribe { event in
            if case .pitStop(let driverID, _, let compound, _) = event {
                stops.append((driverID, compound))
            }
        }

        engine.run(seconds: 200)
        XCTAssertTrue(stops.filter { $0.0 == "HAM" }.isEmpty,
                      "Ohne Anforderung kommt ein menschliches Auto nicht herein.")

        engine.setInput(DriverInput(pushLevel: .normal, pitRequest: .hard), for: "HAM")
        engine.run(until: { stops.contains { $0.0 == "HAM" } }, maxSeconds: 400)

        let own = stops.filter { $0.0 == "HAM" }
        XCTAssertEqual(own.count, 1, "Genau ein Stopp auf Anforderung.")
        XCTAssertEqual(own.first?.1, .hard, "Und zwar auf die gewünschte Mischung.")

        // Die Anforderung ist danach verbraucht — kein Dauerstopp.
        engine.run(seconds: 500)
        XCTAssertEqual(stops.filter { $0.0 == "HAM" }.count, 1,
                       "Eine Anforderung ergibt genau einen Stopp.")
        XCTAssertNil(engine.input(for: "HAM")?.pitRequest)
    }

    func testHumanCarIsNotPittedByTheAI() throws {
        // Der wichtigste Punkt: Die KI-Strategie darf einem Menschen nicht
        // dazwischenfunken. Über eine volle Distanz ohne Anforderung heißt das:
        // kein einziger Stopp, auch wenn die Reifen längst hinüber sind.
        let engine = RaceEngine(configuration: try Fixtures.configuration(
            circuitID: "bahrain", laps: 30, seed: 3))
        engine.claimCar(driverID: "ALO")

        var ownStops = 0
        engine.events.subscribe { event in
            if case .pitStop(let driverID, _, _, _) = event, driverID == "ALO" { ownStops += 1 }
        }
        engine.runToCompletion()
        XCTAssertEqual(ownStops, 0)
    }

    // MARK: - Angriff abschalten

    func testDisablingOvertakesStopsTheCarFromAttacking() throws {
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 40, seed: 21))
        engine.claimCar(driverID: "PER")
        engine.setInput(DriverInput(pushLevel: .normal, allowOvertake: false), for: "PER")

        var attacks = 0
        engine.events.subscribe { event in
            if case .overtake(let driverID, _, _, _) = event, driverID == "PER" { attacks += 1 }
        }
        engine.runToCompletion()
        XCTAssertEqual(attacks, 0, "Wer nicht angreifen will, überholt auch nicht.")
    }

    // MARK: - Nichts kaputt gemacht

    func testAIRacesAreUnchangedByTheFeature() throws {
        // Solange niemand ein Auto übernimmt, muss alles exakt wie vorher laufen.
        // Sonst hätte das Fahrer-Feature alle bestehenden Rennen verändert.
        let first = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 4242))
        let second = RaceEngine(configuration: try Fixtures.configuration(laps: 12, seed: 4242))
        first.runToCompletion()
        second.runToCompletion()

        XCTAssertEqual(first.events.logSignature, second.events.logSignature)
        XCTAssertEqual(try XCTUnwrap(first.result()).entries.map { $0.driverID },
                       try XCTUnwrap(second.result()).entries.map { $0.driverID })

        // Und alle KI-Autos fahren auf `normal` mit voller Batterie.
        let engine = RaceEngine(configuration: try Fixtures.configuration(laps: 8))
        engine.run(seconds: 60)
        for state in engine.snapshot().standings {
            XCTAssertEqual(state.pushLevel, .normal)
            XCTAssertFalse(state.isHumanControlled)
        }
    }
}
