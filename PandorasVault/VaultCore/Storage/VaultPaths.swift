import Foundation

enum VaultPaths {
    static func vaultDirectory(appName: String = "PandorasVault") throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func configURL(vaultDir: URL) -> URL {
        vaultDir.appendingPathComponent("vault-config.json", isDirectory: false)
    }

    static func itemsEncryptedURL(vaultDir: URL) -> URL {
        vaultDir.appendingPathComponent("items.json.pvlt", isDirectory: false)
    }

    static func encryptedFilesDirectory(vaultDir: URL) throws -> URL {
        let dir = vaultDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}


