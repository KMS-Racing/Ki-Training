import Foundation

/// Ein Punkt der Streckenlinie, normiert auf 0…1.
///
/// Die Track Map zeichnet die Strecke als Linienzug durch diese Punkte. Normiert heißt:
/// unabhängig davon, wie groß das Fenster ist, passt die Strecke immer hinein.
public struct TrackPoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Eine Rennstrecke.
public struct Circuit: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let country: String
    public let lengthKm: Double
    /// Renndistanz nach Reglement.
    public let defaultLaps: Int

    /// Referenz-Rundenzeit in Sekunden: was ein perfektes Auto mit perfektem Fahrer
    /// auf frischen Softs bei trockener Strecke fahren würde.
    public let baseLapTime: Double
    /// Wie weit das Feld auseinanderliegt (Sekunden zwischen Bestem und Schlechtestem).
    public let paceSpread: Double
    /// Zeitverlust für einen Boxenstopp inklusive Ein- und Ausfahrt.
    public let pitLaneLoss: Double
    /// 0 = überholen ist leicht (Monza), 1 = praktisch unmöglich (Monaco).
    public let overtakingDifficulty: Double
    /// Reifenabrieb der Strecke. 1.0 = normal, 1.4 = sehr fordernd.
    public let tyreWear: Double
    /// Grundneigung zu Regen an diesem Ort (0…1).
    public let rainProbability: Double
    /// Wo die Sektoren enden, als Anteil der Runde — üblicherweise `[0.33, 0.66]`.
    public let sectorSplits: [Double]
    /// Die Streckenlinie für die Track Map.
    public let layout: [TrackPoint]

    public init(
        id: String,
        name: String,
        country: String,
        lengthKm: Double,
        defaultLaps: Int,
        baseLapTime: Double,
        paceSpread: Double,
        pitLaneLoss: Double,
        overtakingDifficulty: Double,
        tyreWear: Double,
        rainProbability: Double,
        sectorSplits: [Double],
        layout: [TrackPoint]
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.lengthKm = lengthKm
        self.defaultLaps = defaultLaps
        self.baseLapTime = baseLapTime
        self.paceSpread = paceSpread
        self.pitLaneLoss = pitLaneLoss
        self.overtakingDifficulty = overtakingDifficulty
        self.tyreWear = tyreWear
        self.rainProbability = rainProbability
        self.sectorSplits = sectorSplits
        self.layout = layout
    }

    /// In welchem Sektor (1…3) liegt dieser Rundenfortschritt?
    public func sector(at progress: Double) -> Int {
        let p = progress - progress.rounded(.down)
        for (index, split) in sectorSplits.enumerated() where p < split {
            return index + 1
        }
        return sectorSplits.count + 1
    }

    /// Position auf der Streckenlinie für einen Rundenfortschritt 0…1.
    ///
    /// Wird zwischen den beiden nächstgelegenen Streckenpunkten interpoliert, damit
    /// sich die Autos auf der Karte flüssig bewegen und nicht von Punkt zu Punkt springen.
    public func position(at progress: Double) -> TrackPoint {
        guard layout.count > 1 else { return layout.first ?? TrackPoint(x: 0.5, y: 0.5) }
        var p = progress - progress.rounded(.down)
        if p < 0 { p += 1 }

        let scaled = p * Double(layout.count)
        let index = Int(scaled) % layout.count
        let nextIndex = (index + 1) % layout.count
        let t = scaled - Double(Int(scaled))

        let a = layout[index]
        let b = layout[nextIndex]
        return TrackPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
