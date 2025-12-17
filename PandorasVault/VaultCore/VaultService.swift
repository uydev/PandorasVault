import CryptoKit
import Foundation
import Security

final class VaultService {
    struct UnlockResult {
        var vaultKey: SymmetricKey
        var items: [VaultItem]
    }

    let store: VaultStore
    let keychain: KeychainStore

    static let keychainAccountVaultKey = "vaultKey.v1"

    init(store: VaultStore = VaultStore(), keychain: KeychainStore = KeychainStore()) {
        self.store = store
        self.keychain = keychain
    }

    func isInitialized() throws -> Bool {
        (try store.loadConfig()) != nil
    }

    func createVault(passwordUTF8: Data, iterations: Int = 200_000) throws -> UnlockResult {
        if try isInitialized() { throw VaultServiceError.vaultAlreadyInitialized }

        let salt = randomBytes(count: 16)
        let derived = try PBKDF2.sha256(password: passwordUTF8, salt: salt, iterations: iterations, keyByteCount: 32)
        let derivedKey = SymmetricKey(data: derived)

        let vaultKeyData = randomBytes(count: 32)
        let wrapped = try AES.GCM.seal(vaultKeyData, using: derivedKey)
        guard let wrappedCombined = wrapped.combined else { throw VaultServiceError.missingCombinedRepresentation }

        let cfg = VaultConfig(
            kdf: .init(
                saltB64: salt.base64EncodedString(),
                iterations: iterations
            ),
            wrappedVaultKeyB64: wrappedCombined.base64EncodedString()
        )
        try store.saveConfig(cfg)

        let vaultKey = SymmetricKey(data: vaultKeyData)
        try store.saveItems([], vaultKey: vaultKey)

        // Cache vault key in Keychain for convenience (still requires OS user session).
        try? keychain.saveData(vaultKeyData, account: Self.keychainAccountVaultKey)

        return .init(vaultKey: vaultKey, items: [])
    }

    func unlock(passwordUTF8: Data) throws -> UnlockResult {
        guard let cfg = try store.loadConfig() else { throw VaultServiceError.vaultNotInitialized }
        guard cfg.kdf.algorithm == "PBKDF2-HMAC-SHA256" else { throw VaultServiceError.unsupportedKDF }

        guard
            let salt = Data(base64Encoded: cfg.kdf.saltB64),
            let wrappedCombined = Data(base64Encoded: cfg.wrappedVaultKeyB64)
        else { throw VaultServiceError.invalidConfig }

        let derived = try PBKDF2.sha256(password: passwordUTF8, salt: salt, iterations: cfg.kdf.iterations, keyByteCount: 32)
        let derivedKey = SymmetricKey(data: derived)

        do {
            let sealed = try AES.GCM.SealedBox(combined: wrappedCombined)
            let vaultKeyData = try AES.GCM.open(sealed, using: derivedKey)
            let vaultKey = SymmetricKey(data: vaultKeyData)
            let items = try store.loadItems(vaultKey: vaultKey)

            try? keychain.saveData(vaultKeyData, account: Self.keychainAccountVaultKey)

            return .init(vaultKey: vaultKey, items: items)
        } catch {
            throw VaultServiceError.wrongPasswordOrCorruptVault
        }
    }

    func unlockFromKeychainIfPresent() throws -> UnlockResult? {
        guard let data = try keychain.loadData(account: Self.keychainAccountVaultKey) else { return nil }
        let key = SymmetricKey(data: data)
        let items = try store.loadItems(vaultKey: key)
        return .init(vaultKey: key, items: items)
    }

    func lock() {
        try? keychain.delete(account: Self.keychainAccountVaultKey)
    }

    func addFile(url: URL, vaultKey: SymmetricKey) throws -> VaultItem {
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let byteCount = try fileByteCount(url)

        let encryptedName = "\(UUID().uuidString).pvlt"
        let outURL = try store.encryptedFileURL(fileName: encryptedName)
        try AESGCMChunkedFileCrypto.encryptFile(input: url, output: outURL, key: vaultKey)

        return VaultItem(
            originalFileName: fileName,
            originalFileExtension: ext,
            originalByteCount: byteCount,
            encryptedFileName: encryptedName
        )
    }

    func exportItem(_ item: VaultItem, to destination: URL, vaultKey: SymmetricKey) throws {
        let inURL = try store.encryptedFileURL(fileName: item.encryptedFileName)
        try AESGCMChunkedFileCrypto.decryptFile(input: inURL, output: destination, key: vaultKey)
    }

    func deleteItem(_ item: VaultItem) throws {
        let inURL = try store.encryptedFileURL(fileName: item.encryptedFileName)
        try? FileManager.default.removeItem(at: inURL)
    }

    // MARK: - Helpers

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private func fileByteCount(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }
}

enum VaultServiceError: Error {
    case vaultNotInitialized
    case vaultAlreadyInitialized
    case invalidConfig
    case unsupportedKDF
    case missingCombinedRepresentation
    case wrongPasswordOrCorruptVault
}


