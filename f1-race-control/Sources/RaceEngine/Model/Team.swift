import Foundation

/// Ein Rennstall.
///
/// Das Auto macht in der Formel 1 den größeren Teil der Rundenzeit aus — deshalb
/// wiegt `carPerformance` in der Rundenzeit-Formel schwerer als das Fahrer-Talent.
public struct Team: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Teamfarbe als Hex, z.B. `"#3671C6"`. Die UI macht daraus die Farbe im Timing Tower.
    public let colorHex: String
    /// Stärke des Autos (0…100).
    public let carPerformance: Double
    /// Standfestigkeit (0…100). Niedrig = öfter technischer Ausfall.
    public let reliability: Double
    /// Können der Boxencrew (0…100). Beeinflusst die Standzeit beim Reifenwechsel.
    public let pitCrewSkill: Double

    public init(
        id: String,
        name: String,
        colorHex: String,
        carPerformance: Double,
        reliability: Double,
        pitCrewSkill: Double
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.carPerformance = carPerformance
        self.reliability = reliability
        self.pitCrewSkill = pitCrewSkill
    }
}
