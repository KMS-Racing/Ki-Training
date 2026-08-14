import Foundation

/// Speichert und lädt den Saisonstand als JSON.
///
/// Das Verzeichnis ist ein Parameter mit sinnvollem Standardwert — dadurch können
/// Tests in ein temporäres Verzeichnis schreiben und fassen nie die echte Saison an.
public enum SeasonStore {

    public static let fileName = "season.json"

    /// Wo die Saison normalerweise liegt.
    ///
    /// | System | Ort |
    /// |---|---|
    /// | macOS / iPadOS | `~/Library/Application Support/F1RaceControl/` |
    /// | Linux | `~/.f1-race-control/` |
    public static func defaultDirectory() -> URL {
        #if canImport(Darwin)
        if let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            return support.appendingPathComponent("F1RaceControl", isDirectory: true)
        }
        #endif

        // Nur der Notnagel, falls oben nichts kam.
        #if os(macOS) || os(Linux)
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".f1-race-control", isDirectory: true)
        #else
        // `homeDirectoryForCurrentUser` gibt es auf iOS und iPadOS **nicht** — eine App
        // hat dort kein Heimatverzeichnis eines Benutzerkontos, sondern eine Sandbox.
        // Deren Wurzel liefert `NSHomeDirectory()`.
        //
        // Der Compiler prüft auch Zweige, die nie laufen: Auf dem iPad greift immer
        // schon der Abschnitt darüber, trotzdem hat diese eine Zeile den ganzen
        // iPad-Bau scheitern lassen. Gefunden hat das erst `xcodebuild` in der CI.
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/F1RaceControl",
                                    isDirectory: true)
        #endif
    }

    public static func fileURL(in directory: URL? = nil) -> URL {
        return (directory ?? defaultDirectory()).appendingPathComponent(fileName)
    }

    /// Saison sichern.
    public static func save(_ season: Season, in directory: URL? = nil) throws {
        let folder = directory ?? defaultDirectory()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(season)
        try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    /// Saison laden. Gibt `nil` zurück, wenn noch keine angelegt wurde.
    public static func load(in directory: URL? = nil) throws -> Season? {
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Season.self, from: data)
    }

    /// Gespeicherte Saison löschen.
    public static func delete(in directory: URL? = nil) throws {
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public static func exists(in directory: URL? = nil) -> Bool {
        return FileManager.default.fileExists(atPath: fileURL(in: directory).path)
    }
}
