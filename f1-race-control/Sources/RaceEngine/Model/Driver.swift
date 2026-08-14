import Foundation

/// Ein Fahrer mit seinen Stärken.
///
/// Alle Werte gehen von 0 bis 100 und sind so gemeint, wie man es aus Rennspielen kennt:
/// 100 = Weltklasse, 80 = solides Mittelfeld. Aus diesen Zahlen entsteht später die
/// Rundenzeit — ein Fahrer mit `pace: 98` ist auf einer Runde ein paar Zehntel
/// schneller als einer mit `pace: 85`.
public struct Driver: Codable, Identifiable, Hashable, Sendable {
    /// Kürzel wie im echten Timing, z.B. `"VER"`.
    public let id: String
    public let name: String
    public let number: Int
    public let teamID: String

    /// Grundtempo auf einer freien Runde.
    public let pace: Double
    /// Wie gleichmäßig er trifft. Niedrig = mehr Streuung, mehr Fehler.
    public let consistency: Double
    /// Risikobereitschaft. Hoch = greift öfter an, baut aber auch öfter Mist.
    public let aggression: Double
    /// Wie gut er einen Angriff durchbringt.
    public let overtaking: Double
    /// Wie gut er eine Position verteidigt.
    public let defending: Double
    /// Tempo im Regen.
    public let wetPerformance: Double
    /// Wie schonend er mit den Reifen umgeht.
    public let tyreManagement: Double

    public init(
        id: String,
        name: String,
        number: Int,
        teamID: String,
        pace: Double,
        consistency: Double,
        aggression: Double,
        overtaking: Double,
        defending: Double,
        wetPerformance: Double,
        tyreManagement: Double
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.teamID = teamID
        self.pace = pace
        self.consistency = consistency
        self.aggression = aggression
        self.overtaking = overtaking
        self.defending = defending
        self.wetPerformance = wetPerformance
        self.tyreManagement = tyreManagement
    }

    /// Nachname in Großbuchstaben — so steht es im Timing Tower.
    public var lastName: String {
        let parts = name.split(separator: " ")
        return String(parts.last ?? "").uppercased()
    }
}
