import XCTest
@testable import RaceEngine

/// Reifen: Abbau, Grip und der Zusammenhang mit dem Wetter.
final class TyreTests: XCTestCase {

    func testGripFallsWithWear() {
        var previous = TyreModel.grip(forWear: 0)
        XCTAssertEqual(previous, 1.0, accuracy: 0.001, "Ein frischer Reifen hat vollen Grip.")

        for step in stride(from: 0.05, through: 1.0, by: 0.05) {
            let grip = TyreModel.grip(forWear: step)
            XCTAssertLessThan(grip, previous, "Grip muss mit dem Verschleiß fallen (wear=\(step)).")
            XCTAssertGreaterThanOrEqual(grip, 0.15)
            previous = grip
        }
    }

    func testWornTyresAreSlower() throws {
        let weather = WeatherConditions()
        let fresh = TyreSet.fresh(.medium)
        var worn = TyreSet.fresh(.medium)
        worn.wear = 0.9
        worn.grip = TyreModel.grip(forWear: 0.9)

        let freshDelta = TyreModel.lapTimeDelta(tyres: fresh, weather: weather)
        let wornDelta = TyreModel.lapTimeDelta(tyres: worn, weather: weather)

        XCTAssertGreaterThan(wornDelta - freshDelta, 1.5,
                             "Abgefahrene Reifen müssen deutlich Zeit kosten.")
        XCTAssertLessThan(wornDelta - freshDelta, 6.0,
                          "…aber nicht so viel, dass das Auto stehen bleibt.")
    }

    func testSofterCompoundIsFasterButWearsQuicker() {
        XCTAssertLessThan(TyreCompound.soft.dryLapDelta, TyreCompound.medium.dryLapDelta)
        XCTAssertLessThan(TyreCompound.medium.dryLapDelta, TyreCompound.hard.dryLapDelta)

        XCTAssertGreaterThan(TyreCompound.soft.baseWearPerLap, TyreCompound.medium.baseWearPerLap)
        XCTAssertGreaterThan(TyreCompound.medium.baseWearPerLap, TyreCompound.hard.baseWearPerLap)
    }

    func testTyreManagementMakesTyresLastLonger() throws {
        let circuit = try Fixtures.circuit()
        let weather = WeatherConditions()
        let careful = Fixtures.driver(id: "CAR", tyreManagement: 95)
        let rough = Fixtures.driver(id: "ROU", tyreManagement: 60)

        let carefulWear = TyreModel.wearPerLap(
            tyres: .fresh(.medium), driver: careful, circuit: circuit, weather: weather)
        let roughWear = TyreModel.wearPerLap(
            tyres: .fresh(.medium), driver: rough, circuit: circuit, weather: weather)

        XCTAssertLessThan(carefulWear, roughWear,
                          "Wer die Reifen schont, verbraucht weniger.")
    }

    func testAbrasiveTrackWearsTyresFaster() throws {
        let monaco = try Fixtures.circuit("monaco")     // tyreWear 0.75
        let silverstone = try Fixtures.circuit("silverstone")  // tyreWear 1.35
        let driver = Fixtures.driver()
        let weather = WeatherConditions()

        let monacoWear = TyreModel.wearPerLap(
            tyres: .fresh(.medium), driver: driver, circuit: monaco, weather: weather)
        let silverstoneWear = TyreModel.wearPerLap(
            tyres: .fresh(.medium), driver: driver, circuit: silverstone, weather: weather)

        XCTAssertGreaterThan(silverstoneWear, monacoWear)
    }

    func testSlicksInHeavyRainAreHeavilyPenalised() {
        let soaked = WeatherConditions(state: .heavyRain, trackWetness: 0.95)
        let slickDelta = TyreModel.lapTimeDelta(tyres: .fresh(.soft), weather: soaked)
        let wetDelta = TyreModel.lapTimeDelta(tyres: .fresh(.wet), weather: soaked)

        XCTAssertGreaterThan(slickDelta - wetDelta, 12.0,
                             "Auf Slicks bei Starkregen muss man hoffnungslos langsam sein.")
    }

    func testWetTyresOnDryTrackAreSlower() {
        let dry = WeatherConditions(state: .dry, trackWetness: 0.0)
        let slickDelta = TyreModel.lapTimeDelta(tyres: .fresh(.medium), weather: dry)
        let wetDelta = TyreModel.lapTimeDelta(tyres: .fresh(.wet), weather: dry)

        XCTAssertGreaterThan(wetDelta, slickDelta,
                             "Regenreifen auf trockener Strecke kosten Zeit.")
    }

    func testRightCompoundForConditions() {
        XCTAssertTrue(TyreCompound.best(forWetness: 0.0).isSlick)
        XCTAssertEqual(TyreCompound.best(forWetness: 0.40), .intermediate)
        XCTAssertEqual(TyreCompound.best(forWetness: 0.90), .wet)
    }

    func testGripStaysInBounds() throws {
        let circuit = try Fixtures.circuit()
        let driver = Fixtures.driver()
        var tyres = TyreSet.fresh(.soft)
        let weather = WeatherConditions(state: .lightRain, trackWetness: 0.5)

        // Weit über die Renndistanz hinaus altern lassen.
        for _ in 0..<200 {
            TyreModel.advanceLap(tyres: &tyres, driver: driver, circuit: circuit, weather: weather)
            XCTAssertFalse(tyres.grip.isNaN)
            XCTAssertGreaterThanOrEqual(tyres.grip, 0.15)
            XCTAssertLessThanOrEqual(tyres.grip, 1.0)
            XCTAssertLessThanOrEqual(tyres.wear, 1.0)
        }
    }

    func testAdvanceLapAgesTyres() throws {
        let circuit = try Fixtures.circuit()
        let driver = Fixtures.driver()
        var tyres = TyreSet.fresh(.soft)

        TyreModel.advanceLap(tyres: &tyres, driver: driver, circuit: circuit,
                             weather: WeatherConditions())

        XCTAssertEqual(tyres.age, 1)
        XCTAssertGreaterThan(tyres.wear, 0)
        XCTAssertLessThan(tyres.grip, 1.0)
    }
}
