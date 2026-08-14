import SwiftUI
import RaceEngine

/// Die Meldungen der Rennleitung, neueste oben.
///
/// ```
/// LAP 18   VSC DEPLOYED
/// LAP 22   GREEN FLAG
/// LAP 31   CAR 44 (HAM) — 5 SECOND PENALTY
/// ```
struct RaceControlFeedView: View {
    let snapshot: RaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Die Begründung der letzten Anordnung — das ist die „Race Director AI“,
            // die erklärt, warum sie so entschieden hat.
            if let justification = snapshot.directorJustification,
               snapshot.trackStatus.isNeutralised || snapshot.trackStatus == .redFlag {
                VStack(alignment: .leading, spacing: 4) {
                    Label("RACE DIRECTOR", systemImage: "brain")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.yellow)
                    Text(justification)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.yellow.opacity(0.10))

                Divider().overlay(Theme.panelBorder)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.messages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct MessageRow: View {
    let message: RaceControlMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(colour)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("LAP \(message.lap)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                    Text(message.headline)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(colour)
                }
                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colour: Color {
        switch message.category {
        case .flag: return Theme.yellow
        case .incident: return Theme.red
        case .penalty: return Theme.purple
        case .weather: return Theme.cyan
        case .pit: return Theme.cyan
        case .result: return .white
        case .info: return Theme.dimText
        }
    }
}
