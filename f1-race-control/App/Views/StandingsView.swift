import SwiftUI
import RaceEngine

/// Fahrer- und Konstrukteurswertung nebeneinander.
struct StandingsView: View {
    @EnvironmentObject private var seasonModel: SeasonViewModel

    var body: some View {
        Group {
            if let season = seasonModel.season {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Nach \(season.completedRounds) von \(season.calendar.count) Rennen")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                driverTable
                                constructorTable.frame(maxWidth: 380)
                            }
                            VStack(alignment: .leading, spacing: 18) {
                                driverTable
                                constructorTable
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Keine Saison", systemImage: "trophy",
                    description: Text("Lege unter „Saison“ eine Meisterschaft an."))
            }
        }
        .navigationTitle("Meisterschaft")
    }

    private var driverTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAHRERWERTUNG")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Text("POS").frame(width: 34, alignment: .leading)
                Text("FAHRER").frame(width: 150, alignment: .leading)
                Text("PKT").frame(width: 46, alignment: .trailing)
                Text("SIEGE").frame(width: 50, alignment: .trailing)
                Text("POD").frame(width: 42, alignment: .trailing)
                Text("POLE").frame(width: 46, alignment: .trailing)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)

            ForEach(seasonModel.driverStandings) { entry in
                HStack(spacing: 0) {
                    Text("\(entry.position)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 34, alignment: .leading)

                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(seasonModel.color(forDriver: entry.driverID))
                            .frame(width: 3, height: 16)
                        Text(seasonModel.driver(entry.driverID)?.name ?? entry.driverID)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)

                    Text("\(entry.points)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 46, alignment: .trailing)
                    Text("\(entry.wins)")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                    Text("\(entry.podiums)")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 42, alignment: .trailing)
                    Text("\(entry.poles)")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 46, alignment: .trailing)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .background(entry.position <= 3 ? Color.primary.opacity(0.05) : .clear)
            }
        }
    }

    private var constructorTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KONSTRUKTEURSWERTUNG")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Text("POS").frame(width: 34, alignment: .leading)
                Text("TEAM").frame(width: 170, alignment: .leading)
                Text("PKT").frame(width: 46, alignment: .trailing)
                Text("SIEGE").frame(width: 50, alignment: .trailing)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)

            ForEach(seasonModel.constructorStandings) { entry in
                HStack(spacing: 0) {
                    Text("\(entry.position)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 34, alignment: .leading)

                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(seasonModel.color(forTeam: entry.teamID))
                            .frame(width: 3, height: 16)
                        Text(seasonModel.team(entry.teamID)?.name ?? entry.teamID)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    .frame(width: 170, alignment: .leading)

                    Text("\(entry.points)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 46, alignment: .trailing)
                    Text("\(entry.wins)")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .background(entry.position <= 3 ? Color.primary.opacity(0.05) : .clear)
            }
        }
    }
}

/// Die Statistiktabelle: alles, was über eine Saison zusammenkommt.
struct SeasonStatsView: View {
    @EnvironmentObject private var seasonModel: SeasonViewModel

    var body: some View {
        Group {
            if seasonModel.season != nil {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 3) {
                        header
                        ForEach(seasonModel.driverStandings) { entry in
                            row(entry)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Keine Saison", systemImage: "chart.bar",
                    description: Text("Statistiken entstehen, sobald Rennen gefahren wurden."))
            }
        }
        .navigationTitle("Statistik")
    }

    private let columns: [(String, CGFloat)] = [
        ("FAHRER", 150), ("REN", 44), ("SIE", 44), ("POD", 44), ("POLE", 48),
        ("FL", 40), ("DNF", 44), ("BOX", 44), ("Ø POS", 56), ("Ø RUNDE", 84), ("BESTE", 84),
    ]

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.0) { column in
                Text(column.0)
                    .frame(width: column.1,
                           alignment: column.0 == "FAHRER" ? .leading : .trailing)
            }
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private func row(_ entry: ChampionshipEntry) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(seasonModel.color(forDriver: entry.driverID))
                    .frame(width: 3, height: 15)
                Text(seasonModel.driver(entry.driverID)?.lastName ?? entry.driverID)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .frame(width: 150, alignment: .leading)

            value("\(entry.races)", 44)
            value("\(entry.wins)", 44)
            value("\(entry.podiums)", 44)
            value("\(entry.poles)", 48)
            value("\(entry.fastestLaps)", 40)
            value("\(entry.dnfs)", 44)
            value("\(entry.totalPitStops)", 44)
            value(entry.averageFinish.map { String(format: "%.1f", $0) } ?? "—", 56)
            value(entry.averageLapTime.map { RaceControl.formatLapTime($0) } ?? "—", 84)
            value(entry.bestLapTime.map { RaceControl.formatLapTime($0) } ?? "—", 84)
        }
        .padding(.vertical, 2)
    }

    private func value(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: width, alignment: .trailing)
    }
}
