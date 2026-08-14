import Foundation

/// Was für eine Session gefahren wird.
public enum SessionType: String, Codable, CaseIterable, Sendable {
    case race
    case sprint
    case qualifying
    case practice

    public var displayName: String {
        switch self {
        case .race: return "RACE"
        case .sprint: return "SPRINT"
        case .qualifying: return "QUALIFYING"
        case .practice: return "PRACTICE"
        }
    }
}

/// Alles, was man vor dem Start einstellt.
public struct RaceConfiguration: Sendable {
    public var circuit: Circuit
    public var drivers: [Driver]
    public var teams: [Team]
    public var laps: Int
    /// Fahrer-IDs in Startaufstellung — Index 0 ist die Pole Position.
    public var startingGrid: [String]
    public var startingWeather: WeatherState
    /// Wie stark die KI-Gegner sind, 0…1. Niedrig = mehr Fehler und langsamer.
    public var aiStrength: Double
    /// Wie sprunghaft das Wetter ist, 0…1.
    public var weatherVariability: Double
    /// Gleicher Seed = gleiches Rennen.
    public var seed: UInt64
    public var sessionType: SessionType
    /// Soll die Engine nach einer roten Flagge selbst wieder freigeben?
    /// Im Einzelspieler ja; im Mehrspieler entscheidet das später der Race Director.
    public var autoResumeRedFlag: Bool

    public init(
        circuit: Circuit,
        drivers: [Driver],
        teams: [Team],
        laps: Int? = nil,
        startingGrid: [String]? = nil,
        startingWeather: WeatherState = .dry,
        aiStrength: Double = 0.85,
        weatherVariability: Double = 0.5,
        seed: UInt64 = 1,
        sessionType: SessionType = .race,
        autoResumeRedFlag: Bool = true
    ) {
        self.autoResumeRedFlag = autoResumeRedFlag
        self.circuit = circuit
        self.drivers = drivers
        self.teams = teams
        self.laps = laps ?? circuit.defaultLaps
        self.startingGrid = startingGrid ?? RaceConfiguration.gridByPace(drivers: drivers, teams: teams)
        self.startingWeather = startingWeather
        self.aiStrength = aiStrength
        self.weatherVariability = weatherVariability
        self.seed = seed
        self.sessionType = sessionType
    }

    /// Startaufstellung nach Stärke, wenn keine vorgegeben wurde.
    ///
    /// Kein echtes Qualifying, sondern die Reihenfolge, die man ohne Zufall erwarten würde —
    /// Auto und Fahrer zusammengerechnet.
    public static func gridByPace(drivers: [Driver], teams: [Team]) -> [String] {
        var teamByID: [String: Team] = [:]
        for team in teams { teamByID[team.id] = team }

        let ranked = drivers.sorted { lhs, rhs in
            let lhsCar = teamByID[lhs.teamID]?.carPerformance ?? 80
            let rhsCar = teamByID[rhs.teamID]?.carPerformance ?? 80
            let lhsScore = lhs.pace * 0.4 + lhsCar * 0.6
            let rhsScore = rhs.pace * 0.4 + rhsCar * 0.6
            if lhsScore == rhsScore { return lhs.id < rhs.id }   // stabile Reihenfolge
            return lhsScore > rhsScore
        }
        return ranked.map { $0.id }
    }

    /// Team eines Fahrers.
    public func team(for driver: Driver) -> Team? {
        return teams.first { $0.id == driver.teamID }
    }

    /// Fahrer per ID.
    public func driver(id: String) -> Driver? {
        return drivers.first { $0.id == id }
    }
}
