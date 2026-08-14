import SwiftUI
import RaceEngine

/// Der Saisonkalender: was gefahren wurde und was als Nächstes kommt.
struct SeasonView: View {
    @EnvironmentObject private var seasonModel: SeasonViewModel
    @EnvironmentObject private var raceModel: RaceViewModel
    let data: RaceData
    /// Wird aufgerufen, wenn das Rennen live gestartet wurde.
    let onRaceStart: () -> Void

    @State private var showQualifying = false

    var body: some View {
        Group {
            if let season = seasonModel.season {
                content(season)
            } else {
                NewSeasonView(onCreate: { seed, length, ai in
                    seasonModel.startNewSeason(
                        seed: seed, raceLengthFactor: length, aiStrength: ai)
                })
            }
        }
        .navigationTitle("Saison")
        .sheet(isPresented: $showQualifying) {
            if let setup = seasonModel.pendingWeekend {
                QualifyingResultView(setup: setup) {
                    showQualifying = false
                    startRace(setup)
                }
            }
        }
    }

    private func content(_ season: Season) -> some View {
        VStack(spacing: 0) {
            header(season)
            Divider()
            List {
                ForEach(season.calendar) { round in
                    RoundRow(
                        round: round,
                        result: season.result(forRound: round.round),
                        isNext: round.round == season.nextRound?.round
                    )
                }
            }
        }
    }

    private func header(_ season: Season) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SAISON \(String(season.year))")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                Text("\(season.completedRounds) von \(season.calendar.count) Rennen · "
                     + "Seed \(String(season.seed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if season.isFinished {
                Label("Saison beendet", systemImage: "trophy.fill")
                    .foregroundStyle(Theme.yellow)
            } else {
                Button {
                    if seasonModel.prepareNextWeekend() != nil {
                        showQualifying = true
                    }
                } label: {
                    Label("Wochenende starten", systemImage: "flag.checkered")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    seasonModel.simulateNextWeekend()
                } label: {
                    Label("Überspringen", systemImage: "forward.fill")
                }
                .help("Das Wochenende im Hintergrund durchrechnen")
            }
        }
        .padding()
    }

    private func startRace(_ setup: WeekendSetup) {
        raceModel.start(configuration: setup.raceConfiguration)
        raceModel.onFinish = { result in
            seasonModel.record(result: result)
        }
        onRaceStart()
    }
}

/// Eine Zeile im Kalender.
private struct RoundRow: View {
    @EnvironmentObject private var seasonModel: SeasonViewModel
    let round: SeasonRound
    let result: RoundResult?
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(round.round)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)

            if let circuit = seasonModel.circuit(for: round) {
                CircuitThumbnail(circuit: circuit)
                    .frame(width: 44, height: 34)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(round.name).font(.headline)
                if let circuit = seasonModel.circuit(for: round) {
                    Text(circuit.name).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let result = result {
                VStack(alignment: .trailing, spacing: 3) {
                    resultLine("SIEGER", result.winner, Theme.green)
                    resultLine("POLE", result.poleSitter, Theme.cyan)
                }
            } else if isNext {
                Text("ALS NÄCHSTES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.yellow)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.yellow.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .opacity(result == nil && !isNext ? 0.55 : 1)
    }

    private func resultLine(_ label: String, _ driverID: String?, _ colour: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(driverID.flatMap { seasonModel.driver($0)?.lastName } ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(colour)
                .frame(width: 96, alignment: .leading)
        }
    }
}

/// Eine neue Saison einstellen.
struct NewSeasonView: View {
    let onCreate: (UInt64, Double, Double) -> Void

    @State private var seedText = "2026"
    @State private var length = 1.0
    @State private var aiStrength = 0.9

    var body: some View {
        Form {
            Section("NEUE SAISON") {
                Text("""
                Eine Meisterschaft über 24 Rennen. Jedes Wochenende beginnt mit einem \
                Qualifying (Q1/Q2/Q3), danach wird gefahren. Der Stand wird gespeichert \
                und bleibt erhalten, auch wenn du die App schließt.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("EINSTELLUNGEN") {
                TextField("Seed", text: $seedText)
                VStack(alignment: .leading) {
                    Text("Renndistanz: \(Int(length * 100)) %")
                    Slider(value: $length, in: 0.1...1.0)
                    Text("Kürzere Rennen gehen schneller, die Logik bleibt dieselbe.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("KI-Stärke: \(Int(aiStrength * 100)) %")
                    Slider(value: $aiStrength, in: 0.3...1.0)
                }
            }

            Section {
                Button {
                    onCreate(UInt64(seedText) ?? 2026, length, aiStrength)
                } label: {
                    Label("Saison starten", systemImage: "trophy")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }
}
