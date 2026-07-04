import Foundation

/// Minimal RFC 1321 MD5, used for the Baidu Translate API request signature.
/// Not for security purposes; Foundation/CryptoKit MD5 is unavailable on Linux,
/// where the core module is built for tests.
enum MD5 {
    static func hex(_ string: String) -> String {
        digest(Array(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    private static let sines: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    ]

    private static func digest(_ message: [UInt8]) -> [UInt8] {
        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        var padded = message
        let bitLength = UInt64(message.count) &* 8
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for shift in stride(from: UInt64(0), to: 64, by: 8) {
            padded.append(UInt8(truncatingIfNeeded: bitLength >> shift))
        }

        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 16)
            for index in 0..<16 {
                let base = chunkStart + index * 4
                words[index] = UInt32(padded[base])
                    | UInt32(padded[base + 1]) << 8
                    | UInt32(padded[base + 2]) << 16
                    | UInt32(padded[base + 3]) << 24
            }

            var a = a0, b = b0, c = c0, d = d0
            for round in 0..<64 {
                let mix: UInt32
                let wordIndex: Int
                switch round {
                case 0..<16:
                    mix = (b & c) | (~b & d)
                    wordIndex = round
                case 16..<32:
                    mix = (d & b) | (~d & c)
                    wordIndex = (5 * round + 1) % 16
                case 32..<48:
                    mix = b ^ c ^ d
                    wordIndex = (3 * round + 5) % 16
                default:
                    mix = c ^ (b | ~d)
                    wordIndex = (7 * round) % 16
                }
                let sum = mix &+ a &+ sines[round] &+ words[wordIndex]
                a = d
                d = c
                c = b
                b = b &+ (sum << shifts[round] | sum >> (32 - shifts[round]))
            }

            a0 &+= a
            b0 &+= b
            c0 &+= c
            d0 &+= d
        }

        var output = [UInt8]()
        output.reserveCapacity(16)
        for value in [a0, b0, c0, d0] {
            output.append(UInt8(truncatingIfNeeded: value))
            output.append(UInt8(truncatingIfNeeded: value >> 8))
            output.append(UInt8(truncatingIfNeeded: value >> 16))
            output.append(UInt8(truncatingIfNeeded: value >> 24))
        }
        return output
    }
}
