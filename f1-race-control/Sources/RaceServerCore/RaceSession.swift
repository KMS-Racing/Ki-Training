import Foundation
import RaceEngine

/// Die laufende Renn-Session auf dem Server.
///
/// Hier laufen zwei Dinge gleichzeitig: Ein Thread lässt das Rennen weiterlaufen und
/// schickt regelmäßig den Stand an alle, und pro Client hängt ein Thread am Lesen.
/// **Alles**, was die Engine anfasst, geht durch dieselbe Sperre — die `RaceEngine`
/// ist bewusst eine einfache Klasse ohne eigene Absicherung, und das soll sie auch
/// bleiben, damit sie im Einzelspieler nichts kostet.
public final class RaceSession {

    private let lock = NSLock()
    private var engine: RaceEngine
    private var clients: [WebSocketConnection] = []
    private var nextClientID = 1

    private let data: RaceData
    private let configuration: RaceConfiguration
    private let sessionName: String

    /// Rennsekunden pro echter Sekunde.
    private var speed: Double = 20
    private var running = true

    /// So oft wird gerechnet und gesendet.
    private let tickInterval = 0.1

    public init(configuration: RaceConfiguration, data: RaceData, sessionName: String) {
        self.configuration = configuration
        self.data = data
        self.sessionName = sessionName
        self.engine = RaceEngine(configuration: configuration)
    }

    // MARK: - Clients

