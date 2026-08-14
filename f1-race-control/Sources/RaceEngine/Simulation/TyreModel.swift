import Foundation

/// Alles, was mit Reifen zu tun hat: Abbau, Grip und der daraus folgende Zeitverlust.
///
/// Die Grundidee der Formel 1 in zwei Sätzen: Ein weicher Reifen klebt besser, ist
/// aber schneller hinüber. Und ein Reifen, der nicht zum Wetter passt, kostet so viel
/// Zeit, dass alles andere egal ist.
public enum TyreModel {

    // MARK: - Verschleiß

    /// Wie viel Reifenleben eine Runde kostet.
    ///
    /// - Parameter pushLevel: Wie hart gefahren wird. 1.0 = normales Renntempo,
    ///   1.25 = Angriff/Verteidigung, 0.85 = Reifen schonen.
    public static func wearPerLap(
        tyres: TyreSet,
        driver: Driver,
        circuit: Circuit,
        weather: WeatherConditions,
        pushLevel: Double = 1.0
    ) -> Double {
        // Ein guter Reifenversteher bringt sie deutlich weiter.
        let managementFactor = 1.35 - 0.70 * (driver.tyreManagement / 100.0)

        // Falscher Reifen fürs Wetter zerstört sich selbst — Regenreifen auf trockener
        // Strecke überhitzen, Slicks auf nasser Bahn bekommen keine Temperatur.
        let mismatch = wetnessMismatch(compound: tyres.compound, wetness: weather.trackWetness)
        let mismatchFactor = 1.0 + mismatch * 2.5

        // Nasse Strecke kühlt und schont die Reifen.
        let coolingFactor = 1.0 - 0.25 * weather.trackWetness

        let raw = tyres.compound.baseWearPerLap
            * circuit.tyreWear
            * managementFactor
            * mismatchFactor
            * coolingFactor
            * pushLevel

        return max(0.0, raw)
    }

    /// Grip aus dem Verschleiß.
    ///
    /// Bis etwa 85 % Abnutzung geht es sanft bergab, danach kommt „die Klippe“:
    /// der Reifen bricht plötzlich ein. Genau deshalb wird in der Formel 1 überhaupt
    /// an die Box gefahren, statt einfach durchzufahren.
    public static func grip(forWear wear: Double) -> Double {
        let clamped = min(max(wear, 0.0), 1.0)
        let steady = 0.30 * pow(clamped, 1.6)
        let cliff = clamped > 0.85 ? ((clamped - 0.85) / 0.15) * 0.20 : 0.0
        return min(max(1.0 - steady - cliff, 0.15), 1.0)
    }

    /// Reifen um eine Runde altern lassen.
    public static func advanceLap(
        tyres: inout TyreSet,
        driver: Driver,
        circuit: Circuit,
        weather: WeatherConditions,
        pushLevel: Double = 1.0
    ) {
        tyres.age += 1
        tyres.wear = min(1.0, tyres.wear + wearPerLap(
            tyres: tyres, driver: driver, circuit: circuit, weather: weather, pushLevel: pushLevel
        ))
        tyres.grip = grip(forWear: tyres.wear)
        tyres.temperature = temperature(for: tyres, weather: weather)
    }

    /// Betriebstemperatur — hauptsächlich für die Anzeige.
    public static func temperature(for tyres: TyreSet, weather: WeatherConditions) -> Double {
        let base = weather.trackTemperature + 45
        let compoundBonus: Double = tyres.compound.isSlick ? 8 : -6
        let wetCooling = weather.trackWetness * 30
        return base + compoundBonus - wetCooling
    }

    // MARK: - Zeitverlust

    /// Wie weit dieser Reifen von seiner Wohlfühl-Nässe entfernt ist.
    /// 0 = passt, größer = passt nicht. Der Wert ist das Maß für alles Weitere.
    public static func wetnessMismatch(compound: TyreCompound, wetness: Double) -> Double {
        let distance = abs(wetness - compound.optimalWetness)
        return max(0.0, distance - compound.wetnessTolerance)
    }

    /// Zeitverlust in Sekunden pro Runde, weil der Reifen nicht zum Wetter passt.
    ///
    /// Slicks auf nasser Strecke werden härter bestraft als Regenreifen auf trockener:
    /// zu wenig Profil bei Wasser ist gefährlich langsam, zu viel Profil bei Trockenheit
    /// nur unwirtschaftlich.
    public static func weatherPenalty(compound: TyreCompound, wetness: Double) -> Double {
        let mismatch = wetnessMismatch(compound: compound, wetness: wetness)
        guard mismatch > 0 else { return 0 }
        let slope: Double = compound.isSlick ? 30.0 : 25.0
        return mismatch * slope
    }

    /// Gesamter Reifen-Anteil an der Rundenzeit, in Sekunden.
    ///
    /// Setzt sich zusammen aus der Mischung selbst (weich = schneller), dem Abbau
    /// und der Strafe fürs falsche Wetter.
    public static func lapTimeDelta(
        tyres: TyreSet,
        weather: WeatherConditions
    ) -> Double {
        let compoundDelta = tyres.compound.dryLapDelta
        let wearDelta = (1.0 - grip(forWear: tyres.wear)) * 6.0
        let weatherDelta = weatherPenalty(compound: tyres.compound, wetness: weather.trackWetness)
        return compoundDelta + wearDelta + weatherDelta
    }

    /// Wie viele Runden dieser Satz noch durchhält, bis die Klippe kommt.
    /// Die KI-Strategie plant damit ihren Boxenstopp.
    public static func estimatedRemainingLaps(
        tyres: TyreSet,
        driver: Driver,
        circuit: Circuit,
        weather: WeatherConditions
    ) -> Int {
        let perLap = wearPerLap(tyres: tyres, driver: driver, circuit: circuit, weather: weather)
        guard perLap > 1e-6 else { return 99 }
        let remaining = max(0.0, 0.85 - tyres.wear)
        return Int(remaining / perLap)
    }
}
