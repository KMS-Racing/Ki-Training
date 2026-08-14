import Foundation

/// Der interne Zustand eines Autos während der Simulation.
///
/// Klasse statt Struct, weil die Engine sehr oft kleine Änderungen an einzelnen Autos
/// macht — mit Referenzen bleibt das übersichtlich. Nach außen gibt die Engine
/// ausschließlich das unveränderliche `DriverState` weiter.
final class CarSim {
    let driver: Driver
    let team: Team
    let gridPosition: Int
    /// Feste Nummer dieses Autos. Bestimmt seinen eigenen Zufallsstrom und ändert
    /// sich während des Rennens nie — sonst wäre die Reproduzierbarkeit dahin.
    let index: Int

    var position: Int
    var lapsCompleted: Int = 0
    var lapProgress: Double = 0
    /// Zeit, die in der laufenden Runde schon vergangen ist.
    var elapsedThisLap: Double = 0

    /// Rennzeit beim Überfahren der Ziellinie. `crossingTimes[i]` = Ende von Runde `i+1`.
    /// Damit lassen sich Abstände so berechnen, wie es die echte Zeitnahme macht.
    var crossingTimes: [Double] = []

    var lastLapTime: Double?
    var bestLapTime: Double?
    /// Zwischenzeiten der laufenden Runde (Stand bei den Sektorgrenzen).
    var sectorMarks: [Double] = []
    var lastSectors: [Double] = []

    var tyres: TyreSet
    var status: DriverStatus = .running
    var retirementReason: String?
    var pitStops: Int = 0
    var penaltySeconds: Double = 0
    var hasFastestLap: Bool = false

    // --- Boxenstopp ---
    /// Restzeit, die das Auto noch in der Boxengasse verbringt.
    var pitRemaining: Double = 0
    var pitCompound: TyreCompound = .medium

    // --- Zwischenstände fürs Rechnen ---
    var gapToLeader: Double = 0
    var interval: Double = 0
    var lapsDown: Int = 0
    /// Geschätzte Zeit für die laufende Runde — Grundlage für Abstände und Tempo.
    var currentLapEstimate: Double = 90
    /// Die Tagesform dieser einen Runde, einmal pro Runde gewürfelt.
    ///
    /// Absichtlich **nicht** in jedem Simulationsschritt neu: sonst würde das Auto
    /// zappeln, und die Zufallsfolge hinge daran, wie fein man die Schritte wählt —
    /// womit zwei Läufe mit gleichem Seed auseinanderliefen.
    var lapNoise: Double = 0
    /// Wurde die laufende Runde durch Box, Gelb oder VSC entwertet?
    /// Solche Runden zählen nicht für die schnellste Rennrunde.
    var lapCompromised: Bool = false
    /// Wie viel dieses Auto unter Safety Car schneller/langsamer fahren muss,
    /// damit sich das Feld zusammenschiebt.
    var bunchFactor: Double = 1.0
    var inDirtyAir: Bool = false
    /// In welcher Runde zuletzt ein Angriff gefahren wurde (max. einer pro Runde).
    var lastAttackLap: Int = -1
    /// Um wie viele Runden das Boxenfenster dieses Autos verschoben ist.
    /// Sorgt dafür, dass nicht alle in derselben Runde hereinkommen.
    var pitWindowOffset: Int = 0

    init(driver: Driver, team: Team, gridPosition: Int, index: Int, startingTyres: TyreSet) {
        self.driver = driver
        self.team = team
        self.gridPosition = gridPosition
        self.index = index
        self.position = gridPosition
        self.tyres = startingTyres
    }

    /// Gesamtfortschritt: volle Runden plus angefangene Runde.
    var raceProgress: Double {
        return Double(lapsCompleted) + lapProgress
    }

    var isActive: Bool {
        return status == .running || status == .inPitLane
    }

    /// Wann war dieses Auto bei einem bestimmten Streckenfortschritt?
    ///
    /// Das ist der Kern einer korrekten Abstandsberechnung. Statt „Weg mal Rundenzeit“
    /// zu schätzen, wird nachgeschlagen, **wann** das vordere Auto an genau der Stelle war,
    /// an der das hintere jetzt ist. Genau so misst die echte Zeitnahme auch.
    ///
    /// - Returns: Die Rennzeit, oder `nil`, wenn das Auto dort noch nicht war.
    func time(atProgress target: Double) -> Double? {
        guard target >= 0 else { return nil }
        let lapIndex = Int(target.rounded(.down))
        let fraction = target - Double(lapIndex)

        // Wann begann die Runde, in der dieser Punkt liegt?
        let lapStart: Double
        if lapIndex == 0 {
            lapStart = 0
        } else if lapIndex <= crossingTimes.count {
            lapStart = crossingTimes[lapIndex - 1]
        } else {
            return nil   // so weit ist dieses Auto noch nicht
        }

        // Liegt der Punkt in einer abgeschlossenen Runde, sind Anfang und Ende bekannt.
        if lapIndex < crossingTimes.count {
            let lapEnd = crossingTimes[lapIndex]
            return lapStart + fraction * (lapEnd - lapStart)
        }

        // Die Runde läuft noch. Hier **nicht** mit der geschätzten Rundenzeit
        // hochrechnen: Wenn sich das Tempo mitten in der Runde ändert — genau das
        // macht ein VSC —, käme ein Zeitpunkt heraus, der in der Zukunft liegt, und
        // alle Abstände fielen auf null. Stattdessen wird die **tatsächlich**
        // verstrichene Zeit dieser Runde auf den zurückgelegten Anteil verteilt.
        guard lapIndex == lapsCompleted, fraction <= lapProgress + 1e-9 else { return nil }
        guard lapProgress > 1e-9 else { return lapStart }
        return lapStart + (fraction / lapProgress) * elapsedThisLap
    }

    /// Momentaufnahme für die Außenwelt.
    func makeState() -> DriverState {
        return DriverState(
            driverID: driver.id,
            position: position,
            gridPosition: gridPosition,
            lapsCompleted: lapsCompleted,
            lapProgress: lapProgress,
            totalTime: crossingTimes.last ?? 0,
            lastLapTime: lastLapTime,
            bestLapTime: bestLapTime,
            lastSectors: lastSectors,
            tyres: tyres,
            status: status,
            retirementReason: retirementReason,
            pitStops: pitStops,
            gapToLeader: gapToLeader,
            interval: interval,
            lapsDown: lapsDown,
            penaltySeconds: penaltySeconds,
            hasFastestLap: hasFastestLap
        )
    }
}
