import Foundation

/// Die drei Abschnitte des Qualifyings.
public enum QualifyingSegment: String, Codable, CaseIterable, Sendable {
    case q1
    case q2
    case q3

    public var displayName: String {
        return rawValue.uppercased()
    }

    /// Wie viel schneller die Strecke in diesem Abschnitt schon ist.
    ///
    /// Über eine Session legen die Autos Gummi auf den Asphalt, und die Strecke wird
    /// von Abschnitt zu Abschnitt schneller. Deshalb fallen die Bestzeiten in Q3.
    public var trackEvolution: Double {
        switch self {
        case .q1: return 1.000
        case .q2: return 0.997
        case .q3: return 0.994
        }
    }
}

/// Ein Fahrer im Qualifying-Ergebnis.
public struct QualifyingEntry: Codable, Hashable, Sendable, Identifiable {
    public let driverID: String
    public var id: String { driverID }

    /// Der erreichte Startplatz (1 = Pole).
    public let position: Int
    /// Beste Zeit im jeweiligen Abschnitt — `nil`, wenn er dort nicht mehr dabei war.
    public let q1Time: Double?
    public let q2Time: Double?
    public let q3Time: Double?
    /// In welchem Abschnitt er ausgeschieden ist. `.q3` heißt: bis ins Finale gekommen.
    public let eliminatedIn: QualifyingSegment

    public init(
        driverID: String,
        position: Int,
        q1Time: Double?,
        q2Time: Double?,
        q3Time: Double?,
        eliminatedIn: QualifyingSegment
    ) {
        self.driverID = driverID
        self.position = position
        self.q1Time = q1Time
        self.q2Time = q2Time
        self.q3Time = q3Time
        self.eliminatedIn = eliminatedIn
    }

    /// Die schnellste Zeit, die dieser Fahrer überhaupt gefahren ist.
    public var bestTime: Double? {
        let all = [q1Time, q2Time, q3Time].compactMap { $0 }
        return all.min()
    }
}

/// Das Ergebnis eines Qualifyings.
public struct QualifyingResult: Codable, Sendable {
    public let circuitID: String
    /// Nach Startplatz sortiert.
    public let entries: [QualifyingEntry]

    public init(circuitID: String, entries: [QualifyingEntry]) {
        self.circuitID = circuitID
        self.entries = entries
    }

    /// Die Startaufstellung — geht direkt in `RaceConfiguration(startingGrid:)`.
    public var grid: [String] {
        return entries.map { $0.driverID }
    }

    public var poleSitter: String? {
        return entries.first?.driverID
    }

    public var poleTime: Double? {
        return entries.first?.bestTime
    }

    /// Alle Fahrer, die in einem bestimmten Abschnitt ausgeschieden sind.
    public func eliminated(in segment: QualifyingSegment) -> [QualifyingEntry] {
        return entries.filter { $0.eliminatedIn == segment }
    }
}

/// Rechnet ein komplettes Qualifying.
///
/// Kein zweites Rennsystem mit Uhr und Boxenausfahrt: Jeder Fahrer bekommt pro
/// Abschnitt eine gewertete Runde, danach scheiden die Langsamsten aus.
///
/// ```
/// Q1   alle       → die Langsamsten scheiden aus → hintere Startplätze
/// Q2   der Rest   → dasselbe nochmal             → mittlere Startplätze
/// Q3   die Top 10 → Reihenfolge = Startplätze 1–10, Schnellster hat die Pole
/// ```
///
/// Die Rundenzeit kommt aus demselben `LapTimeModel` wie im Rennen — nur mit leerem
/// Tank, freier Strecke und frischen Reifen. Es gibt bewusst **keine** zweite
/// Zeitformel, sonst könnten Quali- und Renntempo auseinanderlaufen.
public enum QualifyingSimulator {

    /// So viele Fahrer erreichen den letzten Abschnitt.
    public static let finalSegmentSize = 10

    /// Wie stark die Qualizeiten streuen — als Anteil der Rennstreuung.
    ///
    /// Kleiner als 1, und das ist kein Versehen: Eine Qualirunde ist eine freie Runde
    /// mit leerem Tank auf frischen Reifen. Alles, was eine Rennrunde unberechenbar
    /// macht — Verkehr, abbauende Reifen, Spritlast, Dirty Air —, fällt hier weg.
    ///
    /// Der Wert ist ein Kompromiss, der zweimal falsch war: Zu klein, und in allen
    /// 24 Rennen steht dieselbe Aufstellung. Zu groß (2.2 war der erste Versuch), und
    /// die Streuung überdeckt die Autos komplett — dann holt ein Cadillac die Pole und
    /// ein Ferrari fliegt in Q1 raus. Bei 0.8 liegen die Spitzenteams so eng
    /// beieinander, dass die Reihenfolge vorn jedes Wochenende wechselt, während die
    /// Rangordnung über die Saison trotzdem stimmt.
    public static let qualifyingVariationFactor: Double = 0.8

