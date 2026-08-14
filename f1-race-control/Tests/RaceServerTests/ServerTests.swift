import XCTest
@testable import RaceServerCore
@testable import RaceEngine

/// SHA-1, WebSocket-Handshake und das Protokoll.
final class ServerTests: XCTestCase {

    private func hex(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - SHA-1

    func testSHA1MatchesOfficialTestVectors() {
        // Die Vektoren aus FIPS 180-1 bzw. den üblichen Referenzlisten.
        let cases: [(String, String)] = [
            ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
            ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
            ("The quick brown fox jumps over the lazy dog",
             "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
             "84983e441c3bd26ebaae4aa1f95129e5e54670f1"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(hex(SHA1.hash(Array(input.utf8))), expected, "SHA-1 von \"\(input)\"")
        }
    }

    func testSHA1HandlesLongInputAcrossManyBlocks() {
        // Eine Million 'a' — deckt die Blockschleife und die Längenkodierung ab.
        let long = [UInt8](repeating: UInt8(ascii: "a"), count: 1_000_000)
        XCTAssertEqual(hex(SHA1.hash(long)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
    }

    func testSHA1LengthBoundaries() {
        // Genau an den Blockgrenzen wird gern falsch aufgefüllt.
        for count in [54, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128] {
            let input = [UInt8](repeating: 0x61, count: count)
            XCTAssertEqual(SHA1.hash(input).count, 20, "Länge \(count)")
        }
        // 55, 56 und 64 Byte sind genau die Stellen, an denen ein zusätzlicher
        // Block gebraucht wird — hier gehen Padding-Fehler typischerweise auf.
        XCTAssertEqual(hex(SHA1.hash([UInt8](repeating: 0x61, count: 55))),
                       "c1c8bbdc22796e28c0e15163d20899b65621d65a")
        XCTAssertEqual(hex(SHA1.hash([UInt8](repeating: 0x61, count: 56))),
                       "c2db330f6083854c99d4b5bfb6e8f29f201be699")
        XCTAssertEqual(hex(SHA1.hash([UInt8](repeating: 0x61, count: 64))),
                       "0098ba824b5c16427bd7a1122a5a442a25ec644d")
    }

    // MARK: - WebSocket-Handshake

    func testHandshakeMatchesTheRFCExample() {
        // Das Beispiel aus RFC 6455, Abschnitt 1.3 — wenn das stimmt, versteht
        // jeder Browser den Handshake.
        let key = "dGhlIHNhbXBsZSBub25jZQ=="
        let accept = SHA1.base64(of: key + WebSocketHandshake.magic)
        XCTAssertEqual(accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    // MARK: - Protokoll

    func testCommandDecoding() throws {
        let json = #"{"action":"penalty","driverID":"HAM","seconds":5}"#
        let command = try JSONDecoder().decode(
            CommandMessage.self, from: Data(json.utf8))
        XCTAssertEqual(command.action, "penalty")
        XCTAssertEqual(command.driverID, "HAM")
        XCTAssertEqual(command.seconds, 5)
    }

    func testCommandDecodingWithoutOptionalFields() throws {
        let command = try JSONDecoder().decode(
            CommandMessage.self, from: Data(#"{"action":"vsc"}"#.utf8))
        XCTAssertEqual(command.action, "vsc")
        XCTAssertNil(command.driverID)
        XCTAssertNil(command.seconds)
    }

    func testStatusKindCoversEveryFlag() {
        XCTAssertEqual(statusKind(.green), "green")
        XCTAssertEqual(statusKind(.yellow(sector: 2)), "yellow")
        XCTAssertEqual(statusKind(.virtualSafetyCar(phase: .active)), "vsc")
        XCTAssertEqual(statusKind(.safetyCar(phase: .active)), "safetyCar")
        XCTAssertEqual(statusKind(.redFlag), "red")
        XCTAssertEqual(statusKind(.finished), "finished")
    }

    func testSnapshotMessageIsValidJSON() throws {
        // Der Snapshot geht zehnmal pro Sekunde raus — er muss verlässlich
        // in JSON passen, sonst bricht die Übertragung mitten im Rennen ab.
        let data = try DataLoader.loadAll()
        guard let circuit = data.circuit(id: "monza") else {
            throw XCTSkip("Monza fehlt in den Stammdaten.")
        }
        let engine = RaceEngine(configuration: RaceConfiguration(
            circuit: circuit, drivers: data.drivers, teams: data.teams, laps: 5, seed: 1))
        engine.run(seconds: 120)
        let snapshot = engine.snapshot()

        let message = SnapshotMessage(
            lap: snapshot.lap, totalLaps: snapshot.totalLaps, raceTime: snapshot.raceTime,
            status: snapshot.trackStatus.displayName,
            statusKind: statusKind(snapshot.trackStatus),
            countdown: snapshot.neutralisationCountdown,
            justification: snapshot.directorJustification,
            weather: snapshot.weather, standings: snapshot.standings,
            messages: snapshot.messages, fastestLap: snapshot.fastestLap,
            finished: snapshot.isFinished, running: true, speed: 20, viewers: 3)

        let encoded = try JSONEncoder().encode(message)
        let parsed = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let object = try XCTUnwrap(parsed)

        XCTAssertEqual(object["type"] as? String, "snapshot")
        XCTAssertEqual((object["standings"] as? [Any])?.count, data.drivers.count)
        XCTAssertNotNil(object["weather"])
        XCTAssertEqual(object["viewers"] as? Int, 3)
    }

    func testWelcomeCarriesTheTrackLayout() throws {
        // Die Streckenkarte geht genau einmal raus. Fehlte sie, könnte der Browser
        // die Autos nirgends hinsetzen.
        let data = try DataLoader.loadAll()
        guard let circuit = data.circuit(id: "spa") else {
            throw XCTSkip("Spa fehlt in den Stammdaten.")
        }
        let welcome = WelcomeMessage(
            role: .spectator, circuit: circuit,
            drivers: data.drivers.map {
                DriverInfo(id: $0.id, name: $0.name, lastName: $0.lastName,
                           number: $0.number, team: $0.teamID, color: "#fff")
            },
            totalLaps: 44, sessionName: circuit.name)

        let encoded = try JSONEncoder().encode(welcome)
        let decoded = try JSONDecoder().decode(WelcomeMessage.self, from: encoded)
        XCTAssertEqual(decoded.circuit.layout.count, circuit.layout.count)
        XCTAssertEqual(decoded.drivers.count, data.drivers.count)
        XCTAssertEqual(decoded.role, .spectator)
    }

    func testDashboardIsShipped() {
        let html = ServerResources.dashboardHTML()
        XCTAssertTrue(html.contains("<title>F1 Race Control</title>"),
                      "Die Weboberfläche muss im Paket liegen.")
        XCTAssertTrue(html.contains("new WebSocket"))
        XCTAssertFalse(html.contains("fehlt"))
    }
}

private extension RaceEngine {
    func run(seconds: Double, step: Double = 0.25) {
        var elapsed = 0.0
        while elapsed < seconds && !isFinished {
            advance(step)
            elapsed += step
        }
    }
}
