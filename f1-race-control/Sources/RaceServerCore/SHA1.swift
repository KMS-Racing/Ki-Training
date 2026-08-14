import Foundation

/// SHA-1, von Hand.
///
/// Warum selbst schreiben? Der WebSocket-Handshake schreibt SHA-1 vor (RFC 6455).
/// Auf Apple-Systemen gäbe es dafür CryptoKit, unter Linux nicht — und eine
/// Bibliothek nur für 60 Zeilen Hashfunktion wollte ich dem Projekt nicht antun,
/// das sonst komplett ohne Abhängigkeiten auskommt.
///
/// **Wichtig:** SHA-1 gilt seit Jahren als gebrochen und darf nirgends mehr für
/// Sicherheit benutzt werden. Im WebSocket-Handshake geht es aber gar nicht um
/// Sicherheit — der Hash beweist nur, dass die Gegenstelle das Protokoll versteht
/// und kein alter HTTP-Proxy dazwischenfunkt. Dafür ist er genau richtig.
public enum SHA1 {

    public static func hash(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        // Anhängen: eine 1-Bit, Nullen, dann die Länge in Bits als 64-Bit-Zahl.
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 {
            data.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }

        // Blockweise verarbeiten, 64 Byte am Stück.
        var offset = 0
        while offset < data.count {
            var w = [UInt32](repeating: 0, count: 80)

            for index in 0..<16 {
                let base = offset + index * 4
                w[index] = (UInt32(data[base]) << 24)
                    | (UInt32(data[base + 1]) << 16)
                    | (UInt32(data[base + 2]) << 8)
                    | UInt32(data[base + 3])
            }
            for index in 16..<80 {
                w[index] = rotateLeft(w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16], 1)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4

            for index in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch index {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A82_7999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }

                let temp = rotateLeft(a, 5) &+ f &+ e &+ k &+ w[index]
                e = d
                d = c
                c = rotateLeft(b, 30)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e

            offset += 64
        }

        var result: [UInt8] = []
        for value in [h0, h1, h2, h3, h4] {
            result.append(UInt8((value >> 24) & 0xFF))
            result.append(UInt8((value >> 16) & 0xFF))
            result.append(UInt8((value >> 8) & 0xFF))
            result.append(UInt8(value & 0xFF))
        }
        return result
    }

    public static func base64(of text: String) -> String {
        return Data(hash(Array(text.utf8))).base64EncodedString()
    }

    private static func rotateLeft(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        return (value << amount) | (value >> (32 - amount))
    }
}
