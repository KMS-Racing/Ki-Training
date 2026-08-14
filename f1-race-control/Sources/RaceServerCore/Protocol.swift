import Foundation
import RaceEngine

// =============================================================================
//  Das Protokoll zwischen Server und Clients
// -----------------------------------------------------------------------------
//  Alles JSON über eine WebSocket-Verbindung. Bewusst schlicht gehalten: ein
//  `type`-Feld sagt, worum es geht, der Rest hängt daran.
// =============================================================================

/// Was ein Client darf.
public enum ClientRole: String, Codable {
    /// Darf zuschauen.
    case spectator
    /// Darf die Rennleitung bedienen: VSC, Safety Car, Rote Flagge, Strafen, Wetter.
    case director
}

// MARK: - Server → Client

/// Einmal beim Verbinden: alles, was sich während des Rennens nicht ändert.
public struct WelcomeMessage: Codable {
    public let type = "welcome"
    public let role: ClientRole
    public let circuit: Circuit
    public let drivers: [DriverInfo]
    public let totalLaps: Int
    public let sessionName: String

    enum CodingKeys: String, CodingKey {
        case type, role, circuit, drivers, totalLaps, sessionName
    }
}

/// Stammdaten eines Fahrers — Name, Nummer, Teamfarbe.
public struct DriverInfo: Codable {
    public let id: String
    public let name: String
    public let lastName: String
    public let number: Int
    public let team: String
    public let color: String
}

/// Der laufende Rennstand. Geht mehrmals pro Sekunde raus.
///
/// Bewusst **ohne** die Streckenkarte: Die 160 Punkte des Streckenverlaufs stehen
/// schon in der Begrüßung. Würde man sie jedes Mal mitschicken, wäre die Nachricht
/// zehnmal so groß, ohne dass sich daran je etwas ändert.
public struct SnapshotMessage: Codable {
    public let type = "snapshot"
    public let lap: Int
    public let totalLaps: Int
    public let raceTime: Double
    public let status: String
    public let statusKind: String
    public let countdown: Int?
    public let justification: String?
    public let weather: WeatherConditions
    public let standings: [DriverState]
    public let messages: [RaceControlMessage]
    public let fastestLap: FastestLap?
    public let finished: Bool
    public let running: Bool
    public let speed: Double
    public let viewers: Int

    enum CodingKeys: String, CodingKey {
        case type, lap, totalLaps, raceTime, status, statusKind, countdown
        case justification, weather, standings, messages, fastestLap
        case finished, running, speed, viewers
    }
}

/// Rückmeldung auf einen Befehl — auch bei Ablehnung.
public struct NoticeMessage: Codable {
    public let type = "notice"
    public let ok: Bool
    public let message: String

    enum CodingKeys: String, CodingKey { case type, ok, message }
}

// MARK: - Client → Server

/// Ein Befehl der Rennleitung.
public struct CommandMessage: Codable {
    public let action: String
    /// Für Strafen.
    public let driverID: String?
    public let seconds: Double?
    /// Für den Wetterwechsel.
    public let state: String?
    /// Für das Tempo der Simulation.
    public let value: Double?
}

/// Kurzform des Streckenzustands für die Weboberfläche.
func statusKind(_ status: TrackStatus) -> String {
    switch status {
    case .green: return "green"
    case .yellow: return "yellow"
    case .virtualSafetyCar: return "vsc"
    case .safetyCar: return "safetyCar"
    case .redFlag: return "red"
    case .finished: return "finished"
    }
}

/// Zugriff auf die mitgelieferte Weboberfläche.
///
/// `Bundle.module` gibt es nur in dem Target, das die Ressource besitzt — deshalb
/// liegt der Zugriff hier in der Bibliothek und nicht in der ausführbaren Hülle.
public enum ServerResources {
    public static func dashboardHTML() -> String {
        if let url = Bundle.module.url(forResource: "dashboard", withExtension: "html"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return "<h1>dashboard.html fehlt</h1>"
    }
}
