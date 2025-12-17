import AppKit
import SwiftUI
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private weak var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("PandorasVault: applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.regular)

        // Defer window creation to the next run-loop tick. In some launch contexts (notably
        // Xcode/LaunchServices), a window can exist but fail to become visible/frontmost
        // unless we re-assert on the main queue.
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }

        // One extra re-assert shortly after launch helps when activation ordering is odd.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showMainWindow()
            NSLog("PandorasVault: windows=%d, keyWindow=%@", NSApp.windows.count, String(describing: NSApp.keyWindow))
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Xcode (and LaunchServices) can start apps with “don’t make frontmost”.
        // Re-assert window visibility once we’re active.
        showMainWindow()
        NSLog("PandorasVault: didBecomeActive -> reasserted window")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Dock icon should always bring back the main window.
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Window management

    @MainActor
    private func showMainWindow() {
        if let existing = windowController?.window ?? window {
            existing.makeKeyAndOrderFront(nil)
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.orderFrontRegardless()
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        let vm = VaultViewModel()
        let contentView = ContentView(vm: vm)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "PandorasVault"
        w.isReleasedWhenClosed = false

        // Put it somewhere obvious.
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let size = NSSize(width: 720, height: 480)
            let origin = NSPoint(
                x: vf.origin.x + (vf.size.width - size.width) / 2.0,
                y: vf.origin.y + (vf.size.height - size.height) / 2.0
            )
            w.setFrame(NSRect(origin: origin, size: size), display: true)
        } else {
            w.center()
        }

        // Avoid “invisible window” issues if the system restores a bad frame across launches.
        w.setFrameAutosaveName("PandorasVaultMainWindow")
        w.contentView = NSHostingView(rootView: contentView)

        let wc = NSWindowController(window: w)
        self.windowController = wc
        self.window = w

        wc.showWindow(nil)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSLog("PandorasVault: showMainWindow created+shown, frame=%@", NSStringFromRect(w.frame))
    }
}
