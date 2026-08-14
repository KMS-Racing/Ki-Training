import SwiftUI
import RaceEngine

/// Die Wetterleiste am unteren Rand.
struct WeatherBarView: View {
    let weather: WeatherConditions

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.cyan)
                Text(weather.state.displayName)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            reading("TRACK", String(format: "%.0f°C", weather.trackTemperature))
            reading("AIR", String(format: "%.0f°C", weather.airTemperature))
            reading("WIND", String(format: "%.0f km/h", weather.windSpeed))
            reading("RAIN", String(format: "%.0f%%", weather.rainProbability * 100))

            // Nässe als Balken — der wichtigste Wert für die Reifenwahl.
            VStack(alignment: .leading, spacing: 3) {
                Text("TRACK WETNESS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 6)
                    Capsule()
                        .fill(Theme.cyan)
                        .frame(width: max(2, 120 * weather.trackWetness), height: 6)
                }
                .frame(width: 120)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.panelBorder, lineWidth: 1))
    }

    private func reading(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symbol: String {
        switch weather.state {
        case .dry: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .lightRain: return "cloud.drizzle.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .drying: return "sun.rain.fill"
        }
    }
}

/// Strategie-Übersicht: Wer steht auf welchem Reifen, wie alt, wie viele Stopps.
struct StrategyView: View {
    @EnvironmentObject private var model: RaceViewModel
    let snapshot: RaceSnapshot

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(snapshot.standings.filter { $0.isActive }.prefix(12)) { state in
                    VStack(spacing: 5) {
                        Text(model.driver(state.driverID)?.lastName.prefix(3).uppercased()
                             ?? state.driverID)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.text)

                        // Reifen mit Alter.
                        ZStack {
                            Circle()
                                .stroke(Theme.color(for: state.tyres.compound), lineWidth: 2.5)
                                .frame(width: 30, height: 30)
                            Text(state.tyres.compound.letter)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(Theme.color(for: state.tyres.compound))
                        }

                        Text("\(state.tyres.age) L")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.dimText)

                        // Wie viel vom Reifen noch übrig ist.
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10)).frame(width: 34, height: 4)
                            Capsule()
                                .fill(wearColour(state.tyres.wear))
                                .frame(width: max(2, 34 * (1 - state.tyres.wear)), height: 4)
                        }

                        Text("\(state.pitStops) PIT")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Theme.dimText)
                    }
                    .frame(width: 48)
                }
            }
            .padding(10)
        }
    }

    private func wearColour(_ wear: Double) -> Color {
        if wear > 0.80 { return Theme.red }
        if wear > 0.55 { return Theme.yellow }
        return Theme.green
    }
}
