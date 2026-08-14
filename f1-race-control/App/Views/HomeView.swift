import SwiftUI
import RaceEngine

/// Der Startbildschirm.
///
/// ```
/// Home
/// ├── Saison ── Kalender · Meisterschaft · Statistik
/// ├── Neues Rennen
/// ├── Rennen fortsetzen
/// ├── Fahrer · Teams · Strecken
/// └── Einstellungen
/// ```
struct HomeView: View {
    @EnvironmentObject private var model: RaceViewModel
    @EnvironmentObject private var seasonModel: SeasonViewModel
    @State private var data: RaceData?
    @State private var loadError: String?
    @State private var selection: Destination? = .newRace

    enum Destination: Hashable {
        case season, standings, stats
        case newRace, race, drivers, teams, circuits, settings
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("SAISON") {
                    Label("Kalender", systemImage: "calendar").tag(Destination.season)
                    Label("Meisterschaft", systemImage: "trophy").tag(Destination.standings)
                    Label("Statistik", systemImage: "chart.bar").tag(Destination.stats)
                }
                Section("EINZELRENNEN") {
                    Label("Neues Rennen", systemImage: "flag.checkered")
                        .tag(Destination.newRace)
                    Label("Rennen fortsetzen", systemImage: "play.circle")
                        .tag(Destination.race)
                        .disabled(model.snapshot == nil)
                }
                Section("DATEN") {
                    Label("Fahrer", systemImage: "person.3").tag(Destination.drivers)
                    Label("Teams", systemImage: "car.2").tag(Destination.teams)
                    Label("Strecken", systemImage: "map").tag(Destination.circuits)
                }
                Section {
                    Label("Einstellungen", systemImage: "gearshape").tag(Destination.settings)
                }
            }
            .navigationTitle("F1 Race Control")
            #if os(macOS)
            .frame(minWidth: 210)
            #endif
        } detail: {
            detailView
        }
        .task { load() }
    }

    @ViewBuilder
    private var detailView: some View {
        if let error = loadError {
            ContentUnavailableView("Stammdaten fehlen", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let data = data {
            switch selection {
            case .season:
                SeasonView(data: data) { selection = .race }
            case .standings:
                StandingsView()
            case .stats:
                SeasonStatsView()
            case .newRace, .none:
                NewRaceView(data: data) { selection = .race }
            case .race:
                DashboardView()
            case .drivers:
                DriverListView(data: data)
            case .teams:
                TeamListView(data: data)
            case .circuits:
                CircuitListView(data: data)
            case .settings:
                SettingsView()
            }
        } else {
            ProgressView("Lade Stammdaten …")
        }
    }

    private func load() {
        do {
            let loaded = try DataLoader.loadAll()
            data = loaded
            seasonModel.load(data: loaded)
        } catch {
            loadError = "\(error)"
        }
    }
}

/// Rennen einstellen und starten.
struct NewRaceView: View {
    @EnvironmentObject private var model: RaceViewModel
    let data: RaceData
    /// Wird aufgerufen, sobald das Rennen läuft — die Home-Ansicht schaltet dann um.
    let onStart: () -> Void

    @State private var circuitID: String = "monza"
    @State private var laps: Double = 0          // 0 = Renndistanz der Strecke
    @State private var weather: WeatherState = .dry
    @State private var aiStrength: Double = 0.9
    @State private var variability: Double = 0.5
    @State private var seedText: String = "42"

    private var circuit: Circuit? {
        return data.circuits.first { $0.id == circuitID }
    }

    var body: some View {
        Form {
            Section("STRECKE") {
                Picker("Rennstrecke", selection: $circuitID) {
                    ForEach(data.circuits) { circuit in
                        Text("\(circuit.name) — \(circuit.country)").tag(circuit.id)
                    }
                }
                if let circuit = circuit {
                    LabeledContent("Länge", value: String(format: "%.3f km", circuit.lengthKm))
                    LabeledContent("Renndistanz", value: "\(circuit.defaultLaps) Runden")
                    LabeledContent("Überholen",
                                   value: overtakingDescription(circuit.overtakingDifficulty))
                }
            }

            Section("RENNEN") {
                VStack(alignment: .leading) {
                    Text(laps < 1
                         ? "Rundenzahl: Renndistanz (\(circuit?.defaultLaps ?? 0))"
                         : "Rundenzahl: \(Int(laps))")
                    Slider(value: $laps, in: 0...80, step: 1)
                }
                Picker("Startwetter", selection: $weather) {
                    ForEach(WeatherState.allCases, id: \.self) { state in
                        Text(state.displayName).tag(state)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Wetterumschwünge: \(Int(variability * 100)) %")
                    Slider(value: $variability, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text("KI-Stärke: \(Int(aiStrength * 100)) %")
                    Slider(value: $aiStrength, in: 0.3...1.0)
                }
            }

            Section("ZUFALL") {
                TextField("Seed", text: $seedText)
                Text("Derselbe Seed ergibt exakt dasselbe Rennen — praktisch zum Vergleichen und Nacherzählen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    startRace()
                } label: {
                    Label("Rennen starten", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(circuit == nil)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Neues Rennen")
    }

    private func startRace() {
        guard let circuit = circuit else { return }
        let configuration = RaceConfiguration(
            circuit: circuit,
            drivers: data.drivers,
            teams: data.teams,
            laps: laps < 1 ? nil : Int(laps),
            startingWeather: weather,
            aiStrength: aiStrength,
            weatherVariability: variability,
            seed: UInt64(seedText) ?? 42
        )
        model.start(configuration: configuration)
        onStart()
    }

    private func overtakingDescription(_ difficulty: Double) -> String {
        switch difficulty {
        case ..<0.25: return "sehr leicht"
        case ..<0.45: return "machbar"
        case ..<0.70: return "schwer"
        default: return "fast unmöglich"
        }
    }
}
