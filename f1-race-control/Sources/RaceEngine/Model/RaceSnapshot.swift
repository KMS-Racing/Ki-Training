import Foundation

/// Der komplette Rennstand zu einem Zeitpunkt — alles, was eine Anzeige braucht.
///
/// Das ist die einzige Schnittstelle zwischen Engine und Oberfläche. SwiftUI und das
/// Terminal-Werkzeug bekommen beide genau dieses Paket und zeichnen es nur noch.
/// Dadurch weiß die Rennlogik nichts über Knöpfe, Farben oder Bildschirme.
public struct RaceSnapshot: Sendable {
    public let circuit: Circuit
    public let sessionType: SessionType
    /// Aktuelle Runde des Führenden (1-basiert, wie auf der Anzeigetafel).
    public let lap: Int
    public let totalLaps: Int
    /// Vergangene Rennzeit in Sekunden.
    public let raceTime: Double
    public let trackStatus: TrackStatus
    /// Countdown bis zur Freigabe (5, 4, 3, 2, 1), sonst `nil`.
    public let neutralisationCountdown: Int?
    /// Warum die Rennleitung so entschieden hat.
    public let directorJustification: String?
    public let weather: WeatherConditions
    /// Alle Autos, sortiert nach Rennposition.
    public let standings: [DriverState]
    /// Meldungen der Rennleitung, neueste zuerst.
    public let messages: [RaceControlMessage]
    public let fastestLap: FastestLap?
    public let isFinished: Bool

    public init(
        circuit: Circuit,
        sessionType: SessionType,
        lap: Int,
        totalLaps: Int,
        raceTime: Double,
        trackStatus: TrackStatus,
        neutralisationCountdown: Int?,
        directorJustification: String?,
        weather: WeatherConditions,
        standings: [DriverState],
        messages: [RaceControlMessage],
        fastestLap: FastestLap?,
        isFinished: Bool
    ) {
        self.circuit = circuit
        self.sessionType = sessionType
        self.lap = lap
        self.totalLaps = totalLaps
        self.raceTime = raceTime
        self.trackStatus = trackStatus
        self.neutralisationCountdown = neutralisationCountdown
        self.directorJustification = directorJustification
        self.weather = weather
        self.standings = standings
        self.messages = messages
        self.fastestLap = fastestLap
        self.isFinished = isFinished
    }

    /// Die Autos in der Reihenfolge, in der sie auf der Strecke liegen.
    ///
    /// **Nicht** dasselbe wie `standings`: Wer überrundet wurde, fährt räumlich zwischen
    /// den Führenden, steht in der Wertung aber weit hinten. Die Track Map braucht diese
    /// Reihenfolge, der Timing Tower die andere.
    public var trackOrder: [DriverState] {
        return standings.filter { $0.isActive }.sorted { $0.lapProgress > $1.lapProgress }
    }
}

/// Die schnellste Runde der Session.
public struct FastestLap: Codable, Hashable, Sendable {
    public let driverID: String
    public let lap: Int
    public let time: Double

    public init(driverID: String, lap: Int, time: Double) {
        self.driverID = driverID
        self.lap = lap
        self.time = time
    }
}
