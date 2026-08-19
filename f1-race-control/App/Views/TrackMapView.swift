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
                let fit = mapping(in: box)
                drawTrack(context: context, fit: fit)
                drawCars(context: context, fit: fit)
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
    }

    /// Wie die Streckenlinie auf den Bildschirm kommt: ein Faktor, zwei Verschiebungen.
    struct Mapping {
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    /// Beide Achsen mit **demselben** Faktor.
    ///
    /// Vorher wurde x mit der Breite und y mit der Höhe des Panels multipliziert.
    /// Damit war jede Strecke genau um das Seitenverhältnis des Panels verzerrt —
    /// hier um 25 % in die Breite gezogen. Das war einer von drei Gründen, warum die
    /// Karten unbrauchbar aussahen; die anderen beiden steckten im Generator.
    ///
    /// Skaliert wird nach der tatsächlichen Ausdehnung der Linie, nicht nach dem
    /// 0…1-Quadrat, in dem sie steckt: Sonst füllt ein langes, schmales Montreal nur
    /// ein Bändchen in der Mitte, während rundherum alles leer bleibt.
    private func mapping(in box: CGRect) -> Mapping {
        let layout = snapshot.circuit.layout
        guard let first = layout.first else { return Mapping(scale: 1, offsetX: 0, offsetY: 0) }

        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for entry in layout {
            minX = min(minX, entry.x); maxX = max(maxX, entry.x)
            minY = min(minY, entry.y); maxY = max(maxY, entry.y)
        }

        let width = max(CGFloat(maxX - minX), 0.000001)
        let height = max(CGFloat(maxY - minY), 0.000001)
        let scale = min(box.width / width, box.height / height)

        return Mapping(
            scale: scale,
            offsetX: box.minX + (box.width - width * scale) / 2 - CGFloat(minX) * scale,
            offsetY: box.minY + (box.height - height * scale) / 2 - CGFloat(minY) * scale
        )
    }

    /// Punkt der Streckenlinie in Bildschirmkoordinaten.
    private func point(_ track: TrackPoint, fit: Mapping) -> CGPoint {
        return CGPoint(
            x: fit.offsetX + CGFloat(track.x) * fit.scale,
            y: fit.offsetY + CGFloat(track.y) * fit.scale
        )
    }

    private func drawTrack(context: GraphicsContext, fit: Mapping) {
        let layout = snapshot.circuit.layout
        guard layout.count > 1 else { return }

        var path = Path()
        path.move(to: point(layout[0], fit: fit))
        for entry in layout.dropFirst() {
            path.addLine(to: point(entry, fit: fit))
        }
        path.closeSubpath()

        // Zwei Linien übereinander: breite dunkle Fahrbahn, dünner heller Rand.
        context.stroke(path, with: .color(Color.white.opacity(0.12)),
                       style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(Color.white.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Start-/Ziellinie.
        let start = point(layout[0], fit: fit)
        var line = Path()
        line.move(to: CGPoint(x: start.x - 8, y: start.y))
        line.addLine(to: CGPoint(x: start.x + 8, y: start.y))
        context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3))
    }

    private func drawCars(context: GraphicsContext, fit: Mapping) {
        // Von hinten nach vorn zeichnen, damit der Führende obenauf liegt.
        for state in snapshot.standings.reversed() {
            guard state.isActive else { continue }

            let position = point(snapshot.circuit.position(at: state.lapProgress), fit: fit)
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
