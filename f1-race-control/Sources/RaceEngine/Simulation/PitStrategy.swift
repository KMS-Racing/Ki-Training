import Foundation

/// Die Boxenstrategie der KI.
///
/// Entscheidet für jedes Auto selbst, wann es an die Box kommt und welchen Reifen es
/// aufzieht. Drei Gründe für einen Stopp, in dieser Reihenfolge:
///
/// 1. **Das Wetter hat gedreht** — falscher Reifen kostet mehr als jeder Stopp.
/// 2. **Die Reifen sind am Ende** — kurz vor der Klippe.
/// 3. **Günstige Gelegenheit** — unter VSC oder Safety Car kostet ein Stopp
///    viel weniger Zeit, weil alle anderen auch langsam fahren.
public enum PitStrategy {

    /// Das Ergebnis einer Strategie-Überlegung.
    public struct Decision {
        public let shouldPit: Bool
        public let compound: TyreCompound
        public let reason: String

        public static let stayOut = Decision(shouldPit: false, compound: .medium, reason: "")
    }

    /// Soll dieses Auto jetzt an die Box?
    ///
    /// Wird immer beim Überfahren der Linie gefragt, also einmal pro Runde.
    public static func evaluate(
        driver: Driver,
        tyres: TyreSet,
        circuit: Circuit,
        weather: WeatherConditions,
        trackStatus: TrackStatus,
        lapsCompleted: Int,
        totalLaps: Int,
        pitStopsMade: Int,
        random: inout SeededRandom
    ) -> Decision {
        let lapsRemaining = totalLaps - lapsCompleted

        // In der letzten Runde kommt niemand mehr rein — durchfahren ist immer schneller.
        guard lapsRemaining > 1 else { return .stayOut }

        let idealCompound = TyreCompound.best(forWetness: weather.trackWetness)
        let currentPenalty = TyreModel.weatherPenalty(compound: tyres.compound, wetness: weather.trackWetness)

        // Sperrfrist nach einem Stopp.
        //
        // Ohne die pendelt ein Auto bei wechselndem Wetter zwischen Slicks und
        // Regenreifen hin und her und steht am Ende öfter in der Box als auf der
        // Strecke. Nur ein wirklich hoffnungsloser Reifen darf sofort wieder rein.
        if tyres.age < 4 && currentPenalty < 8.0 {
            return .stayOut
        }

        // --- 1. Falscher Reifen fürs Wetter ---
        if currentPenalty > 2.5 {
            // Lohnt sich der Stopp noch? Der Verlust muss über die Restrunden wieder reinkommen.
            let expectedGain = currentPenalty * Double(lapsRemaining)
            if expectedGain > circuit.pitLaneLoss {
                return Decision(
                    shouldPit: true,
                    compound: idealCompound,
                    reason: "WRONG COMPOUND FOR CONDITIONS"
                )
            }
        }

        // --- 2. Reifen am Ende ---
        let remainingTyreLaps = TyreModel.estimatedRemainingLaps(
            tyres: tyres, driver: driver, circuit: circuit, weather: weather
        )
        if remainingTyreLaps <= 1 && lapsRemaining > 3 {
            return Decision(
                shouldPit: true,
                compound: chooseCompound(
                    idealCompound: idealCompound,
                    lapsRemaining: lapsRemaining,
                    circuit: circuit,
                    driver: driver,
                    weather: weather
                ),
                reason: "TYRES AT THE END OF THEIR LIFE"
            )
        }

        // --- 3. Günstige Gelegenheit unter Neutralisierung ---
        // Ein Stopp unter Safety Car kostet oft nur die Hälfte — die halbe Startaufstellung
        // kommt dann gleichzeitig rein. Das ist echte Formel-1-Strategie.
        if trackStatus.isNeutralised, tyres.wear > 0.35, lapsRemaining > 5 {
            // Nicht alle reagieren gleich schnell — sonst wäre es zu mechanisch.
            if random.chance(0.75) {
                return Decision(
                    shouldPit: true,
                    compound: chooseCompound(
                        idealCompound: idealCompound,
                        lapsRemaining: lapsRemaining,
                        circuit: circuit,
                        driver: driver,
                        weather: weather
                    ),
                    reason: "CHEAP STOP UNDER NEUTRALISATION"
                )
            }
        }

        // --- 4. Pflichtstopp im Trockenen ---
        //
        // Im Reglement muss bei trockenem Rennen jeder zwei verschiedene Mischungen
        // gefahren haben. Das ist kein „vielleicht“: Wer bis kurz vor Schluss draußen
        // bleibt, muss rein — sonst würde die Strategie das Rennen entscheiden statt
        // des Tempos, und genau das war vorher der Fehler.
        if pitStopsMade == 0, weather.trackWetness < 0.30 {
            let earliest = max(2, totalLaps / 3)
            let latest = max(earliest, totalLaps - 4)
            let mustPitNow = lapsCompleted >= latest
            let goodMoment = lapsCompleted >= earliest && tyres.wear > 0.45

            if mustPitNow || goodMoment {
                return Decision(
                    shouldPit: true,
                    compound: chooseCompound(
                        idealCompound: idealCompound,
                        lapsRemaining: lapsRemaining,
                        circuit: circuit,
                        driver: driver,
                        weather: weather
                    ),
                    reason: "MANDATORY COMPOUND CHANGE"
                )
            }
        }

        return .stayOut
    }

    /// Welchen Reifen aufziehen?
    ///
    /// Im Regen entscheidet nur das Wetter. Im Trockenen zählt die Restdistanz:
    /// Für einen kurzen Schlussspurt nimmt man den weichen, für einen langen Stint den harten.
    public static func chooseCompound(
        idealCompound: TyreCompound,
        lapsRemaining: Int,
        circuit: Circuit,
        driver: Driver,
        weather: WeatherConditions
    ) -> TyreCompound {
        // Nass: keine Wahl.
        if !idealCompound.isSlick { return idealCompound }

        // Wie viele Runden hält welcher Reifen hier?
        let probe = WeatherConditions(
            state: weather.state,
            trackWetness: weather.trackWetness,
            airTemperature: weather.airTemperature,
            trackTemperature: weather.trackTemperature
        )
        for candidate in [TyreCompound.soft, .medium, .hard] {
            let life = TyreModel.estimatedRemainingLaps(
                tyres: TyreSet.fresh(candidate), driver: driver, circuit: circuit, weather: probe
            )
            // Der weichste Reifen, der bis ins Ziel hält, ist der schnellste.
            if life >= lapsRemaining { return candidate }
        }
        return .hard
    }

    /// Wie lange das Auto tatsächlich steht.
    ///
    /// Eine gute Crew wechselt in gut zwei Sekunden, eine schwache braucht länger —
    /// und ab und zu klemmt ein Rad, dann werden daraus schnell zehn.
    public static func stationaryTime(team: Team, random: inout SeededRandom) -> Double {
        let skill = team.pitCrewSkill / 100.0
        let base = 3.4 - skill * 1.2          // 2.2 s bei perfekter Crew, 3.4 s bei schwacher
        let jitter = random.gaussian(mean: 0, standardDeviation: 0.18)
        var duration = max(1.9, base + jitter)

        // Patzer: klemmendes Rad, Radmutter verkantet.
        if random.chance(0.05 * (1.4 - skill)) {
            duration += random.double(in: 2.0...9.0)
        }
        return duration
    }
}