    public static func run(
        circuit: Circuit,
        drivers: [Driver],
        teams: [Team],
        weather: WeatherConditions = WeatherConditions(),
        aiStrength: Double = 0.9,
        seed: UInt64
    ) -> QualifyingResult {

        var teamByID: [String: Team] = [:]
        for team in teams { teamByID[team.id] = team }

        // Nur Fahrer, deren Team es wirklich gibt.
        let field = drivers.filter { teamByID[$0.teamID] != nil }
        guard !field.isEmpty else {
            return QualifyingResult(circuitID: circuit.id, entries: [])
        }

        var random = RandomSource(masterSeed: seed)

        // Feste Nummer je Fahrer → eigener Zufallsstrom, wie im Rennen.
        var indexOf: [String: Int] = [:]
        for (index, driver) in field.enumerated() { indexOf[driver.id] = index }

        let (q1Eliminations, q2Eliminations) = eliminationCounts(fieldSize: field.count)

        var q1Times: [String: Double] = [:]
        var q2Times: [String: Double] = [:]
        var q3Times: [String: Double] = [:]

        /// Einen Abschnitt fahren: Zeiten setzen, langsamste `eliminations` aussortieren.
        /// - Returns: (weiter dabei, ausgeschieden — Langsamster zuletzt)
        func runSegment(
            _ segment: QualifyingSegment,
            participants: [Driver],
            eliminations: Int,
            store: inout [String: Double]
        ) -> (advancing: [Driver], eliminated: [Driver]) {

            for driver in participants {
                guard let team = teamByID[driver.teamID] else { continue }
                let actor = indexOf[driver.id] ?? 0
                let time = random.with(.qualifying, actor: actor) { rng in
                    lapTime(
                        driver: driver, team: team, circuit: circuit,
                        weather: weather, aiStrength: aiStrength,
                        segment: segment, random: &rng
                    )
                }
                store[driver.id] = time
            }

            let ranked = participants.sorted { lhs, rhs in
                let lhsTime = store[lhs.id] ?? .greatestFiniteMagnitude
                let rhsTime = store[rhs.id] ?? .greatestFiniteMagnitude
                if lhsTime != rhsTime { return lhsTime < rhsTime }
                return lhs.id < rhs.id      // stabil bei exakter Gleichheit
            }

            guard eliminations > 0, eliminations < ranked.count else {
                return (ranked, [])
            }
            let cut = ranked.count - eliminations
            return (Array(ranked[..<cut]), Array(ranked[cut...]))
        }

        // --- Q1 ---
        let (afterQ1, outInQ1) = runSegment(
            .q1, participants: field, eliminations: q1Eliminations, store: &q1Times)

        // --- Q2 ---
        let (afterQ2, outInQ2) = runSegment(
            .q2, participants: afterQ1, eliminations: q2Eliminations, store: &q2Times)

        // --- Q3 ---
        let (finalOrder, _) = runSegment(
            .q3, participants: afterQ2, eliminations: 0, store: &q3Times)

        // Startplätze vergeben: Q3 vorn, dann die in Q2 Ausgeschiedenen, dann Q1.
        var entries: [QualifyingEntry] = []
        var position = 1

        func append(_ drivers: [Driver], eliminatedIn segment: QualifyingSegment) {
            for driver in drivers {
                entries.append(QualifyingEntry(
                    driverID: driver.id,
                    position: position,
                    q1Time: q1Times[driver.id],
                    q2Time: q2Times[driver.id],
                    q3Time: q3Times[driver.id],
                    eliminatedIn: segment
                ))
                position += 1
            }
        }

        append(finalOrder, eliminatedIn: .q3)
        append(outInQ2, eliminatedIn: .q2)
        append(outInQ1, eliminatedIn: .q1)

        return QualifyingResult(circuitID: circuit.id, entries: entries)
    }

    /// Wie viele in Q1 und in Q2 ausscheiden.
    ///
    /// Wird aus der Feldgröße gerechnet, damit es auch bei 20 oder 24 Autos stimmt:
    /// Der letzte Abschnitt hat immer 10 Fahrer, der Rest wird gleichmäßig aufgeteilt.
    public static func eliminationCounts(fieldSize: Int) -> (q1: Int, q2: Int) {
        let surplus = fieldSize - finalSegmentSize
        guard surplus > 0 else { return (0, 0) }
        let q1 = (surplus + 1) / 2
        return (q1, surplus - q1)
    }

    /// Eine gewertete Qualirunde.
    static func lapTime(
        driver: Driver,
        team: Team,
        circuit: Circuit,
        weather: WeatherConditions,
        aiStrength: Double,
        segment: QualifyingSegment,
        random: inout SeededRandom
    ) -> Double {
        let compound = TyreCompound.best(forWetness: weather.trackWetness)
        let input = LapTimeModel.Input(
            driver: driver,
            team: team,
            circuit: circuit,
            tyres: TyreSet.fresh(compound),
            weather: weather,
            trackStatus: .green,
            lapsRemaining: 0,        // Quali-Trimm: praktisch leerer Tank
            inDirtyAir: false,       // freie Runde
            aiStrength: aiStrength
        )

        let base = LapTimeModel.deterministicLapTime(input) * segment.trackEvolution
        let spread = LapTimeModel.variation(input) * qualifyingVariationFactor
        let noise = random.gaussian(mean: 0, standardDeviation: spread)

        // Nach unten begrenzen — schneller als das theoretische Optimum geht nicht.
        return max(base * 0.97, base + noise)
    }
}
