import SwiftUI
import RaceEngine
#if os(macOS)
import AppKit
#endif

/// Einstiegspunkt der App.
@main
struct F1RaceControlApp: App {
    @StateObject private var model = RaceViewModel()
    @StateObject private var seasonModel = SeasonViewModel()

    init() {
        #if os(macOS)
        // Startet man die App mit `swift run F1RaceControl`, gibt es kein `.app`-Bündel
        // und damit auch keine `Info.plist`. macOS hält so ein Programm für ein
        // Hilfswerkzeug ohne Oberfläche: Das Fenster geht zwar auf, aber ohne Eintrag
        // im Dock und ohne Menüleiste, und es kommt nicht nach vorn.
        //
        // Diese Zeile macht daraus eine ganz normale Anwendung. Wird die App in Xcode
        // gebaut, steht die Richtlinie ohnehin schon auf `.regular` — dann ist der
        // Aufruf wirkungslos und stört nicht.
        NSApplication.shared.setActivationPolicy(.regular)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .environmentObject(seasonModel)
                .preferredColorScheme(.dark)   // Rennleitungen sind dunkel
                #if os(macOS)
                // Nach vorn holen, sobald das Fenster wirklich steht. In `init()` wäre
                // es zu früh — da läuft die Anwendung noch gar nicht.
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 900)
        #endif
    }
}

/// Die Farben und Abstände der Oberfläche an einer Stelle.
enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let panel = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let panelBorder = Color.white.opacity(0.08)
    static let text = Color.white
    static let dimText = Color.white.opacity(0.55)

    static let green = Color(red: 0.20, green: 0.85, blue: 0.35)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.10)
    static let red = Color(red: 0.95, green: 0.20, blue: 0.25)
    static let purple = Color(red: 0.75, green: 0.35, blue: 0.95)
    static let cyan = Color(red: 0.30, green: 0.85, blue: 0.95)

    /// Die Farbe zum Streckenzustand — dieselbe Sprache wie an der Strecke.
    static func color(for status: TrackStatus) -> Color {
        switch status {
        case .green: return green
        case .yellow: return yellow
        case .virtualSafetyCar, .safetyCar: return yellow
        case .redFlag: return red
        case .finished: return .white
        }
    }

    /// Die Farbe einer Reifenmischung, wie auf den Flanken.
    static func color(for compound: TyreCompound) -> Color {
        switch compound {
        case .soft: return red
        case .medium: return yellow
        case .hard: return .white
        case .intermediate: return green
        case .wet: return cyan
        }
    }
}

/// Einheitlicher Rahmen für alle Panels des Dashboards.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider().overlay(Theme.panelBorder)

            content
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Theme.panelBorder, lineWidth: 1)
        )
    }
}