    public func nextID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextClientID
        nextClientID += 1
        return id
    }

    public func add(_ client: WebSocketConnection) {
        lock.lock()
        clients.append(client)
        // Ausgabe bewusst *innerhalb* der Sperre: Sonst rechnet zwar jeder Thread
        // die richtige Zahl aus, sie landen aber in beliebiger Reihenfolge auf dem
        // Bildschirm — und dann steht da "0 verbunden", gefolgt von "3 verbunden".
        log("Client \(client.id) verbunden als \(client.isDirector ? "RACE DIRECTOR" : "Zuschauer") "
            + "(\(clients.count) verbunden)")
        lock.unlock()

        send(welcomeTo: client)
    }

    public func remove(_ client: WebSocketConnection) {
        lock.lock()
        clients.removeAll { $0 === client }
        log("Client \(client.id) getrennt (\(clients.count) verbunden)")
        lock.unlock()
    }

    private func send(welcomeTo client: WebSocketConnection) {
        var teamByID: [String: Team] = [:]
        for team in data.teams { teamByID[team.id] = team }

        let infos = data.drivers.map { driver in
            DriverInfo(
                id: driver.id,
                name: driver.name,
                lastName: driver.lastName,
                number: driver.number,
                team: teamByID[driver.teamID]?.name ?? driver.teamID,
                color: teamByID[driver.teamID]?.colorHex ?? "#888888"
            )
        }

        let welcome = WelcomeMessage(
            role: client.isDirector ? .director : .spectator,
            circuit: configuration.circuit,
            drivers: infos,
            totalLaps: configuration.laps,
            sessionName: sessionName
        )
        if let json = encode(welcome) {
            client.send(text: json)
        }
    }

    // MARK: - Die Schleife

    /// Läuft, bis der Prozess endet.
    public func run() {
        while true {
            let start = Date()

            lock.lock()
            if running && !engine.isFinished {
                engine.advance(speed * tickInterval)
            }
            let message = makeSnapshot()
            lock.unlock()

            if let json = encode(message) {
                broadcast(json)
            }

            // Auf den nächsten Takt warten.
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < tickInterval {
                Thread.sleep(forTimeInterval: tickInterval - elapsed)
            }
        }
    }

    /// Muss unter der Sperre aufgerufen werden.
    private func makeSnapshot() -> SnapshotMessage {
        let snapshot = engine.snapshot()
        return SnapshotMessage(
            lap: snapshot.lap,
            totalLaps: snapshot.totalLaps,
            raceTime: snapshot.raceTime,
            status: snapshot.trackStatus.displayName,
            statusKind: statusKind(snapshot.trackStatus),
            countdown: snapshot.neutralisationCountdown,
            justification: snapshot.directorJustification,
            weather: snapshot.weather,
            standings: snapshot.standings,
            messages: Array(snapshot.messages.prefix(25)),
            fastestLap: snapshot.fastestLap,
            finished: snapshot.isFinished,
            running: running,
            speed: speed,
            viewers: clients.count
        )
    }

    private func broadcast(_ json: String) {
        lock.lock()
        let targets = clients
        lock.unlock()

        for client in targets where client.isOpen {
            client.send(text: json)
        }

        // Verbindungen aufräumen, die beim Senden weggebrochen sind.
        lock.lock()
        clients.removeAll { !$0.isOpen }
        lock.unlock()
    }

    // MARK: - Befehle der Rennleitung

    public func handle(commandJSON: String, from client: WebSocketConnection) {
        guard let payload = commandJSON.data(using: .utf8),
              let command = try? JSONDecoder().decode(CommandMessage.self, from: payload) else {
            reply(to: client, ok: false, "Befehl nicht verstanden.")
            return
        }

        // Zuschauer dürfen zuschauen — mehr nicht.
        guard client.isDirector else {
            reply(to: client, ok: false, "Nur der Race Director darf das Rennen steuern.")
            return
        }

        lock.lock()
        var answer = "Ausgeführt."
        var ok = true

        switch command.action {
        case "vsc":
            engine.forceTrackStatus(
                .virtualSafetyCar(phase: .deploying), clearance: 90,
                reason: "Virtual Safety Car deployed by the Race Director. "
                      + "Drivers must hold a delta; overtaking is not allowed.")
            answer = "VIRTUAL SAFETY CAR"

        case "safetyCar":
            engine.forceTrackStatus(
                .safetyCar(phase: .deploying), clearance: 160,
                reason: "Safety Car deployed by the Race Director. "
                      + "The field will bunch up behind the Safety Car.")
            answer = "SAFETY CAR DEPLOYED"

        case "redFlag":
            engine.forceTrackStatus(
                .redFlag, clearance: 180,
                reason: "Red flag shown by the Race Director. The session is suspended.")
            answer = "RED FLAG — Rennen unterbrochen"

        case "resume":
            engine.resumeFromRedFlag()
            answer = "Rennen freigegeben"

        case "penalty":
            if let driverID = command.driverID {
                let seconds = command.seconds ?? 5
                engine.applyPenalty(driverID: driverID, seconds: seconds,
                                    reason: "RACE DIRECTOR DECISION")
                answer = "\(Int(seconds)) SECOND PENALTY für \(driverID)"
            } else {
                ok = false
                answer = "Kein Fahrer angegeben."
            }

        case "weather":
            if let raw = command.state, let state = WeatherState(rawValue: raw) {
                engine.forceWeather(state)
                answer = "Wetter: \(state.displayName)"
            } else {
                ok = false
                answer = "Unbekanntes Wetter."
            }

        case "pause":
            running = false
            answer = "Pausiert"

        case "play":
            running = true
            answer = "Läuft"

        case "speed":
            if let value = command.value {
                speed = min(max(value, 1), 400)
                answer = "Tempo: \(Int(speed))×"
            } else {
                ok = false
                answer = "Kein Tempo angegeben."
            }

        default:
            ok = false
            answer = "Unbekannter Befehl: \(command.action)"
        }
        lock.unlock()

        if ok { log("Race Director (Client \(client.id)): \(answer)") }
        reply(to: client, ok: ok, answer)
    }

    private func reply(to client: WebSocketConnection, ok: Bool, _ message: String) {
        if let json = encode(NoticeMessage(ok: ok, message: message)) {
            client.send(text: json)
        }
    }

    // MARK: - Kleinkram

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[\(stamp)] \(message)")
        fflush(stdout)
    }
}
