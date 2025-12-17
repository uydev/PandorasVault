import Foundation

struct VaultItem: Codable, Identifiable, Hashable {
    var id: UUID
    var originalFileName: String
    var originalFileExtension: String?
    var originalByteCount: Int
    var addedAt: Date

    /// Filename inside the vault directory (encrypted bytes are stored here).
    var encryptedFileName: String

    init(
        id: UUID = UUID(),
        originalFileName: String,
        originalFileExtension: String?,
        originalByteCount: Int,
        addedAt: Date = Date(),
        encryptedFileName: String
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.originalFileExtension = originalFileExtension
        self.originalByteCount = originalByteCount
        self.addedAt = addedAt
        self.encryptedFileName = encryptedFileName
    }
}


