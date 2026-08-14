import Foundation

/// Fehler beim Laden der Stammdaten.
public enum DataLoaderError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case decodingFailed(String, String)

    public var description: String {
        switch self {
        case .resourceMissing(let name):
            return "Datei '\(name)' nicht im Paket gefunden."
        case .decodingFailed(let name, let reason):
            return "Datei '\(name)' konnte nicht gelesen werden: \(reason)"
        }
    }
}

/// Fahrer, Teams und Strecken zusammen.
public struct RaceData: Sendable {
    public let drivers: [Driver]
    public let teams: [Team]
    public let circuits: [Circuit]

    public init(drivers: [Driver], teams: [Team], circuits: [Circuit]) {
        self.drivers = drivers
        self.teams = teams
        self.circuits = circuits
    }

    public func circuit(id: String) -> Circuit? {
        return circuits.first { $0.id.lowercased() == id.lowercased() }
    }
}

/// Lädt die JSON-Stammdaten aus dem Paket.
///
/// Die Dateien liegen in `Sources/RaceEngine/Resources/` und werden von SwiftPM als
/// Ressourcen mit eingepackt. Deshalb funktioniert `Bundle.module` sowohl unter Linux
/// als auch in der App auf dem Mac — man muss keine Pfade von Hand angeben.
public enum DataLoader {
    public static func loadDrivers() throws -> [Driver] {
        return try load([Driver].self, from: "Drivers")
    }

    public static func loadTeams() throws -> [Team] {
        return try load([Team].self, from: "Teams")
    }

    public static func loadCircuits() throws -> [Circuit] {
        return try load([Circuit].self, from: "Circuits")
    }

    /// Alles auf einmal.
    public static func loadAll() throws -> RaceData {
        return RaceData(
            drivers: try loadDrivers(),
            teams: try loadTeams(),
            circuits: try loadCircuits()
        )
    }

    private static func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw DataLoaderError.resourceMissing("\(name).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DataLoaderError.decodingFailed("\(name).json", error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DataLoaderError.decodingFailed("\(name).json", "\(error)")
        }
    }
}
