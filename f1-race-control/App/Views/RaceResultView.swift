import SwiftUI
import RaceEngine

/// Das Schlussklassement nach der Zielflagge.
struct RaceResultView: View {
    @EnvironmentObject private var model: RaceViewModel
    @Environment(\.dismiss) private var dismiss
    let result: RaceResult

    private var winnerTime: Double { result.winner?.classifiedTime ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("RACE FINISHED")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                Text(result.circuitName.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .padding(.vertical, 20)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(result.entries) { entry in
                        resultRow(entry)
                    }
                }
                .padding(.horizontal, 16)
            }

            if let fastest = result.fastestLap {
                HStack(spacing: 8) {
                    Text("FASTEST LAP")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                    Text(model.driver(fastest.driverID)?.lastName ?? fastest.driverID)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.purple)
                    Text(RaceControl.formatLapTime(fastest.time))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text("(Runde \(fastest.lap))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }
                .padding(.vertical, 14)
            }

            Button("Schließen") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyan)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 620, minHeight: 560)
        .background(Theme.background)
    }

    private func resultRow(_ entry: RaceResultEntry) -> some View {
        HStack(spacing: 0) {
            Text("\(entry.position)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .frame(width: 36, alignment: .leading)
                .foregroundStyle(entry.position <= 3 ? Theme.yellow : Theme.text)

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(model.color(for: entry.driverID))
                    .frame(width: 3, height: 18)
                Text(model.driver(entry.driverID)?.name ?? entry.driverID)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.status == .retired ? Theme.dimText : Theme.text)
            }
            .frame(width: 190, alignment: .leading)

            Text(timeText(entry))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(entry.status == .retired ? Theme.red : Theme.text.opacity(0.85))
                .frame(width: 150, alignment: .trailing)

            Text("\(entry.pitStops) PIT")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.dimText)
                .frame(width: 60, alignment: .trailing)

            if entry.penaltySeconds > 0 {
                Text("+\(Int(entry.penaltySeconds))s")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.purple)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Spacer().frame(width: 44)
            }

            Text(entry.points > 0 ? "\(entry.points)" : "—")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.points > 0 ? Theme.green : Theme.dimText)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(entry.position <= 3 ? Color.white.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func timeText(_ entry: RaceResultEntry) -> String {
        if entry.status == .retired {
            return "DNF — \(entry.retirementReason ?? "")"
        }
        if entry.position == 1 {
            return RaceControl.formatLapTime(entry.classifiedTime)
        }
        if entry.lapsCompleted < result.totalLaps {
            return "+\(result.totalLaps - entry.lapsCompleted) LAP"
        }
        return RaceControl.formatGap(entry.classifiedTime - winnerTime)
    }
}
