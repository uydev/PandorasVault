import Foundation

struct VaultConfig: Codable, Hashable {
    var version: Int
    var kdf: KDF
    var wrappedVaultKeyB64: String
    var createdAt: Date

    init(version: Int = 1, kdf: KDF, wrappedVaultKeyB64: String, createdAt: Date = Date()) {
        self.version = version
        self.kdf = kdf
        self.wrappedVaultKeyB64 = wrappedVaultKeyB64
        self.createdAt = createdAt
    }

    struct KDF: Codable, Hashable {
        var algorithm: String
        var saltB64: String
        var iterations: Int

        init(algorithm: String = "PBKDF2-HMAC-SHA256", saltB64: String, iterations: Int) {
            self.algorithm = algorithm
            self.saltB64 = saltB64
            self.iterations = iterations
        }
    }
}


