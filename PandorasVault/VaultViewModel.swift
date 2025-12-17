import AppKit
import CryptoKit
import Foundation

@MainActor
final class VaultViewModel: ObservableObject {
    @Published var password: String = ""
    @Published var isInitialized: Bool = false
    @Published var isUnlocked: Bool = false
    @Published var items: [VaultItem] = []
    @Published var statusText: String?
    @Published var statusIsError: Bool = false

    @Published var isDropTargeted: Bool = false

    private var vaultKey: SymmetricKey?
    private let service = VaultService()

    private var failedAttempts: Int = 0
    private var lockoutUntil: Date?

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            isInitialized = try service.isInitialized()
            if let unlocked = try service.unlockFromKeychainIfPresent() {
                vaultKey = unlocked.vaultKey
                items = unlocked.items
                isUnlocked = true
                setStatus("Unlocked.", isError: false)
            } else {
                isUnlocked = false
                vaultKey = nil
            }
        } catch {
            isInitialized = false
            isUnlocked = false
            vaultKey = nil
            setStatus("Failed to load vault: \(error)", isError: true)
        }
    }

    func createVault() {
        guard !isLockedOut else {
            setStatus("Temporarily locked due to failed attempts. Try again shortly.", isError: true)
            return
        }
        guard !password.isEmpty else {
            setStatus("Enter a password to create the vault.", isError: true)
            return
        }

        do {
            let result = try service.createVault(passwordUTF8: Data(password.utf8))
            vaultKey = result.vaultKey
            items = result.items
            isInitialized = true
            isUnlocked = true
            failedAttempts = 0
            lockoutUntil = nil
            setStatus("Vault created and unlocked.", isError: false)
        } catch {
            setStatus("Create failed: \(error)", isError: true)
        }
    }

    func unlock() {
        guard !isLockedOut else {
            setStatus("Temporarily locked due to failed attempts. Try again shortly.", isError: true)
            return
        }
        guard !password.isEmpty else {
            setStatus("Enter your password to unlock.", isError: true)
            return
        }

        do {
            let result = try service.unlock(passwordUTF8: Data(password.utf8))
            vaultKey = result.vaultKey
            items = result.items
            isUnlocked = true
            failedAttempts = 0
            lockoutUntil = nil
            setStatus("Unlocked.", isError: false)
        } catch {
            registerFailedAttempt()
            setStatus("Unlock failed (wrong password or corrupted vault).", isError: true)
        }
    }

    func lock() {
        vaultKey = nil
        isUnlocked = false
        password = ""
        service.lock()
        setStatus("Locked.", isError: false)
    }

    func addDroppedFileURLs(_ urls: [URL]) {
        guard let key = vaultKey, isUnlocked else {
            setStatus("Unlock the vault before adding files.", isError: true)
            return
        }

        do {
            var current = items
            for url in urls {
                let item = try service.addFile(url: url, vaultKey: key)
                current.append(item)
            }
            items = current.sorted(by: { $0.addedAt > $1.addedAt })
            try service.store.saveItems(items, vaultKey: key)
            setStatus("Encrypted and added \(urls.count) file(s).", isError: false)
        } catch {
            setStatus("Failed to add files: \(error)", isError: true)
        }
    }

    func export(_ item: VaultItem) {
        guard let key = vaultKey, isUnlocked else {
            setStatus("Unlock the vault before exporting.", isError: true)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.originalFileName
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try service.exportItem(item, to: dest, vaultKey: key)
                setStatus("Decrypted and exported.", isError: false)
            } catch {
                setStatus("Export failed: \(error)", isError: true)
            }
        }
    }

    func delete(_ item: VaultItem) {
        guard let key = vaultKey, isUnlocked else {
            setStatus("Unlock the vault before deleting.", isError: true)
            return
        }

        do {
            try service.deleteItem(item)
            items.removeAll { $0.id == item.id }
            try service.store.saveItems(items, vaultKey: key)
            setStatus("Deleted from vault.", isError: false)
        } catch {
            setStatus("Delete failed: \(error)", isError: true)
        }
    }

    func changePassword(currentPassword: String, newPassword: String, confirmNewPassword: String) {
        guard isInitialized else {
            setStatus("Create a vault before changing the password.", isError: true)
            return
        }
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            setStatus("Enter your current password and a new password.", isError: true)
            return
        }
        guard newPassword == confirmNewPassword else {
            setStatus("New password confirmation does not match.", isError: true)
            return
        }

        do {
            try service.changePassword(
                currentPasswordUTF8: Data(currentPassword.utf8),
                newPasswordUTF8: Data(newPassword.utf8)
            )
            // Clear any in-memory key and force re-unlock with the new password (keeps behavior predictable).
            vaultKey = nil
            isUnlocked = false
            password = ""
            setStatus("Password updated. Please unlock again.", isError: false)
        } catch {
            setStatus("Password update failed: \(error)", isError: true)
        }
    }

    // MARK: - Attempt limiting

    private var isLockedOut: Bool {
        if let until = lockoutUntil { return Date() < until }
        return false
    }

    private func registerFailedAttempt() {
        failedAttempts += 1
        if failedAttempts >= 5 {
            lockoutUntil = Date().addingTimeInterval(60)
        }
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusText = text
        statusIsError = isError
    }
}


