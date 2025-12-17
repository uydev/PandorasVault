import CryptoKit
import Foundation
import Security

enum AESGCMChunkedFileCrypto {
    // File format:
    // [magic: 5 bytes "PVLT1"]
    // [chunkSize: UInt32 BE]
    // [noncePrefix: 8 bytes random]
    // [originalSize: UInt64 BE]
    // [chunkCount: UInt32 BE]
    // repeated chunkCount times:
    //   [sealedLen: UInt32 BE]
    //   [sealedCombined: sealedLen bytes]  (nonce(12) + ciphertext + tag(16))
    //
    // This keeps memory bounded and provides per-chunk authenticity.

    static let magic = Data("PVLT1".utf8)
    static let defaultChunkSize = 1_048_576 // 1 MiB

    static func encryptFile(
        input: URL,
        output: URL,
        key: SymmetricKey,
        chunkSize: Int = defaultChunkSize
    ) throws {
        let inHandle = try FileHandle(forReadingFrom: input)
        defer { try? inHandle.close() }

        FileManager.default.createFile(atPath: output.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: output)
        defer { try? outHandle.close() }

        let fileSize = try fileByteCount(input)
        let noncePrefix = randomBytes(count: 8)

        // We'll write the header with a placeholder chunkCount, then patch it once done.
        outHandle.write(magic)
        outHandle.write(Data(uint32be(UInt32(chunkSize))))
        outHandle.write(noncePrefix)
        outHandle.write(Data(uint64be(UInt64(fileSize))))

        let chunkCountOffset = outHandle.offsetInFile
        outHandle.write(Data(uint32be(0))) // placeholder chunkCount

        var chunkIndex: UInt32 = 0
        while true {
            let chunk = inHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            let nonce = try AES.GCM.Nonce(data: buildNonce(prefix8: noncePrefix, counter4: chunkIndex))
            let sealed = try AES.GCM.seal(chunk, using: key, nonce: nonce)
            guard let combined = sealed.combined else {
                throw AESGCMChunkedFileCryptoError.missingCombinedRepresentation
            }

            outHandle.write(Data(uint32be(UInt32(combined.count))))
            outHandle.write(combined)

            chunkIndex &+= 1
        }

        // Patch chunkCount
        let endOffset = outHandle.offsetInFile
        outHandle.seek(toFileOffset: chunkCountOffset)
        outHandle.write(Data(uint32be(chunkIndex)))
        outHandle.seek(toFileOffset: endOffset)
    }

    static func decryptFile(
        input: URL,
        output: URL,
        key: SymmetricKey
    ) throws {
        let inHandle = try FileHandle(forReadingFrom: input)
        defer { try? inHandle.close() }

        FileManager.default.createFile(atPath: output.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: output)
        defer { try? outHandle.close() }

        let headerMagic = try readExact(inHandle, count: 5)
        guard headerMagic == magic else { throw AESGCMChunkedFileCryptoError.invalidMagic }

        _ = Int(try readUInt32be(inHandle)) // chunkSize informational
        let _ = try readExact(inHandle, count: 8) // noncePrefix informational
        let _ = try readUInt64be(inHandle) // originalSize informational
        let chunkCount = try readUInt32be(inHandle)

        for _ in 0..<chunkCount {
            let sealedLen = Int(try readUInt32be(inHandle))
            let combined = try readExact(inHandle, count: sealedLen)
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(sealed, using: key)
            outHandle.write(plaintext)
        }
    }

    // MARK: - Helpers

    private static func buildNonce(prefix8: Data, counter4: UInt32) -> Data {
        var nonce = Data()
        nonce.append(prefix8)
        nonce.append(contentsOf: uint32be(counter4))
        return nonce
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private static func fileByteCount(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func uint32be(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
    }

    private static func uint64be(_ value: UInt64) -> [UInt8] {
        [
            UInt8((value >> 56) & 0xff),
            UInt8((value >> 48) & 0xff),
            UInt8((value >> 40) & 0xff),
            UInt8((value >> 32) & 0xff),
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
    }

    private static func readUInt32be(_ handle: FileHandle) throws -> UInt32 {
        let d = try readExact(handle, count: 4)
        return d.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func readUInt64be(_ handle: FileHandle) throws -> UInt64 {
        let d = try readExact(handle, count: 8)
        return d.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private static func readExact(_ handle: FileHandle, count: Int) throws -> Data {
        var out = Data()
        out.reserveCapacity(count)
        while out.count < count {
            let next = handle.readData(ofLength: count - out.count)
            if next.isEmpty { throw AESGCMChunkedFileCryptoError.unexpectedEOF }
            out.append(next)
        }
        return out
    }
}

enum AESGCMChunkedFileCryptoError: Error {
    case invalidMagic
    case unexpectedEOF
    case missingCombinedRepresentation
}


