import Foundation

/// Würfelt Fahrfehler, Unfälle und technische Defekte aus.
///
/// Die Grundwahrscheinlichkeit ist bewusst klein: pro Fahrer und Runde deutlich unter
/// einem Prozent. Über 20 Autos und 50+ Runden ergibt das trotzdem die zwei bis vier
/// Zwischenfälle, die ein Rennen spannend machen — ohne dass es zum Autoscooter wird.
public enum IncidentModel {

    /// Grundwahrscheinlichkeit eines Fahrfehlers pro Fahrer und Runde.
    public static let baseErrorRate: Double = 0.0035
    /// Grundwahrscheinlichkeit eines technischen Defekts pro Fahrer und Runde.
    public static let baseFailureRate: Double = 0.0018

    /// Wie fehleranfällig ein Fahrer gerade ist.
    public static func errorProbability(
        driver: Driver,
        tyres: TyreSet,
        weatherIncidentFactor: Double,
        trackStatus: TrackStatus,
        isBattling: Bool,
        aiStrength: Double
    ) -> Double {
        // Unter Neutralisierung wird nur gerollt — da passiert praktisch nichts.
        guard trackStatus.allowsOvertaking else { return baseErrorRate * 0.05 }

        // Unruhige Fahrer machen mehr Fehler.
        let consistencyFactor = 0.5 + (100.0 - driver.consistency) / 100.0 * 2.0
        // Wer angreift, riskiert mehr.
        let aggressionFactor = isBattling ? 1.0 + driver.aggression / 100.0 : 1.0
        // Abgefahrene Reifen rutschen.
        let tyreFactor = 1.0 + pow(tyres.wear, 2.0) * 1.5
        // Schwächere KI patzt öfter.
        let aiFactor = 1.0 + (1.0 - min(max(aiStrength, 0), 1)) * 1.5

        return baseErrorRate
            * consistencyFactor
            * aggressionFactor
            * tyreFactor
            * weatherIncidentFactor
            * aiFactor
    }

    /// Wie wahrscheinlich das Auto kaputtgeht.
    public static func failureProbability(team: Team, lapsCompleted: Int) -> Double {
        let reliabilityFactor = (100.0 - team.reliability) / 100.0
        // Je länger das Rennen dauert, desto mehr Belastung.
        let wearFactor = 1.0 + Double(lapsCompleted) / 60.0
        return baseFailureRate * reliabilityFactor * wearFactor
    }

    /// Aus einem Fahrfehler einen konkreten Zwischenfall machen.
    ///
    /// Die meisten Fehler sind harmlos (ein Ausrutscher, ein paar Zehntel verloren).
    /// Nur ein kleiner Teil endet im Kiesbett — und ein noch kleinerer blockiert die Strecke.
    public static func makeDrivingIncident(
        driver: Driver,
        lap: Int,
        sector: Int,
        wetness: Double,
        random: inout SeededRandom
    ) -> Incident {
        let roll = random.unit()
        // Nasse Strecke macht aus Ausrutschern eher echte Unfälle.
        //
        // Der Wert ist bewusst klein: Auch im strömenden Regen ist der weitaus häufigste
        // Fehler ein Verbremser, kein Abflug. Mit einem größeren Wert endet ein
        // Regenrennen mit dem halben Feld im Kiesbett — das sieht man in echt nicht.
        let severityShift = wetness * 0.10

        let kind: IncidentKind
        let severity: IncidentSeverity
        let stopped: Bool
        let blocks: Bool

        if roll < 0.55 - severityShift {
            kind = .offTrack
            severity = .low
            stopped = false
            blocks = false
        } else if roll < 0.82 - severityShift {
            kind = .spin
            severity = .medium
            stopped = false
            blocks = false
        } else if roll < 0.95 {
            kind = .crash
            severity = .high
            stopped = true
            // Im Kiesbett gelandet, aber die Strecke ist frei.
            blocks = random.chance(0.30)
        } else {
            kind = .crash
            severity = .extreme
            stopped = true
            blocks = random.chance(0.70)
        }

        return Incident(
            lap: lap,
            driverIDs: [driver.id],
            kind: kind,
            severity: severity,
            sector: sector,
            blocksTrack: blocks,
            carStopped: stopped
        )
    }

    /// Berührung zwischen zwei Autos nach einem misslungenen Angriff.
    ///
    /// Die meisten Berührungen in der Formel 1 sind leicht: ein Frontflügel geht kaputt,
    /// beide fahren weiter. Nur ein kleiner Teil beendet ein Rennen.
    public static func makeCollision(
        attacker: Driver,
        defender: Driver,
        lap: Int,
        sector: Int,
        random: inout SeededRandom
    ) -> Incident {
        let heavy = random.chance(0.18)
        return Incident(
            lap: lap,
            driverIDs: [attacker.id, defender.id],
            kind: .collision,
            severity: heavy ? .high : .medium,
            sector: sector,
            blocksTrack: heavy && random.chance(0.35),
            carStopped: heavy
        )
    }

    /// Technischer Defekt.
    public static func makeMechanicalFailure(
        driver: Driver,
        lap: Int,
        sector: Int,
        random: inout SeededRandom
    ) -> (incident: Incident, reason: String) {
        let causes = ["POWER UNIT", "GEARBOX", "HYDRAULICS", "BRAKES", "COOLING", "ELECTRICAL"]
        let reason = random.pick(causes) ?? "POWER UNIT"
        let incident = Incident(
            lap: lap,
            driverIDs: [driver.id],
            kind: .mechanical,
            severity: .medium,
            sector: sector,
            blocksTrack: false,
            // Manche Defekte erlauben es noch, das Auto abzustellen — manche nicht.
            carStopped: random.chance(0.60)
        )
        return (incident, reason)
    }
}
