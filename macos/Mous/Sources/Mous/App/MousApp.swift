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
        let panel = BorderlessPanelController(store: store)
        self.panel = panel
        panel.show()
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
