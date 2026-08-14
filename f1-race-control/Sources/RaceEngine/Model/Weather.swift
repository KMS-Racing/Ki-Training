import Foundation

/// Der Wetterzustand am Himmel.
///
/// Wichtig: das ist **nicht** dasselbe wie die Nässe der Strecke. Wenn es aufhört zu
/// regnen, ist der Asphalt noch lange nass. Deshalb gibt es zusätzlich `trackWetness`,
/// das dem Wetter hinterherläuft (siehe `WeatherModel`).
public enum WeatherState: String, Codable, CaseIterable, Sendable {
    case dry
    case cloudy
    case lightRain
    case heavyRain
    case drying

    public var displayName: String {
        switch self {
        case .dry: return "DRY"
        case .cloudy: return "CLOUDY"
        case .lightRain: return "LIGHT RAIN"
        case .heavyRain: return "HEAVY RAIN"
        case .drying: return "DRYING TRACK"
        }
    }

    /// Wohin sich die Streckennässe bei diesem Wetter langfristig bewegt.
    public var targetWetness: Double {
        switch self {
        case .dry: return 0.0
        case .cloudy: return 0.0
        case .lightRain: return 0.45
        case .heavyRain: return 0.95
        case .drying: return 0.0
        }
    }

    /// Regnet es gerade?
    public var isRaining: Bool {
        return self == .lightRain || self == .heavyRain
    }

    /// Welche Zustände als nächstes kommen dürfen.
    ///
    /// Das verhindert Unsinn wie „strahlender Sonnenschein → sofort Wolkenbruch“:
    /// Es muss erst bewölkt werden, dann leichter Regen, dann Starkregen.
    public var allowedTransitions: [WeatherState] {
        switch self {
        case .dry: return [.cloudy]
        case .cloudy: return [.dry, .lightRain]
        case .lightRain: return [.heavyRain, .drying]
        case .heavyRain: return [.lightRain]
        case .drying: return [.cloudy, .lightRain]
        }
    }
}

/// Alles, was das Wetter gerade macht — als fertiges Paket für UI und Rechenmodelle.
public struct WeatherConditions: Codable, Hashable, Sendable {
    public var state: WeatherState
    /// Nässe der Strecke, 0 = staubtrocken, 1 = stehendes Wasser.
    public var trackWetness: Double
    public var airTemperature: Double
    public var trackTemperature: Double
    /// Windgeschwindigkeit in km/h.
    public var windSpeed: Double
    /// Wie wahrscheinlich es in nächster Zeit (mehr) regnet, 0…1.
    public var rainProbability: Double

    public init(
        state: WeatherState = .dry,
        trackWetness: Double = 0,
        airTemperature: Double = 24,
        trackTemperature: Double = 38,
        windSpeed: Double = 8,
        rainProbability: Double = 0.1
    ) {
        self.state = state
        self.trackWetness = trackWetness
        self.airTemperature = airTemperature
        self.trackTemperature = trackTemperature
        self.windSpeed = windSpeed
        self.rainProbability = rainProbability
    }
}
