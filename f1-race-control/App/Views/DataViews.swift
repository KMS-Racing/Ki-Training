import SwiftUI
import RaceEngine

/// Alle Fahrer mit ihren Werten.
struct DriverListView: View {
    let data: RaceData

    var body: some View {
        List(data.drivers) { driver in
            let team = data.teams.first { $0.id == driver.teamID }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("\(driver.number)")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(hex: team?.colorHex ?? "#888888"))
                        .frame(width: 34, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(driver.name).font(.headline)
                        Text(team?.name ?? driver.teamID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(driver.id)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Die Werte, aus denen die Engine die Rundenzeit macht.
                VStack(spacing: 3) {
                    RatingBar(label: "PACE", value: driver.pace)
                    RatingBar(label: "CONSISTENCY", value: driver.consistency)
                    RatingBar(label: "OVERTAKING", value: driver.overtaking)
                    RatingBar(label: "DEFENDING", value: driver.defending)
                    RatingBar(label: "WET", value: driver.wetPerformance)
                    RatingBar(label: "TYRES", value: driver.tyreManagement)
                }
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Fahrer")
    }
}

/// Ein Balken für einen Fahrerwert.
struct RatingBar: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(colour)
                        .frame(width: max(2, geometry.size.width * value / 100))
                }
            }
            .frame(height: 5)
            Text("\(Int(value))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private var colour: Color {
        if value >= 92 { return Theme.purple }
        if value >= 84 { return Theme.green }
        if value >= 76 { return Theme.yellow }
        return Theme.red
    }
}

/// Alle Teams.
struct TeamListView: View {
    let data: RaceData

    var body: some View {
        List(data.teams) { team in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: team.colorHex))
                        .frame(width: 5, height: 30)
                    Text(team.name).font(.headline)
                    Spacer()
                    Text(data.drivers.filter { $0.teamID == team.id }
                            .map { $0.id }.joined(separator: " · "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 3) {
                    RatingBar(label: "CAR", value: team.carPerformance)
                    RatingBar(label: "RELIABILITY", value: team.reliability)
                    RatingBar(label: "PIT CREW", value: team.pitCrewSkill)
                }
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Teams")
    }
}

/// Alle Strecken mit einer kleinen Vorschau der Streckenkarte.
struct CircuitListView: View {
    let data: RaceData

    var body: some View {
        List(data.circuits) { circuit in
            HStack(spacing: 14) {
                CircuitThumbnail(circuit: circuit)
                    .frame(width: 76, height: 60)

                VStack(alignment: .leading, spacing: 3) {
                    Text(circuit.name).font(.headline)
                    Text(circuit.country).font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.3f km · %d Runden · Box %.0f s",
                                circuit.lengthKm, circuit.defaultLaps, circuit.pitLaneLoss))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Strecken")
    }
}

/// Kleine Streckenzeichnung für die Liste.
struct CircuitThumbnail: View {
    let circuit: Circuit

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let layout = circuit.layout
                guard layout.count > 1 else { return }
                let inset: CGFloat = 4
                let width = max(1, size.width - inset * 2)
                let height = max(1, size.height - inset * 2)

                var path = Path()
                path.move(to: CGPoint(x: inset + layout[0].x * width,
                                      y: inset + layout[0].y * height))
                for entry in layout.dropFirst() {
                    path.addLine(to: CGPoint(x: inset + entry.x * width,
                                             y: inset + entry.y * height))
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.primary.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Einstellungen.
struct SettingsView: View {
    @EnvironmentObject private var model: RaceViewModel

    var body: some View {
        Form {
            Section("SIMULATION") {
                VStack(alignment: .leading) {
                    Text("Renntempo: \(Int(model.speed))× Echtzeit")
                    Slider(value: $model.speed, in: 1...300)
                }
                Text("""
                Bei 1× läuft das Rennen so lange wie in echt. Höhere Werte raffen die \
                Zeit — die Rechnung bleibt dieselbe.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("ÜBER") {
                LabeledContent("Projekt", value: "F1 Race Control")
                LabeledContent("Datenstand", value: "Saison 2026")
                Text("""
                Die Rennlogik steckt vollständig im Swift-Paket RaceEngine und ist dort \
                mit Tests abgesichert. Diese App zeigt nur an, was die Engine berechnet.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
    }
}
