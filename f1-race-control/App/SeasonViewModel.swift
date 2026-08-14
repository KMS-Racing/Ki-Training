import Foundation
import SwiftUI
import RaceEngine

/// Hält den Saisonstand und startet die Wochenenden.
///
/// Wie beim Rennen gilt: Hier wird nichts gerechnet. Die Meisterschaft kommt aus
/// `Championship`, das Qualifying aus `QualifyingSimulator`, das Rennen aus
/// `RaceEngine`. Dieses Objekt lädt, speichert und reicht weiter.
@MainActor
final class SeasonViewModel: ObservableObject {

    @Published private(set) var season: Season?
    /// Das vorbereitete Wochenende, sobald das Qualifying gefahren ist.
    @Published private(set) var pendingWeekend: WeekendSetup?
    @Published private(set) var errorMessage: String?

    private var data: RaceData?

    // MARK: - Laden und Anlegen

    func load(data: RaceData) {
        self.data = data
        do {
            season = try SeasonStore.load()
        } catch {
            errorMessage = "Gespeicherte Saison konnte nicht gelesen werden: \(error)"
            season = nil
        }
    }

    func startNewSeason(seed: UInt64, raceLengthFactor: Double, aiStrength: Double) {
        let fresh = Season(
            year: 2026,
            seed: seed,
            aiStrength: aiStrength,
            raceLengthFactor: raceLengthFactor
        )
        season = fresh
        pendingWeekend = nil
        save()
    }

    func deleteSeason() {
        try? SeasonStore.delete()
        season = nil
        pendingWeekend = nil
    }

    private func save() {
        guard let season = season else { return }
        do {
            try SeasonStore.save(season)
        } catch {
            errorMessage = "Saison konnte nicht gespeichert werden: \(error)"
        }
    }

    // MARK: - Ein Wochenende

    /// Qualifying fahren und das Rennen vorbereiten.
    @discardableResult
    func prepareNextWeekend() -> WeekendSetup? {
        guard let season = season, let data = data else { return nil }
        do {
            let setup = try SeasonEngine.prepareNextWeekend(season: season, data: data)
            pendingWeekend = setup
            return setup
        } catch {
            errorMessage = "\(error)"
            return nil
        }
    }

    /// Das gefahrene Rennen eintragen.
    func record(result: RaceResult) {
        guard var current = season, let setup = pendingWeekend else { return }
        SeasonEngine.record(race: result, setup: setup, into: &current)
        season = current
        pendingWeekend = nil
        save()
    }

    /// Wochenende ohne Zuschauen durchrechnen.
    func simulateNextWeekend() {
        guard var current = season, let data = data else { return }
        do {
            try SeasonEngine.simulateNextWeekend(season: &current, data: data)
            season = current
            pendingWeekend = nil
            save()
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - Auswertung

    var driverStandings: [ChampionshipEntry] {
        guard let season = season, let data = data else { return [] }
        return Championship.drivers(from: season.results, drivers: data.drivers)
    }

    var constructorStandings: [ConstructorEntry] {
        guard let season = season, let data = data else { return [] }
        return Championship.constructors(
            from: season.results, drivers: data.drivers, teams: data.teams)
    }

    func circuit(for round: SeasonRound) -> Circuit? {
        return data?.circuit(id: round.circuitID)
    }

    func driver(_ id: String) -> Driver? {
        return data?.drivers.first { $0.id == id }
    }

    func team(forDriver id: String) -> Team? {
        guard let driver = driver(id) else { return nil }
        return data?.teams.first { $0.id == driver.teamID }
    }

    func team(_ id: String) -> Team? {
        return data?.teams.first { $0.id == id }
    }

    func color(forDriver id: String) -> Color {
        guard let hex = team(forDriver: id)?.colorHex else { return .gray }
        return Color(hex: hex)
    }

    func color(forTeam id: String) -> Color {
        guard let hex = team(id)?.colorHex else { return .gray }
        return Color(hex: hex)
    }
}
