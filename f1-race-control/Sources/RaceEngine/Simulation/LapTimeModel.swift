import Foundation

/// Berechnet, wie lange ein Auto für eine Runde braucht.
///
/// Das ist die wichtigste Formel des ganzen Projekts — alles andere (Positionen,
/// Abstände, Strategie) folgt daraus. Sie ist absichtlich als Summe von einzelnen
/// Zuschlägen gebaut und nicht als eine große undurchschaubare Gleichung: so kann man
/// jeden Effekt einzeln nachrechnen, testen und verstellen.
///
/// ```
/// Rundenzeit = Basiszeit der Strecke
///            + Auto & Fahrer
///            + Reifen (Mischung, Abbau, passend zum Wetter?)
///            + Sprit an Bord
///            + nasse Strecke
///            + Dirty Air (Luftwirbel des Vordermanns)
///            + Streuung (kein Mensch trifft zweimal dieselbe Zeit)
///            × Neutralisierung (VSC / Safety Car)
/// ```
public enum LapTimeModel {

    /// Zeitverlust pro Runde Restdistanz durch das Gewicht des Sprits.
    /// Über eine volle Distanz sind das gut 1,5-2 Sekunden zwischen Start und Ziel.
    public static let fuelEffectPerLap: Double = 0.035

    /// Eingabe für eine Rundenzeit-Berechnung.
    public struct Input {
        public var driver: Driver
        public var team: Team
        public var circuit: Circuit
        public var tyres: TyreSet
        public var weather: WeatherConditions
        public var trackStatus: TrackStatus
        /// Wie viele Runden noch zu fahren sind (für die Spritlast).
        public var lapsRemaining: Int
        /// Fährt jemand dicht vor mir?
        public var inDirtyAir: Bool
        /// Stärke der KI-Gegner, 0…1.
        public var aiStrength: Double

        public init(
            driver: Driver,
            team: Team,
            circuit: Circuit,
            tyres: TyreSet,
            weather: WeatherConditions,
            trackStatus: TrackStatus,
            lapsRemaining: Int,
            inDirtyAir: Bool,
            aiStrength: Double
        ) {
            self.driver = driver
            self.team = team
            self.circuit = circuit
            self.tyres = tyres
            self.weather = weather
            self.trackStatus = trackStatus
            self.lapsRemaining = lapsRemaining
            self.inDirtyAir = inDirtyAir
            self.aiStrength = aiStrength
        }
    }

    /// Die Rundenzeit ohne Zufall — nützlich für Tests und für die Strategie-Vorschau.
    public static func deterministicLapTime(_ input: Input) -> Double {
        var time = input.circuit.baseLapTime
        time += performanceDelta(input)
        time += TyreModel.lapTimeDelta(tyres: input.tyres, weather: input.weather)
        time += fuelDelta(lapsRemaining: input.lapsRemaining)
        time += wetTrackDelta(input)
        time += dirtyAirDelta(input)
        return time * input.trackStatus.lapTimeMultiplier
    }

    /// Die tatsächliche Rundenzeit inklusive menschlicher Streuung.
    public static func lapTime(_ input: Input, random: inout SeededRandom) -> Double {
        let base = deterministicLapTime(input)
        let noise = random.gaussian(mean: 0, standardDeviation: variation(input))
        // Nach unten begrenzen: schneller als die theoretische Bestzeit geht nicht.
        return max(base * 0.96, base + noise)
    }

    // MARK: - Die einzelnen Zuschläge

    /// Auto und Fahrer zusammen.
    ///
    /// In der Formel 1 macht das Auto den größeren Teil aus — deshalb 60 % Auto,
    /// 40 % Fahrer. Bei Regen dreht sich das Verhältnis: da kann ein guter Fahrer ein
    /// mäßiges Auto weit nach vorn tragen, also bekommt der Fahrer mehr Gewicht.
    public static func performanceDelta(_ input: Input) -> Double {
        let wetness = input.weather.trackWetness

        // Im Regen zählt das Regen-Können statt des Trocken-Tempos.
        let effectivePace = input.driver.pace * (1 - wetness) + input.driver.wetPerformance * wetness

        let carWeight = 0.60 - 0.20 * wetness
        let driverWeight = 1.0 - carWeight
        var combined = input.team.carPerformance * carWeight + effectivePace * driverWeight

        // Schwächere KI fährt etwas verhaltener.
        combined -= (1.0 - min(max(input.aiStrength, 0), 1)) * 6.0

        // 98 ist der Bestwert, den ein Spitzenpaket erreicht. Alles darunter kostet Zeit,
        // verteilt über die typische Feldspreizung der Strecke.
        let deficit = max(0.0, 98.0 - combined)
        return deficit / 25.0 * input.circuit.paceSpread
    }

    /// Spritlast: volle Tanks sind langsam.
    public static func fuelDelta(lapsRemaining: Int) -> Double {
        return Double(max(0, lapsRemaining)) * fuelEffectPerLap
    }

    /// Nasse Strecke kostet Zeit — unabhängig vom Reifen.
    ///
    /// Der Reifen-Anteil steckt schon im `TyreModel`; hier geht es darum, dass eine
    /// nasse Strecke grundsätzlich langsamer ist. Wer im Regen stark ist, verliert weniger.
    public static func wetTrackDelta(_ input: Input) -> Double {
        let wetness = input.weather.trackWetness
        guard wetness > 0 else { return 0 }
        let skill = input.driver.wetPerformance / 100.0
        // Bis zu 12 s auf komplett nasser Strecke, abgemildert durch Regen-Können.
        return wetness * 12.0 * (1.35 - 0.5 * skill)
    }

    /// Dirty Air: hinter einem anderen Auto fehlt Abtrieb.
    ///
    /// Auf Strecken, wo Überholen schwer ist (Monaco), tut das besonders weh —
    /// dort klebt man fest und kommt nicht vorbei.
    public static func dirtyAirDelta(_ input: Input) -> Double {
        guard input.inDirtyAir else { return 0 }
        guard input.trackStatus.allowsOvertaking else { return 0 }
        return 0.15 + 0.45 * input.circuit.overtakingDifficulty
    }

    /// Wie stark die Rundenzeiten schwanken (Standardabweichung in Sekunden).
    ///
    /// Ein sehr konstanter Fahrer liegt bei gut einer Zehntel, ein unruhiger bei einer
    /// halben Sekunde. Nässe vergrößert die Streuung deutlich.
    public static func variation(_ input: Input) -> Double {
        let base = 0.08 + (100.0 - input.driver.consistency) / 100.0 * 1.2
        let wetFactor = 1.0 + input.weather.trackWetness * 1.5
        let aiFactor = 1.0 + (1.0 - min(max(input.aiStrength, 0), 1)) * 0.8
        return base * wetFactor * aiFactor
    }
}
