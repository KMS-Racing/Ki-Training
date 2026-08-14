import SwiftUI
import RaceEngine

/// Das Qualifying-Ergebnis vor dem Rennen.
///
/// Zeigt alle drei Abschnitte nebeneinander, damit man sieht, wer wann ausgeschieden ist.
struct QualifyingResultView: View {
    @EnvironmentObject private var seasonModel: SeasonViewModel
    @Environment(\.dismiss) private var dismiss
    let setup: WeekendSetup
    /// Wird gedrückt, um ins Rennen zu gehen.
    let onStartRace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(setup.qualifying.entries) { entry in
                        row(entry)
                    }
                }
                .padding(.horizontal, 16)
            }

            footer
        }
        .frame(minWidth: 660, minHeight: 620)
        .background(Theme.background)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("QUALIFYING — RUNDE \(setup.round.round)")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(Theme.dimText)
            Text(setup.round.name.uppercased())
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
            Text("\(setup.circuit.name) · \(setup.raceConfiguration.laps) Runden · "
                 + setup.raceConfiguration.startingWeather.displayName)
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            HStack(spacing: 0) {
                Text("POS").frame(width: 40, alignment: .leading)
                Text("FAHRER").frame(width: 150, alignment: .leading)
                Text("Q1").frame(width: 92, alignment: .trailing)
                Text("Q2").frame(width: 92, alignment: .trailing)
                Text("Q3").frame(width: 92, alignment: .trailing)
                Text("RAUS").frame(width: 56, alignment: .trailing)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.dimText)
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private func row(_ entry: QualifyingEntry) -> some View {
        HStack(spacing: 0) {
            Text("\(entry.position)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.position == 1 ? Theme.purple : Theme.text)
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(seasonModel.color(forDriver: entry.driverID))
                    .frame(width: 3, height: 16)
                Text(seasonModel.driver(entry.driverID)?.lastName ?? entry.driverID)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .frame(width: 150, alignment: .leading)

            time(entry.q1Time, highlight: entry.eliminatedIn == .q1)
            time(entry.q2Time, highlight: entry.eliminatedIn == .q2)
            time(entry.q3Time, highlight: entry.eliminatedIn == .q3)

            Text(entry.eliminatedIn == .q3 ? "Q3" : entry.eliminatedIn.displayName)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.eliminatedIn == .q3 ? Theme.green : Theme.dimText)
                .frame(width: 56, alignment: .trailing)

            if entry.position == 1 {
                Text("POLE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.purple)
                    .padding(.leading, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .background(entry.position == 1 ? Theme.purple.opacity(0.12)
                    : (entry.position <= 10 ? Color.white.opacity(0.04) : .clear))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func time(_ value: Double?, highlight: Bool) -> some View {
        Text(value.map { RaceControl.formatLapTime($0) } ?? "—")
            .font(.system(size: 12, weight: highlight ? .bold : .regular, design: .monospaced))
            .foregroundStyle(value == nil ? Theme.dimText.opacity(0.4) : Theme.text.opacity(0.9))
            .frame(width: 92, alignment: .trailing)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let pole = setup.qualifying.poleSitter,
               let driver = seasonModel.driver(pole),
               let time = setup.qualifying.poleTime {
                Text("POLE POSITION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                Text(driver.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.purple)
                Text(RaceControl.formatLapTime(time))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            Button("Abbrechen") { dismiss() }
            Button {
                onStartRace()
            } label: {
                Label("Rennen starten", systemImage: "flag.checkered")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cyan)
        }
        .padding(16)
    }
}
