import Foundation
import RaceEngine
import RaceServerCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// =============================================================================
//  f1server — der Rennleitungs-Server
// -----------------------------------------------------------------------------
//  Ein Rennen läuft auf dem Server. Wer sich verbindet, sieht es live; wer sich
//  als Race Director verbindet, darf eingreifen: VSC, Safety Car, Rote Flagge,
//  Strafen, Wetter.
//
//      swift run f1server --circuit monza --laps 30
//      → http://localhost:8080            zuschauen
//      → http://localhost:8080?role=director   Rennleitung
//
//  Ohne Abhängigkeiten: HTTP und WebSocket sind hier selbst gebaut (WebSocket.swift).
// =============================================================================

let usage = """
f1server — F1 Race Control als Server

Verwendung:
  swift run f1server [Optionen]

Optionen:
  --port <n>         Port (Standard 8080)
  --circuit <id>     Strecke (Standard monza)
  --laps <n>         Rennlänge
  --seed <n>         Zufalls-Startwert
  --weather <s>      dry | cloudy | lightRain | heavyRain | drying
  --speed <n>        Rennsekunden pro echter Sekunde (Standard 20)
  --open             Jeder Verbundene darf die Rennleitung bedienen
  --help             Diese Hilfe

Im Browser:
  http://localhost:<port>/                  zuschauen
  http://localhost:<port>/?role=director    Rennleitung bedienen
"""

// MARK: - Argumente

var port: UInt16 = 8080
var circuitID = "monza"
var laps: Int? = nil
var seed: UInt64 = 42
var weather: WeatherState = .dry
var startSpeed: Double = 20
var openDirector = false

var argIndex = 1
let arguments = CommandLine.arguments
while argIndex < arguments.count {
    let argument = arguments[argIndex]
    func nextValue() -> String? {
        guard argIndex + 1 < arguments.count else { return nil }
        argIndex += 1
        return arguments[argIndex]
    }
    switch argument {
    case "--help", "-h":
        print(usage)
        exit(0)
    case "--port":
        if let v = nextValue(), let n = UInt16(v) { port = n }
    case "--circuit":
        if let v = nextValue() { circuitID = v }
    case "--laps":
        if let v = nextValue(), let n = Int(v) { laps = n }
    case "--seed":
        if let v = nextValue(), let n = UInt64(v) { seed = n }
    case "--speed":
        if let v = nextValue(), let n = Double(v) { startSpeed = n }
    case "--weather":
        if let v = nextValue(), let s = WeatherState(rawValue: v) { weather = s }
    case "--open":
        openDirector = true
    default:
        FileHandle.standardError.write("Unbekannte Option: \(argument)\n".data(using: .utf8)!)
        print(usage)
        exit(1)
    }
    argIndex += 1
}

// MARK: - Rennen aufsetzen

let raceData: RaceData
do {
    raceData = try DataLoader.loadAll()
} catch {
    FileHandle.standardError.write("Stammdaten fehlen: \(error)\n".data(using: .utf8)!)
    exit(1)
}

guard let circuit = raceData.circuit(id: circuitID) else {
    FileHandle.standardError.write("Unbekannte Strecke '\(circuitID)'.\n".data(using: .utf8)!)
    exit(1)
}

let qualifying = QualifyingSimulator.run(
    circuit: circuit,
    drivers: raceData.drivers,
    teams: raceData.teams,
    aiStrength: 0.9,
    seed: seed
)

let raceConfiguration = RaceConfiguration(
    circuit: circuit,
    drivers: raceData.drivers,
    teams: raceData.teams,
    laps: laps,
    startingGrid: qualifying.grid,
    startingWeather: weather,
    seed: seed
)

let session = RaceSession(
    configuration: raceConfiguration,
    data: raceData,
    sessionName: circuit.name
)

// MARK: - Die Weboberfläche

/// Das Dashboard liegt als Ressource im Paket.
@Sendable func dashboardHTML() -> String {
    return ServerResources.dashboardHTML()
}

@Sendable func httpResponse(status: String, contentType: String, body: String) -> [UInt8] {
    let bodyBytes = Array(body.utf8)
    let header = """
    HTTP/1.1 \(status)\r
    Content-Type: \(contentType)\r
    Content-Length: \(bodyBytes.count)\r
    Connection: close\r
    \r

    """
    return Array(header.utf8) + bodyBytes
}

