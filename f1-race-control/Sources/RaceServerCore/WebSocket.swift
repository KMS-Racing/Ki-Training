import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// WebSocket nach RFC 6455 — nur der Teil, den dieses Projekt braucht.
///
/// Absichtlich von Hand statt mit SwiftNIO: Das ganze Projekt kommt ohne
/// Abhängigkeiten aus, `swift build` funktioniert damit auch ohne Netz, und
/// 200 Zeilen, die man lesen kann, sind hier mehr wert als eine Bibliothek.
public enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

public struct WebSocketFrame {
    public let opcode: WebSocketOpcode
    public let payload: [UInt8]

    public var text: String? {
        return String(bytes: payload, encoding: .utf8)
    }
}

/// Eine offene Verbindung zu einem Client.
public final class WebSocketConnection {
    public let id: Int
    public let socket: Int32
    /// Darf dieser Client die Rennleitung bedienen?
    public let isDirector: Bool
    /// Welches Auto dieser Client fährt — `nil`, wenn er nur zuschaut.
    public var claimedCar: String?
    public private(set) var isOpen = true

    /// Schreiben passiert aus dem Broadcast-Thread, Lesen aus dem eigenen —
    /// ohne Sperre würden sich zwei Nachrichten ineinander schieben.
    private let writeLock = NSLock()
    /// Was vom Socket schon gelesen, aber noch nicht verbraucht wurde.
    private var buffer: [UInt8] = []

    public init(id: Int, socket: Int32, isDirector: Bool) {
        self.id = id
        self.socket = socket
        self.isDirector = isDirector
    }

    // MARK: - Senden

    public func send(text: String) {
        send(frame: Array(text.utf8), opcode: .text)
    }

    public func sendPong(_ payload: [UInt8]) {
        send(frame: payload, opcode: .pong)
    }

    public func send(frame payload: [UInt8], opcode: WebSocketOpcode) {
        guard isOpen else { return }

        var header: [UInt8] = [0x80 | opcode.rawValue]   // FIN gesetzt, ein Frame

        // Vom Server gesendete Frames werden nie maskiert.
        if payload.count < 126 {
            header.append(UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            header.append(126)
            header.append(UInt8((payload.count >> 8) & 0xFF))
            header.append(UInt8(payload.count & 0xFF))
        } else {
            header.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                header.append(UInt8((payload.count >> shift) & 0xFF))
            }
        }

        writeLock.lock()
        defer { writeLock.unlock() }
        if !writeAll(header + payload) {
            isOpen = false
        }
    }

    /// Alles rausschreiben, auch wenn der Kernel nur Teile annimmt.
    private func writeAll(_ bytes: [UInt8]) -> Bool {
        var sent = 0
        return bytes.withUnsafeBufferPointer { pointer -> Bool in
            guard let base = pointer.baseAddress else { return true }
            while sent < bytes.count {
                #if canImport(Glibc)
                // MSG_NOSIGNAL: Ohne das killt ein Schreiben auf einen geschlossenen
                // Socket den ganzen Serverprozess per SIGPIPE.
                let written = Glibc.send(socket, base + sent, bytes.count - sent, Int32(MSG_NOSIGNAL))
                #else
                let written = Darwin.send(socket, base + sent, bytes.count - sent, 0)
                #endif
                if written <= 0 { return false }
                sent += written
            }
            return true
        }
    }

    // MARK: - Empfangen

    /// Nächstes Frame lesen. Blockiert, bis eines da ist oder die Verbindung endet.
    public func readFrame() -> WebSocketFrame? {
        guard let first = readBytes(2) else { return nil }

        let opcodeRaw = first[0] & 0x0F
        let masked = (first[1] & 0x80) != 0
        var length = Int(first[1] & 0x7F)

        if length == 126 {
            guard let extended = readBytes(2) else { return nil }
            length = Int(extended[0]) << 8 | Int(extended[1])
        } else if length == 127 {
            guard let extended = readBytes(8) else { return nil }
            length = 0
            for byte in extended { length = (length << 8) | Int(byte) }
        }

        // Notbremse gegen einen Client, der eine absurde Länge behauptet.
        guard length <= 1_000_000 else { return nil }

        var mask: [UInt8] = []
        if masked {
            guard let key = readBytes(4) else { return nil }
            mask = key
        }

        var payload = length > 0 ? (readBytes(length) ?? []) : []
        guard payload.count == length else { return nil }

        // Alles, was ein Client schickt, ist maskiert und muss zurückgerechnet werden.
        if masked {
            for index in payload.indices {
                payload[index] ^= mask[index % 4]
            }
        }

        guard let opcode = WebSocketOpcode(rawValue: opcodeRaw) else { return nil }
        return WebSocketFrame(opcode: opcode, payload: payload)
    }

