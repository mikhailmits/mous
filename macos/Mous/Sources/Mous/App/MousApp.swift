import AppKit
import MousCore

/// Plain AppKit entry point. No SwiftUI `App`/`Settings` scene — the borderless
/// panel with the two cards is the only window this app ever shows.
@main
enum MousMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Keep the delegate alive for the lifetime of the app.
        objc_setAssociatedObject(app, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }
}

private nonisolated(unsafe) var delegateKey: UInt8 = 0

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppStore()
    private var panel: BorderlessPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applySourceTreeDockIconIfNeeded()
        LocalBackend.shared.kickoff()
        let panel = BorderlessPanelController(store: store)
        self.panel = panel
        panel.show()
        if LocalBackend.shared.isBundled {
            Task { @MainActor [weak self] in
                await LocalBackend.shared.start()
                self?.runDemoDirector()
            }
        } else {
            runDemoDirector()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LocalBackend.shared.stop()
    }

    /// `swift run` / `mous dev` are a bare binary, so the Dock would otherwise
    /// show a generic icon. The bundled .app uses `Icon/AppIcon.icns` via Info.plist.
    private func applySourceTreeDockIconIfNeeded() {
        guard !LocalBackend.shared.isBundled, let image = MousIcons.appIcon else { return }
        NSApp.applicationIconImage = image
    }

    /// Screenshot/demo mode, driven by environment variables:
    /// `MOUS_DEMO_TYPE` types a line into the field for real (parse + post),
    /// `MOUS_DEMO_TIP` opens a tip ("history" or "expensive") once loaded.
    private func runDemoDirector() {
        let env = ProcessInfo.processInfo.environment
        let tip = env["MOUS_DEMO_TIP"]
        let line = env["MOUS_DEMO_TYPE"]
        guard tip != nil || line != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.store.hasLoadedDashboard {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let line {
                for char in line {
                    self.store.text.append(char)
                    try? await Task.sleep(nanoseconds: 90_000_000)
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                await self.store.submit()
            }
            if let tip {
                self.panel?.openTipFromDemo(kind: tip == "expensive" ? .expensive : .monthSpend)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        panel?.show()
    }

    func applicationDidResignActive(_ notification: Notification) {
        panel?.hide()
    }
}
