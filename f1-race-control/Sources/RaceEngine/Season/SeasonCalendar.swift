import Foundation

/// Ein Rennwochenende im Kalender.
public struct SeasonRound: Codable, Hashable, Sendable, Identifiable {
    /// Der wievielte Lauf der Saison (1-basiert).
    public let round: Int
    public let circuitID: String
    /// Wie das Rennen heißt, z.B. „Großer Preis von Japan".
    public let name: String

    public var id: Int { round }

    public init(round: Int, circuitID: String, name: String) {
        self.round = round
        self.circuitID = circuitID
        self.name = name
    }
}

/// Der Rennkalender.
///
/// Die Reihenfolge gibt den veröffentlichten Stand der Saison 2026 wieder. Sie steht
/// bewusst hier an einer Stelle und nicht verteilt im Code — wer sie ändern oder
/// eine eigene Saison zusammenstellen will, tauscht einfach diese Liste aus.
public enum SeasonCalendar {

    public static let year2026: [SeasonRound] = build([
        ("melbourne",   "Großer Preis von Australien"),
        ("shanghai",    "Großer Preis von China"),
        ("suzuka",      "Großer Preis von Japan"),
        ("bahrain",     "Großer Preis von Bahrain"),
        ("jeddah",      "Großer Preis von Saudi-Arabien"),
        ("miami",       "Großer Preis von Miami"),
        ("montreal",    "Großer Preis von Kanada"),
        ("monaco",      "Großer Preis von Monaco"),
        ("barcelona",   "Großer Preis von Spanien"),
        ("spielberg",   "Großer Preis von Österreich"),
        ("silverstone", "Großer Preis von Großbritannien"),
        ("spa",         "Großer Preis von Belgien"),
        ("budapest",    "Großer Preis von Ungarn"),
        ("zandvoort",   "Großer Preis der Niederlande"),
        ("monza",       "Großer Preis von Italien"),
        ("madrid",      "Großer Preis von Madrid"),
        ("baku",        "Großer Preis von Aserbaidschan"),
        ("singapore",   "Großer Preis von Singapur"),
        ("austin",      "Großer Preis der USA"),
        ("mexico",      "Großer Preis von Mexiko"),
        ("interlagos",  "Großer Preis von São Paulo"),
        ("lasvegas",    "Großer Preis von Las Vegas"),
        ("losail",      "Großer Preis von Katar"),
        ("yasmarina",   "Großer Preis von Abu Dhabi"),
    ])

    private static func build(_ entries: [(String, String)]) -> [SeasonRound] {
        return entries.enumerated().map { index, entry in
            SeasonRound(round: index + 1, circuitID: entry.0, name: entry.1)
        }
    }
}