    /// Genau `count` Bytes lesen — notfalls in mehreren Anläufen.
    private func readBytes(_ count: Int) -> [UInt8]? {
        while buffer.count < count {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let received = chunk.withUnsafeMutableBufferPointer { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return recv(socket, base, 4096, 0)
            }
            if received <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<received])
        }
        let result = Array(buffer[0..<count])
        buffer.removeFirst(count)
        return result
    }

    /// Rohbytes zurückgeben, die beim Handshake schon mitgelesen wurden.
    public func pushBack(_ bytes: [UInt8]) {
        buffer.insert(contentsOf: bytes, at: 0)
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        send(frame: [], opcode: .close)
        #if canImport(Glibc)
        _ = Glibc.close(socket)
        #else
        _ = Darwin.close(socket)
        #endif
    }
}

/// Der HTTP-Teil: Anfrage lesen und ggf. auf WebSocket hochstufen.
public enum WebSocketHandshake {

    /// Die feste Kennung aus RFC 6455. Sie sorgt dafür, dass ein Server, der das
    /// Protokoll nicht kennt, den Handshake nicht zufällig richtig beantwortet.
    public static let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    public struct Request {
        public let method: String
        public let path: String
        public let headers: [String: String]
        /// Was nach dem Header-Block schon im Puffer lag.
        public let leftover: [UInt8]

        /// Query-Parameter aus dem Pfad, z.B. `/live?role=director`.
        public var query: [String: String] {
            guard let mark = path.firstIndex(of: "?") else { return [:] }
            var result: [String: String] = [:]
            for pair in path[path.index(after: mark)...].split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard let name = parts.first else { continue }
                result[String(name)] = parts.count > 1 ? String(parts[1]) : ""
            }
            return result
        }

        public var route: String {
            guard let mark = path.firstIndex(of: "?") else { return path }
            return String(path[path.startIndex..<mark])
        }

        public var wantsWebSocket: Bool {
            let upgrade = headers["upgrade"]?.lowercased() ?? ""
            return upgrade == "websocket" && headers["sec-websocket-key"] != nil
        }
    }

    /// HTTP-Anfrage vom Socket lesen (nur der Kopf).
    public static func readRequest(socket: Int32) -> Request? {
        var raw: [UInt8] = []
        let terminator = Array("\r\n\r\n".utf8)

        while raw.count < 16_384 {
            var chunk = [UInt8](repeating: 0, count: 2048)
            let received = chunk.withUnsafeMutableBufferPointer { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return recv(socket, base, 2048, 0)
            }
            if received <= 0 { return nil }
            raw.append(contentsOf: chunk[0..<received])

            if let end = find(terminator, in: raw) {
                let headerBytes = Array(raw[0..<end])
                let leftover = Array(raw[(end + 4)...])
                return parse(headerBytes, leftover: leftover)
            }
        }
        return nil
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            var matches = true
            for offset in needle.indices where haystack[start + offset] != needle[offset] {
                matches = false
                break
            }
            if matches { return start }
        }
        return nil
    }

    private static func parse(_ headerBytes: [UInt8], leftover: [UInt8]) -> Request? {
        guard let text = String(bytes: headerBytes, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return Request(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            leftover: leftover
        )
    }

    /// Die Antwort, die aus einer HTTP-Verbindung eine WebSocket-Verbindung macht.
    public static func response(for request: Request) -> String? {
        guard let key = request.headers["sec-websocket-key"] else { return nil }
        let accept = SHA1.base64(of: key + magic)
        return """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
    }
}
