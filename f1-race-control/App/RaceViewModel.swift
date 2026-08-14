import Foundation
import SwiftUI
import RaceEngine

/// Bindeglied zwischen Engine und Oberfläche.
///
/// Bewusst die **einzige** Stelle in `App/`, die die Engine anfasst. Alle Views bekommen
/// nur den fertigen `RaceSnapshot` und zeichnen ihn — sie rechnen nichts selbst.
/// Dadurch bleibt die Rennlogik dort, wo sie getestet ist.
@MainActor
final class RaceViewModel: ObservableObject {

    @Published private(set) var snapshot: RaceSnapshot?
    @Published private(set) var result: RaceResult?
    @Published private(set) var isRunning = false
    /// Wie viele Rennsekunden pro echter Sekunde vergehen.
    @Published var speed: Double = 30

    /// Wird einmal aufgerufen, sobald das Rennen im Ziel ist.
    /// Die Saison trägt darüber das Ergebnis in die Meisterschaft ein.
    var onFinish: ((RaceResult) -> Void)?

    private(set) var engine: RaceEngine?
    private var timer: Timer?
    private(set) var driversByID: [String: Driver] = [:]
    private(set) var teamsByID: [String: Team] = [:]

    /// Wie oft die Anzeige neu gezeichnet wird.
    private let frameInterval: Double = 1.0 / 30.0

    // MARK: - Rennen aufsetzen

    func start(configuration: RaceConfiguration) {
        stop()

        driversByID = Dictionary(uniqueKeysWithValues: configuration.drivers.map { ($0.id, $0) })
        teamsByID = Dictionary(uniqueKeysWithValues: configuration.teams.map { ($0.id, $0) })

        let engine = RaceEngine(configuration: configuration)
        self.engine = engine
        self.result = nil
        self.snapshot = engine.snapshot()
        resume()
    }

    func resume() {
        guard let engine = engine, !engine.isFinished else { return }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            // Der Timer feuert auf der Hauptschleife, also sind wir hier bereits auf
            // dem MainActor — das muss man Swift nur sagen.
            //
            // Vorher stand hier `Task { @MainActor in self?.tick() }`. Das war gleich
            // zweimal falsch: Es erfasst `self?` über die Nebenläufigkeitsgrenze
            // (der Compiler auf dem Mac lehnt es ab), und es hätte dreißigmal pro
            // Sekunde eine Aufgabe erzeugt, nur um auf den Thread zu wechseln,
            // auf dem wir längst sind.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        pause()
        engine = nil
        snapshot = nil
        result = nil
    }

    private func tick() {
        guard let engine = engine else { return }
        engine.advance(speed * frameInterval)
        snapshot = engine.snapshot()

        if engine.isFinished {
            let finished = engine.result()
            result = finished
            pause()
            if let finished = finished {
                // Nur einmal melden — danach abhängen, sonst käme es bei jedem
                // weiteren Tick erneut und das Rennen stünde mehrfach in der Saison.
                let callback = onFinish
                onFinish = nil
                callback?(finished)
            }
        }
    }

    // MARK: - Rennleitung von Hand (die Race-Control-Konsole)

    func deployVirtualSafetyCar() {
        engine?.forceTrackStatus(
            .virtualSafetyCar(phase: .deploying), clearance: 90,
            reason: "Virtual Safety Car deployed by the Race Director.")
        refresh()
    }

    func deploySafetyCar() {
        engine?.forceTrackStatus(
            .safetyCar(phase: .deploying), clearance: 160,
            reason: "Safety Car deployed by the Race Director.")
        refresh()
    }

    func throwRedFlag() {
        engine?.forceTrackStatus(
            .redFlag, clearance: 180,
            reason: "Red flag shown by the Race Director.")
        refresh()
    }

    func resumeRace() {
        engine?.resumeFromRedFlag()
        refresh()
    }

    func applyPenalty(to driverID: String, seconds: Double = 5) {
        engine?.applyPenalty(driverID: driverID, seconds: seconds, reason: "RACE DIRECTOR DECISION")
        refresh()
    }

    func changeWeather(to state: WeatherState) {
        engine?.forceWeather(state)
        refresh()
    }

    private func refresh() {
        snapshot = engine?.snapshot()
    }

    // MARK: - Hilfen für die Views

    func driver(_ id: String) -> Driver? { driversByID[id] }

    func team(for driverID: String) -> Team? {
        guard let driver = driversByID[driverID] else { return nil }
        return teamsByID[driver.teamID]
    }

    /// Teamfarbe als SwiftUI-Farbe.
    func color(for driverID: String) -> Color {
        guard let hex = team(for: driverID)?.colorHex else { return .gray }
        return Color(hex: hex)
    }
}

extension Color {
    /// Farbe aus einem Hex-String wie `"#3671C6"`.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
