import CryptoKit
import Foundation

enum PBKDF2 {
    /// PBKDF2-HMAC-SHA256 (RFC 8018).
    static func sha256(
        password: Data,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> Data {
        guard iterations > 0 else { throw PBKDF2Error.invalidIterations }
        guard keyByteCount > 0 else { throw PBKDF2Error.invalidKeyLength }

        let hLen = 32 // SHA256 output length
        let l = Int(ceil(Double(keyByteCount) / Double(hLen))) // number of blocks

        var derived = Data()
        derived.reserveCapacity(l * hLen)

        let key = SymmetricKey(data: password)

        for blockIndex in 1...l {
            var saltAndIndex = Data()
            saltAndIndex.append(salt)
            saltAndIndex.append(contentsOf: Self.int32be(blockIndex))

            var u = Data(HMAC<SHA256>.authenticationCode(for: saltAndIndex, using: key))
            var t = u

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    Self.xorInPlace(&t, with: u)
                }
            }

            derived.append(t)
        }

        return derived.prefix(keyByteCount)
    }

    private static func int32be(_ value: Int) -> [UInt8] {
        let v = UInt32(value)
        return [
            UInt8((v >> 24) & 0xff),
            UInt8((v >> 16) & 0xff),
            UInt8((v >> 8) & 0xff),
            UInt8(v & 0xff),
        ]
    }

    private static func xorInPlace(_ lhs: inout Data, with rhs: Data) {
        lhs.withUnsafeMutableBytes { (lhsBytes: UnsafeMutableRawBufferPointer) in
            rhs.withUnsafeBytes { (rhsBytes: UnsafeRawBufferPointer) in
                let l = lhsBytes.count
                guard rhsBytes.count == l else { return }
                for i in 0..<l {
                    lhsBytes[i] = lhsBytes[i] ^ rhsBytes[i]
                }
            }
        }
    }
}

enum PBKDF2Error: Error {
    case invalidIterations
    case invalidKeyLength
}


