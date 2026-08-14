import Foundation

/// Das Wettermodell.
///
/// Zwei getrennte Dinge, die oft verwechselt werden:
/// 1. **Der Himmel** (`WeatherState`) — springt zwischen trocken, bewölkt, Regen.
/// 2. **Die Strecke** (`trackWetness`) — läuft dem Himmel *hinterher*.
///
/// Genau daraus entsteht die Spannung im Regenrennen: Es hört auf zu regnen, aber die
/// Strecke ist noch nass. Wer zu früh auf Slicks wechselt, verliert; wer zu spät
/// wechselt, auch. Die Strecke saugt sich schnell voll und trocknet langsam.
public struct WeatherModel {
    public private(set) var conditions: WeatherConditions
    private let circuit: Circuit
    private let variability: Double

    /// Wie lange der aktuelle Zustand schon anhält (Sekunden). Verhindert Zappeln.
    private var timeInState: Double = 0
    /// Frühestens nach dieser Zeit darf das Wetter wieder umschlagen.
    ///
    /// Vier Minuten, damit ein Schauer auch wirklich ein Schauer ist. Mit einem kurzen
    /// Wert kippt das Wetter fast jede Runde, und weil dann jedes Mal das ganze Feld
    /// zum Reifenwechsel kommt, steht am Ende die halbe Startaufstellung in der Box.
    private let minimumStateDuration: Double = 240

    public init(circuit: Circuit, startingWeather: WeatherState, variability: Double) {
        self.circuit = circuit
        self.variability = min(max(variability, 0), 1)

        // Beim Start ist die Strecke schon im Zustand, der zum Wetter passt —
        // ein Rennen, das im Regen beginnt, startet nicht auf trockener Bahn.
        var start = WeatherConditions()
        start.state = startingWeather
        start.trackWetness = startingWeather.targetWetness
        start.airTemperature = 24 - startingWeather.targetWetness * 6
        start.trackTemperature = 40 - startingWeather.targetWetness * 16
        start.windSpeed = 6 + circuit.rainProbability * 10
        start.rainProbability = circuit.rainProbability
        self.conditions = start
    }

    /// Einen Simulationsschritt weiter.
    ///
    /// - Returns: Der neue Zustand, falls sich der Himmel geändert hat — sonst `nil`.
    ///   Die Engine macht daraus ein `weatherChanged`-Ereignis.
    public mutating func update(deltaTime: Double, random: inout SeededRandom) -> WeatherState? {
        timeInState += deltaTime

        var changed: WeatherState? = nil
        if timeInState >= minimumStateDuration {
            if let next = rollTransition(deltaTime: deltaTime, random: &random) {
                conditions.state = next
                timeInState = 0
                changed = next
            }
        }

        updateTrackWetness(deltaTime: deltaTime)
        updateTemperatures(deltaTime: deltaTime)
        conditions.rainProbability = estimatedRainProbability()

        return changed
    }

    /// Würfelt, ob der Himmel umschlägt.
    private mutating func rollTransition(deltaTime: Double, random: inout SeededRandom) -> WeatherState? {
        let options = conditions.state.allowedTransitions
        guard !options.isEmpty else { return nil }

        // Grundneigung pro Minute, skaliert mit Streckenklima und Einstellung.
        let perMinute = 0.06 * (0.4 + variability) * (0.5 + circuit.rainProbability)
        let probability = perMinute * (deltaTime / 60.0)

        guard random.chance(probability) else { return nil }
        return random.pick(options)
    }

    /// Nässe der Strecke nachführen.
    ///
    /// Regen wirkt schnell (Wasser sammelt sich in Minuten), Trocknen dauert —
    /// und geht schneller, je wärmer der Asphalt und je mehr Autos darüberfahren.
    private mutating func updateTrackWetness(deltaTime: Double) {
        let target = conditions.state.targetWetness
        let current = conditions.trackWetness

        let rate: Double
        if target > current {
            // Nass werden: rund 2 Minuten bis zur vollen Nässe.
            rate = 1.0 / 120.0
        } else {
            // Abtrocknen: 6-10 Minuten, wärmerer Asphalt trocknet schneller.
            let warmth = max(0.4, min(1.6, conditions.trackTemperature / 30.0))
            let dryingBoost = conditions.state == .drying ? 1.6 : 1.0
            rate = (1.0 / 480.0) * warmth * dryingBoost
        }

        let step = rate * deltaTime
        if target > current {
            conditions.trackWetness = min(target, current + step)
        } else {
            conditions.trackWetness = max(target, current - step)
        }
        conditions.trackWetness = min(max(conditions.trackWetness, 0.0), 1.0)
    }

    private mutating func updateTemperatures(deltaTime: Double) {
        // Regen kühlt, Sonne wärmt — beides träge.
        let targetAir = 24.0 - conditions.trackWetness * 7.0
        let targetTrack = 42.0 - conditions.trackWetness * 18.0
        let rate = deltaTime / 300.0
        conditions.airTemperature += (targetAir - conditions.airTemperature) * min(1.0, rate)
        conditions.trackTemperature += (targetTrack - conditions.trackTemperature) * min(1.0, rate)
    }

    /// Schätzung für die Anzeige: Wie wahrscheinlich ist (mehr) Regen?
    private func estimatedRainProbability() -> Double {
        let base: Double
        switch conditions.state {
        case .dry: base = 0.05
        case .cloudy: base = 0.35
        case .lightRain: base = 0.75
        case .heavyRain: base = 0.90
        case .drying: base = 0.30
        }
        return min(1.0, base * (0.5 + circuit.rainProbability))
    }

    /// Nässe direkt setzen. Nur für Tests gedacht, damit man nicht erst eine halbe
    /// Stunde Regen simulieren muss, um einen bestimmten Zustand zu prüfen.
    mutating func forceWetnessForTesting(_ value: Double) {
        conditions.trackWetness = min(max(value, 0), 1)
    }

    /// Zusätzliche Unfallgefahr durch Nässe (Faktor auf die Grundwahrscheinlichkeit).
    ///
    /// Am gefährlichsten ist nicht der Dauerregen, sondern die **wechselnde** Strecke:
    /// teils nass, teils trocken, und niemand hat den richtigen Reifen.
    public var incidentFactor: Double {
        let wetness = conditions.trackWetness
        // Höhepunkt bei etwa halbnasser Strecke.
        let tricky = 1.0 - abs(wetness - 0.45) / 0.55
        return 1.0 + wetness * 1.2 + max(0, tricky) * 1.0
    }
}
