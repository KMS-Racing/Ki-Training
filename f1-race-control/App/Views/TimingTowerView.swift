import SwiftUI
import RaceEngine

/// Der Timing Tower — die Tabelle, die man aus jeder Übertragung kennt.
///
/// ```
/// POS DRIVER       GAP       INT      TYRE
/// 1   VERSTAPPEN   —         —        S  12
/// 2   NORRIS       +1.824    +1.824   M   4
/// ```
struct TimingTowerView: View {
    @EnvironmentObject private var model: RaceViewModel
    let snapshot: RaceSnapshot

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(snapshot.standings) { state in
                        TimingRowView(state: state, snapshot: snapshot)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("POS").frame(width: 34, alignment: .leading)
            Text("DRIVER").frame(width: 108, alignment: .leading)
            Text("GAP").frame(width: 68, alignment: .trailing)
            Text("INT").frame(width: 62, alignment: .trailing)
            Text("LAST").frame(width: 72, alignment: .trailing)
            Text("TYRE").frame(width: 48, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(Theme.dimText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Eine Zeile des Timing Towers.
struct TimingRowView: View {
    @EnvironmentObject private var model: RaceViewModel
    let state: DriverState
    let snapshot: RaceSnapshot

    private var driver: Driver? { model.driver(state.driverID) }

    var body: some View {
        HStack(spacing: 0) {
            // Position
            Text("\(state.position)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(state.isActive ? Theme.text : Theme.dimText)

            // Teamfarbe + Name
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(model.color(for: state.driverID))
                    .frame(width: 3, height: 16)
                Text(driver?.lastName ?? state.driverID)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.status == .retired ? Theme.dimText : Theme.text)
                    .strikethrough(state.status == .retired)
            }
            .frame(width: 108, alignment: .leading)

            Text(gapText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(gapColor)
                .frame(width: 68, alignment: .trailing)

            Text(intervalText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.dimText)
                .frame(width: 62, alignment: .trailing)

            Text(state.lastLapTime.map { RaceControl.formatLapTime($0) } ?? "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(state.hasFastestLap ? Theme.purple : Theme.text.opacity(0.85))
                .frame(width: 72, alignment: .trailing)

            // Reifen: Buchstabe in Mischungsfarbe, daneben das Alter
            HStack(spacing: 3) {
                Text(state.tyres.compound.letter)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.color(for: state.tyres.compound))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Theme.color(for: state.tyres.compound), lineWidth: 1.2))
                Text("\(state.tyres.age)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(state.tyres.isCritical ? Theme.red : Theme.dimText)
            }
            .frame(width: 48, alignment: .trailing)

            // Positionsgewinn seit dem Start
            positionChangeBadge
                .frame(width: 34, alignment: .trailing)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        Group {
            if state.status == .inPitLane {
                Theme.cyan.opacity(0.12)
            } else if state.position <= 3 && state.isActive {
                Color.white.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }

    private var gapText: String {
        switch state.status {
        case .retired: return "DNF"
        case .inPitLane: return "PIT"
        default:
            if state.position == 1 { return "LEADER" }
            if state.lapsDown >= 1 { return "+\(state.lapsDown) LAP" }
            return RaceControl.formatGap(state.gapToLeader)
        }
    }

    private var gapColor: Color {
        switch state.status {
        case .retired: return Theme.red
        case .inPitLane: return Theme.cyan
        default: return Theme.text.opacity(0.85)
        }
    }

    private var intervalText: String {
        guard state.isActive, state.position > 1, state.lapsDown == 0 else { return "—" }
        return RaceControl.formatGap(state.interval)
    }

    @ViewBuilder
    private var positionChangeBadge: some View {
        let change = state.positionChange
        if change > 0 {
            Text("▲\(change)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.green)
        } else if change < 0 {
            Text("▼\(-change)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.red)
        } else {
            Text("—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.dimText.opacity(0.5))
        }
    }
}
