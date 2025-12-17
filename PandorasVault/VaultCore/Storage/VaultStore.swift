import CryptoKit
import Foundation

final class VaultStore {
    let appName: String

    init(appName: String = "PandorasVault") {
        self.appName = appName
    }

    func vaultDirectory() throws -> URL {
        try VaultPaths.vaultDirectory(appName: appName)
    }

    func loadConfig() throws -> VaultConfig? {
        let dir = try vaultDirectory()
        let url = VaultPaths.configURL(vaultDir: dir)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VaultConfig.self, from: data)
    }

    func saveConfig(_ config: VaultConfig) throws {
        let dir = try vaultDirectory()
        let url = VaultPaths.configURL(vaultDir: dir)
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: [.atomic])
    }

    func loadItems(vaultKey: SymmetricKey) throws -> [VaultItem] {
        let dir = try vaultDirectory()
        let url = VaultPaths.itemsEncryptedURL(vaultDir: dir)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let combined = try Data(contentsOf: url)
        let sealed = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealed, using: vaultKey)
        return try JSONDecoder().decode([VaultItem].self, from: plaintext)
    }

    func saveItems(_ items: [VaultItem], vaultKey: SymmetricKey) throws {
        let dir = try vaultDirectory()
        let url = VaultPaths.itemsEncryptedURL(vaultDir: dir)
        let data = try JSONEncoder().encode(items)
        let sealed = try AES.GCM.seal(data, using: vaultKey)
        guard let combined = sealed.combined else { throw VaultStoreError.missingCombinedRepresentation }
        try combined.write(to: url, options: [.atomic])
    }

    func encryptedFileURL(fileName: String) throws -> URL {
        let dir = try vaultDirectory()
        let filesDir = try VaultPaths.encryptedFilesDirectory(vaultDir: dir)
        return filesDir.appendingPathComponent(fileName, isDirectory: false)
    }
}

enum VaultStoreError: Error {
    case missingCombinedRepresentation
}


