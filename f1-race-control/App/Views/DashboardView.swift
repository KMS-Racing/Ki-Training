import SwiftUI
import RaceEngine

/// Die Hauptansicht — die Rennleitung.
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │ F1 RACE CONTROL   MONZA   LAP 34/53   GREEN  │
/// ├────────────┬──────────────────┬──────────────┤
/// │  TIMING    │    TRACK MAP     │ RACE CONTROL │
/// │  TOWER     │                  │              │
/// ├────────────┴──────────────────┴──────────────┤
/// │ WEATHER   TRACK 42°  AIR 24°  WIND  RAIN 10% │
/// └──────────────────────────────────────────────┘
/// ```
struct DashboardView: View {
    @EnvironmentObject private var model: RaceViewModel
    @State private var showResult = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let snapshot = model.snapshot {
                VStack(spacing: 10) {
                    HeaderView(snapshot: snapshot)

                    HStack(alignment: .top, spacing: 10) {
                        Panel(title: "TIMING TOWER") {
                            TimingTowerView(snapshot: snapshot)
                        }
                        .frame(minWidth: 380, idealWidth: 430)

                        VStack(spacing: 10) {
                            Panel(title: "TRACK MAP") {
                                TrackMapView(snapshot: snapshot)
                                    .padding(10)
                            }
                            Panel(title: "STRATEGY") {
                                StrategyView(snapshot: snapshot)
                            }
                            .frame(height: 170)
                        }

                        Panel(title: "RACE CONTROL") {
                            RaceControlFeedView(snapshot: snapshot)
                        }
                        .frame(minWidth: 300, idealWidth: 340)
                    }

                    WeatherBarView(weather: snapshot.weather)
                }
                .padding(12)
                .onChange(of: model.result != nil) { _, hasResult in
                    showResult = hasResult
                }
                .sheet(isPresented: $showResult) {
                    if let result = model.result {
                        RaceResultView(result: result)
                    }
                }
            } else {
                ProgressView("Rennen wird vorbereitet …")
                    .tint(.white)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Kopfzeile: Strecke, Runde, Flaggenstatus — plus die Bedienung.
struct HeaderView: View {
    @EnvironmentObject private var model: RaceViewModel
    let snapshot: RaceSnapshot

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("F1 RACE CONTROL")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                Text(snapshot.circuit.name.uppercased())
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            Text("LAP \(snapshot.lap) / \(snapshot.totalLaps)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)

            Spacer()

            // Flaggenstatus — mit Countdown, wenn die Freigabe bevorsteht.
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.color(for: snapshot.trackStatus))
                    .frame(width: 12, height: 12)
                Text(snapshot.trackStatus.displayName)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.color(for: snapshot.trackStatus))
                if let countdown = snapshot.neutralisationCountdown {
                    Text("\(countdown)")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.yellow.opacity(0.25)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.panel, in: Capsule())

            ControlBar()
        }
        .padding(.horizontal, 4)
    }
}

/// Die Knöpfe der Rennleitung.
struct ControlBar: View {
    @EnvironmentObject private var model: RaceViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.isRunning ? model.pause() : model.resume()
            } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
            }
            .help(model.isRunning ? "Pause" : "Weiter")

            Menu {
                Button("Virtual Safety Car") { model.deployVirtualSafetyCar() }
                Button("Safety Car") { model.deploySafetyCar() }
                Button("Red Flag", role: .destructive) { model.throwRedFlag() }
                Divider()
                Button("Rennen freigeben") { model.resumeRace() }
                Divider()
                Menu("Wetter") {
                    ForEach(WeatherState.allCases, id: \.self) { state in
                        Button(state.displayName) { model.changeWeather(to: state) }
                    }
                }
            } label: {
                Label("RACE DIRECTOR", systemImage: "flag.checkered")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Tempo der Simulation.
            HStack(spacing: 4) {
                Image(systemName: "speedometer").foregroundStyle(Theme.dimText)
                Slider(value: $model.speed, in: 1...300)
                    .frame(width: 110)
                Text("\(Int(model.speed))×")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                    .frame(width: 38, alignment: .leading)
            }
        }
        .buttonStyle(.bordered)
        .tint(Theme.cyan)
    }
}