// MARK: - Der Socket

let listener = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
guard listener >= 0 else {
    FileHandle.standardError.write("Socket konnte nicht angelegt werden.\n".data(using: .utf8)!)
    exit(1)
}

var reuse: Int32 = 1
setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

var address = sockaddr_in()
address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian
address.sin_addr.s_addr = INADDR_ANY

let bindResult = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
        bind(listener, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
guard bindResult >= 0 else {
    FileHandle.standardError.write("Port \(port) ist belegt.\n".data(using: .utf8)!)
    exit(1)
}
guard listen(listener, 32) >= 0 else {
    FileHandle.standardError.write("listen() fehlgeschlagen.\n".data(using: .utf8)!)
    exit(1)
}

print("""

F1 RACE CONTROL — SERVER
\(circuit.name) · \(raceConfiguration.laps) Runden · Seed \(seed)
Pole: \(qualifying.poleSitter ?? "—")

  Zuschauen      http://localhost:\(port)/
  Rennleitung    http://localhost:\(port)/?role=director
\(openDirector ? "  (--open: jeder darf die Rennleitung bedienen)" : "")
Beenden mit Strg-C.

""")
fflush(stdout)

// Das Rennen läuft in einem eigenen Thread weiter.
let raceThread = Thread { session.run() }
raceThread.name = "race-loop"
raceThread.start()

// MARK: - Verbindungen annehmen

while true {
    var clientAddress = sockaddr()
    var addressLength = socklen_t(MemoryLayout<sockaddr>.size)
    let client = accept(listener, &clientAddress, &addressLength)
    guard client >= 0 else { continue }

    // Pro Verbindung ein Thread. Für eine Handvoll Clients ist das genau richtig
    // und deutlich einfacher zu verstehen als eine Event-Schleife.
    let thread = Thread {
        guard let request = WebSocketHandshake.readRequest(socket: client) else {
            close(client)
            return
        }

        if request.wantsWebSocket {
            guard let response = WebSocketHandshake.response(for: request) else {
                close(client)
                return
            }
            _ = Array(response.utf8).withUnsafeBufferPointer { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return send(client, base, pointer.count, 0)
            }

            let wantsDirector = request.query["role"] == "director" || openDirector
            let connection = WebSocketConnection(
                id: session.nextID(), socket: client, isDirector: wantsDirector)
            connection.pushBack(request.leftover)
            session.add(connection)

            // Lesen, bis der Client geht.
            while connection.isOpen, let frame = connection.readFrame() {
                switch frame.opcode {
                case .text:
                    if let text = frame.text {
                        session.handle(commandJSON: text, from: connection)
                    }
                case .ping:
                    connection.sendPong(frame.payload)
                case .close:
                    connection.close()
                default:
                    break
                }
            }
            session.remove(connection)
            connection.close()

        } else {
            // Normales HTTP: die Seite ausliefern.
            let body: [UInt8]
            switch request.route {
            case "/", "/index.html":
                body = httpResponse(status: "200 OK",
                                    contentType: "text/html; charset=utf-8",
                                    body: dashboardHTML())
            case "/favicon.ico":
                // Der Browser fragt die von sich aus an. Ohne Antwort steht in jeder
                // Konsole ein 404 — also eine kleine schwarze Flagge als SVG.
                let favicon = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>"
                    + "<rect width='16' height='16' fill='#0d0d11'/>"
                    + "<path d='M3 2h10v6H3z' fill='#fff'/><path d='M3 2h5v3H3zM8 5h5v3H8z' fill='#000'/>"
                    + "<rect x='2' y='2' width='1' height='12' fill='#fff'/></svg>"
                body = httpResponse(status: "200 OK",
                                    contentType: "image/svg+xml",
                                    body: favicon)
            case "/health":
                body = httpResponse(status: "200 OK",
                                    contentType: "text/plain; charset=utf-8",
                                    body: "ok")
            default:
                body = httpResponse(status: "404 Not Found",
                                    contentType: "text/plain; charset=utf-8",
                                    body: "Nicht gefunden")
            }
            _ = body.withUnsafeBufferPointer { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return send(client, base, pointer.count, 0)
            }
            close(client)
        }
    }
    thread.name = "client"
    thread.start()
}
