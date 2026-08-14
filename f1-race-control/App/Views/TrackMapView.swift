import SwiftUI
import RaceEngine

/// Die Streckenkarte mit den Autos in Echtzeit.
///
/// Gezeichnet wird mit `Canvas`, weil hier bei jedem Bild bis zu 22 Punkte neu gesetzt
/// werden — dafür ist eine einzelne Zeichenfläche deutlich sparsamer als 22 einzelne Views.
///
/// Die Position kommt aus `circuit.position(at:)`: Die Engine liefert je Auto einen
/// Rundenfortschritt von 0 bis 1, die Strecke rechnet das in einen Punkt auf der Linie um.
struct TrackMapView: View {
    @EnvironmentObject private var model: RaceViewModel
    let snapshot: RaceSnapshot

    /// Wie groß ein Auto auf der Karte ist.
    private let carRadius: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            let inset = carRadius + 4
            let box = CGRect(
                x: inset, y: inset,
                width: max(1, geometry.size.width - inset * 2),
                height: max(1, geometry.size.height - inset * 2)
            )

            Canvas { context, _ in
                drawTrack(context: context, box: box)
                drawCars(context: context, box: box)
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
    }

    /// Punkt der Streckenlinie in Bildschirmkoordinaten.
    private func point(_ track: TrackPoint, in box: CGRect) -> CGPoint {
        return CGPoint(
            x: box.minX + track.x * box.width,
            y: box.minY + track.y * box.height
        )
    }

    private func drawTrack(context: GraphicsContext, box: CGRect) {
        let layout = snapshot.circuit.layout
        guard layout.count > 1 else { return }

        var path = Path()
        path.move(to: point(layout[0], in: box))
        for entry in layout.dropFirst() {
            path.addLine(to: point(entry, in: box))
        }
        path.closeSubpath()

        // Zwei Linien übereinander: breite dunkle Fahrbahn, dünner heller Rand.
        context.stroke(path, with: .color(Color.white.opacity(0.12)),
                       style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(Color.white.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Start-/Ziellinie.
        let start = point(layout[0], in: box)
        var line = Path()
        line.move(to: CGPoint(x: start.x - 8, y: start.y))
        line.addLine(to: CGPoint(x: start.x + 8, y: start.y))
        context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3))
    }

    private func drawCars(context: GraphicsContext, box: CGRect) {
        // Von hinten nach vorn zeichnen, damit der Führende obenauf liegt.
        for state in snapshot.standings.reversed() {
            guard state.isActive else { continue }

            let position = point(snapshot.circuit.position(at: state.lapProgress), in: box)
            let colour = model.color(for: state.driverID)
            let circle = Path(ellipseIn: CGRect(
                x: position.x - carRadius, y: position.y - carRadius,
                width: carRadius * 2, height: carRadius * 2
            ))

            context.fill(circle, with: .color(colour))
            context.stroke(circle, with: .color(.black.opacity(0.6)), lineWidth: 1)

            // Startnummer ins Auto schreiben.
            if let number = model.driver(state.driverID)?.number {
                let text = Text("\(number)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                context.draw(text, at: position)
            }
        }
    }
}
