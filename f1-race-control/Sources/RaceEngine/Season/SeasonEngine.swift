import Foundation

/// Ein vorbereitetes Rennwochenende: Qualifying ist gefahren, das Rennen kann starten.
public struct WeekendSetup: Sendable {
    public let round: SeasonRound
    public let circuit: Circuit
    public let qualifying: QualifyingResult
    /// Fertig eingestellt, inklusive Startaufstellung aus dem Qualifying.
    public let raceConfiguration: RaceConfiguration
}

public enum SeasonError: Error, CustomStringConvertible {
    case seasonFinished
    case circuitMissing(String)

    public var description: String {
        switch self {
        case .seasonFinished:
            return "Die Saison ist bereits zu Ende."
        case .circuitMissing(let id):
            return "Die Strecke '\(id)' fehlt in den Stammdaten."
        }
    }
}

/// Führt eine Saison Wochenende für Wochenende weiter.
///
/// Bewusst in zwei Schritten getrennt:
///
/// 1. `prepareNextWeekend` fährt das Qualifying und liefert die fertige
///    Rennkonfiguration. Die App kann das Rennen damit **live** anzeigen.
/// 2. `record` trägt das Ergebnis in die Saison ein.
///
/// Wer das Rennen gar nicht sehen will, nimmt `simulateNextWeekend` — das macht beides
/// und rechnet das Rennen im Hintergrund durch.
public enum SeasonEngine {

    /// Qualifying fahren und das Rennen vorbereiten.
    public static func prepareNextWeekend(
        season: Season,
        data: RaceData
    ) throws -> WeekendSetup {
        guard let round = season.nextRound else { throw SeasonError.seasonFinished }
        guard let circuit = data.circuit(id: round.circuitID) else {
            throw SeasonError.circuitMissing(round.circuitID)
        }

        let roundSeed = season.seed(forRound: round.round)
        let weather = startingWeather(for: circuit, seed: roundSeed)

        let qualifying = QualifyingSimulator.run(
            circuit: circuit,
            drivers: data.drivers,
            teams: data.teams,
            weather: weather,
            aiStrength: season.aiStrength,
            seed: roundSeed
        )

        let laps = max(3, Int((Double(circuit.defaultLaps) * season.raceLengthFactor).rounded()))

        let configuration = RaceConfiguration(
            circuit: circuit,
            drivers: data.drivers,
            teams: data.teams,
            laps: laps,
            startingGrid: qualifying.grid,
            startingWeather: weather.state,
            aiStrength: season.aiStrength,
            weatherVariability: season.weatherVariability,
            seed: roundSeed
        )

        return WeekendSetup(
            round: round,
            circuit: circuit,
            qualifying: qualifying,
            raceConfiguration: configuration
        )
    }

    /// Ein gefahrenes Rennen in die Saison eintragen.
    @discardableResult
    public static func record(
        race: RaceResult,
        setup: WeekendSetup,
        into season: inout Season
    ) -> RoundResult {
        let result = RoundResult(
            round: setup.round.round,
            circuitID: setup.round.circuitID,
            qualifying: setup.qualifying,
            race: race
        )
        // Doppelte Einträge derselben Runde verhindern.
        season.results.removeAll { $0.round == result.round }
        season.results.append(result)
        season.results.sort { $0.round < $1.round }
        return result
    }

    /// Wochenende komplett im Hintergrund durchrechnen.
    @discardableResult
    public static func simulateNextWeekend(
        season: inout Season,
        data: RaceData
    ) throws -> RoundResult {
        let setup = try prepareNextWeekend(season: season, data: data)
        let engine = RaceEngine(configuration: setup.raceConfiguration)
        engine.runToCompletion()
        guard let race = engine.result() else {
            // Kann nur passieren, wenn die Sicherheitsgrenze der Schleife greift.
            throw SeasonError.circuitMissing(setup.round.circuitID)
        }
        return record(race: race, setup: setup, into: &season)
    }

    /// Die restliche Saison am Stück durchrechnen.
    public static func simulateRemainingSeason(
        season: inout Season,
        data: RaceData,
        onRound: ((RoundResult) -> Void)? = nil
    ) throws {
        while !season.isFinished {
            let result = try simulateNextWeekend(season: &season, data: data)
            onRound?(result)
        }
    }

    /// Wetter zum Rennstart auswürfeln.
    ///
    /// Gewichtet mit der Regenneigung der Strecke: In Spa oder São Paulo wird es
    /// öfter nass als in Bahrain oder Las Vegas.
    static func startingWeather(for circuit: Circuit, seed: UInt64) -> WeatherConditions {
        var source = RandomSource(masterSeed: seed)
        let state: WeatherState = source.with(.weather) { rng in
            let roll = rng.unit()
            let rain = circuit.rainProbability
            if roll < rain * 0.30 { return .heavyRain }
            if roll < rain * 0.75 { return .lightRain }
            if roll < rain * 1.60 { return .cloudy }
            return .dry
        }

        var conditions = WeatherConditions()
        conditions.state = state
        conditions.trackWetness = state.targetWetness
        conditions.airTemperature = 24 - state.targetWetness * 6
        conditions.trackTemperature = 40 - state.targetWetness * 16
        conditions.windSpeed = 6 + circuit.rainProbability * 10
        conditions.rainProbability = circuit.rainProbability
        return conditions
    }
}
