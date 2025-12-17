import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    @ObservedObject private var vm: VaultViewModel

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(vm: VaultViewModel) {
        _vm = ObservedObject(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            vaultControls

            if vm.isUnlocked {
                dropZone
                fileList
            } else {
                lockedPlaceholder
            }

            if let status = vm.statusText {
                statusBanner(status, isError: vm.statusIsError)
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)
                .cornerRadius(10)
                .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("PandorasVault")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Lock files into an encrypted vault (AES-256-GCM).")
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Group {
            if vm.isUnlocked {
                pill("Unlocked", color: .green)
            } else if vm.isInitialized {
                pill("Locked", color: .orange)
            } else {
                pill("No Vault", color: .gray)
            }
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var vaultControls: some View {
        HStack(spacing: 12) {
            SecureField(vm.isInitialized ? "Enter password to unlock…" : "Create a vault password…", text: $vm.password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            if !vm.isInitialized {
                Button("Create Vault") { vm.createVault() }
            } else if !vm.isUnlocked {
                Button("Unlock") { vm.unlock() }
            } else {
                Button("Lock") { vm.lock() }
            }

            Spacer()

            Button("Refresh") {
                Task { await vm.refresh() }
            }
        }
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 10) {
            Text(vm.isInitialized ? "Enter your password to unlock the vault." : "Create a vault to start encrypting files.")
                .foregroundColor(.secondary)
            Text("Drag & drop is available once unlocked.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(vm.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.windowBackgroundColor).opacity(0.6)))

            VStack(spacing: 6) {
                Text("Drag & drop files here")
                    .font(.system(size: 16, weight: .semibold))
                Text("Files are encrypted and stored in Application Support.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .frame(height: 120)
        .onDrop(of: [DropLoader.fileURLUTI], isTargeted: $vm.isDropTargeted) { providers in
            DropLoader.loadFileURLs(from: providers) { urls in
                vm.addDroppedFileURLs(urls)
            }
            return true
        }
        .animation(.easeInOut(duration: 0.15))
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vault Files")
                .font(.headline)

            if vm.items.isEmpty {
                Text("No files yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                List {
                    ForEach(vm.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.originalFileName)
                                    .lineLimit(1)
                                Text("\(item.originalByteCount) bytes • \(dateFormatter.string(from: item.addedAt))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Export") { vm.export(item) }
                            Button("Delete") { vm.delete(item) }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private func statusBanner(_ text: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isError ? Color.red : Color.green)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.footnote)
            Spacer()
        }
        .padding(10)
        .background((isError ? Color.red : Color.green).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.2))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var vm: VaultViewModel

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Update your vault password.")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
                Spacer()
            }

            GroupBox(label: Text("Change Password")) {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("Current password", text: $currentPassword)
                    SecureField("New password", text: $newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)

                    HStack {
                        Spacer()
                        Button("Update Password") {
                            vm.changePassword(
                                currentPassword: currentPassword,
                                newPassword: newPassword,
                                confirmNewPassword: confirmPassword
                            )
                            currentPassword = ""
                            newPassword = ""
                            confirmPassword = ""
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(8)
            }

            if let status = vm.statusText {
                // Reuse status banner styling from main UI.
                HStack(spacing: 10) {
                    Circle()
                        .fill(vm.statusIsError ? Color.red : Color.green)
                        .frame(width: 10, height: 10)
                    Text(status)
                        .font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background((vm.statusIsError ? Color.red : Color.green).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 340)
    }
}

// MARK: - About

struct AboutView: View {
    private var versionString: String {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        let b = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .cornerRadius(22)

            Text("PandorasVault")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text(versionString)
                .foregroundColor(.secondary)
                .font(.footnote)

            Divider()
                .padding(.horizontal, 30)

            (
                Text("Developed by ")
                + Text("Hephaestus Systems").bold()
                + Text(" (Uner YILMAZ)")
            )
            .font(.system(size: 13))
            .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 320)
    }
}

enum DropLoader {
    static let fileURLUTI = "public.file-url"

    static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(fileURLUTI) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: fileURLUTI, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                } else if let url = item as? URL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }
}
