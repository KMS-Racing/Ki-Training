import Foundation

/// Entscheidet, ob ein Überholvorgang gelingt.
///
/// In der Formel 1 reicht es nicht, schneller zu sein — man muss auch vorbeikommen.
/// Deshalb gehen hier fünf Dinge ein: Tempovorteil, Können (Angriff gegen Verteidigung),
/// Reifen, DRS und vor allem die **Strecke**. In Monza gelingt fast jeder Angriff,
/// in Monaco fast keiner. Genau daraus entsteht das typische „hängt fest hinter dem
/// Vordermann“, ohne dass man es extra einprogrammieren müsste.
public enum OvertakeModel {

    /// Ab diesem Abstand (Sekunden) ist man nah genug für einen Angriff.
    public static let attackRange: Double = 0.9
    /// Innerhalb dieses Abstands wirkt DRS.
    public static let drsRange: Double = 1.0

    /// Eingabe für einen Angriff.
    public struct Duel {
        public var attacker: Driver
        public var defender: Driver
        public var attackerTyres: TyreSet
        public var defenderTyres: TyreSet
        /// Wie viel schneller der Angreifer gerade ist (Sekunden pro Runde, positiv = schneller).
        public var paceAdvantage: Double
        public var gap: Double
        public var circuit: Circuit
        public var drsAvailable: Bool

        public init(
            attacker: Driver,
            defender: Driver,
            attackerTyres: TyreSet,
            defenderTyres: TyreSet,
            paceAdvantage: Double,
            gap: Double,
            circuit: Circuit,
            drsAvailable: Bool
        ) {
            self.attacker = attacker
            self.defender = defender
            self.attackerTyres = attackerTyres
            self.defenderTyres = defenderTyres
            self.paceAdvantage = paceAdvantage
            self.gap = gap
            self.circuit = circuit
            self.drsAvailable = drsAvailable
        }
    }

    /// Wahrscheinlichkeit, dass dieser Angriff in dieser Runde klappt.
    public static func passProbability(_ duel: Duel) -> Double {
        guard duel.gap <= attackRange else { return 0 }

        // Tempovorteil: eine halbe Sekunde pro Runde ist schon deutlich.
        let paceScore = min(max(duel.paceAdvantage / 1.2, -1.0), 1.5)

        // Angriff gegen Verteidigung.
        let skillScore = (duel.attacker.overtaking - duel.defender.defending) / 100.0

        // Frische Reifen sind das schärfste Werkzeug beim Überholen.
        let gripScore = duel.attackerTyres.grip - duel.defenderTyres.grip

        // DRS öffnet den Flügel auf der Geraden.
        let drsScore = duel.drsAvailable ? 0.30 : 0.0

        // Mutige Fahrer probieren mehr.
        let aggressionScore = (duel.attacker.aggression - 75.0) / 100.0

        // Je näher dran, desto besser die Chance.
        let proximity = max(0.0, 1.0 - duel.gap / attackRange)

        let raw = paceScore * 0.40
            + skillScore * 0.25
            + gripScore * 0.55
            + drsScore
            + aggressionScore * 0.15

        // Die Strecke entscheidet mit: 0.92 in Monaco lässt fast nichts übrig.
        let trackFactor = 1.0 - duel.circuit.overtakingDifficulty * 0.90

        return min(max(raw * proximity * trackFactor, 0.0), 0.85)
    }

    /// Endet ein misslungener Angriff in einer Berührung?
    ///
    /// Zwei aggressive Fahrer, die beide nicht nachgeben, fahren irgendwann ineinander.
    /// Die Zahlen sind bewusst klein: In einem Feld, in dem pro Runde ein Dutzend Autos
    /// in Schlagdistanz liegen, summieren sich schon wenige Promille zu ein bis zwei
    /// Berührungen pro Rennen — mehr wäre Autoscooter statt Formel 1.
    public static func contactProbability(_ duel: Duel) -> Double {
        let attackerRisk = duel.attacker.aggression / 100.0
        let defenderRisk = duel.defender.defending / 100.0
        let sloppiness = (100.0 - duel.attacker.consistency) / 100.0
        let wetFactor = 1.0 + duel.circuit.overtakingDifficulty * 0.5
        let raw = 0.0015 + attackerRisk * defenderRisk * 0.006 + sloppiness * 0.004
        return min(0.020, raw * wetFactor)
    }

    /// Ist der Angreifer schuld? Nur dann gibt es eine Strafe.
    ///
    /// Wer spät und wild anbremst, bekommt die fünf Sekunden. Wer sauber neben dem
    /// anderen liegt und trotzdem berührt wird, nicht — das ist dann ein Rennunfall.
    public static func attackerAtFaultProbability(_ duel: Duel) -> Double {
        let recklessness = duel.attacker.aggression / 100.0
        let control = duel.attacker.consistency / 100.0
        return min(0.9, max(0.15, recklessness * 0.9 - control * 0.3 + 0.25))
    }
}
