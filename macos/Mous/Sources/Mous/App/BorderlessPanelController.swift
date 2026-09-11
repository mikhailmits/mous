import AppKit
import MousCore
import SwiftUI

@MainActor
final class BorderlessPanelController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var tipWindow: NSWindow?
    private let store: AppStore
    private let tipChrome = SpendTipChrome()
    private let commandHints = CommandHintState()
    private var hasPositioned = false
    private var spaceObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    /// Opening the app can fire a spurious space-change and a leftover mouse-up
    /// from the Dock/terminal click. Ignore hide until this date.
    private var suppressHideUntil = Date.distantPast

    private var hoveringSpend = false
    private var hoveringSaved = false
    private var hoveringApp = false
    private var hoveringTip = false
    private var hoverGeneration = 0
    private var tipVisible = false
    /// Keyboard shortcut opened the tip; keep it until dismiss, not just hover.
    private var tipPinned = false
    private var commandHintGeneration = 0

    init(store: AppStore) {
        self.store = store
        super.init()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleLocalEvent(event) ?? event
        }
        observeLaunchSplash()
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func show() {
        suppressHideUntil = Date().addingTimeInterval(1)
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        if !hasPositioned {
            positionOnScreen(window)
            hasPositioned = true
        }
        stealFocus(window, attempt: 0)
    }

    private func stealFocus(_ window: NSWindow, attempt: Int) {
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
        guard attempt < 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let window = self.window else { return }
            if !NSApp.isActive || !window.isKeyWindow || !window.isVisible {
                self.stealFocus(window, attempt: attempt + 1)
            }
        }
    }

    func hide() {
        guard Date() >= suppressHideUntil else { return }
        // Stay up while the launch spin is playing so `mous dev` from a
        // terminal still shows the animation after the shell takes focus back.
        if store.showLaunchSplash { return }
        dismissTipImmediately()
        hideCommandHints()
        window?.orderOut(nil)
        window?.collectionBehavior.remove(.moveToActiveSpace)
    }

    private func observeLaunchSplash() {
        withObservationTracking {
            _ = store.showLaunchSplash
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeLaunchSplash()
                if !self.store.showLaunchSplash, !NSApp.isActive {
                    self.hide()
                }
            }
        }
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = MousPopup(
            store: store,
            commandHints: commandHints,
            onQuit: { [weak self] in self?.quitApp() },
            onSizeChange: { [weak self] size in self?.updateContentSize(size) },
            onSpendHover: { [weak self] inside in self?.noteSpendHover(inside) },
            onSavedHover: { [weak self] inside in self?.noteSavedHover(inside) },
            onAppHover: { [weak self] inside in self?.noteAppHover(inside) }
        )
        let hosting = ClearHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.masksToBounds = false
        if hosting.responds(to: Selector(("setDrawsBackground:"))) {
            hosting.setValue(false, forKey: "drawsBackground")
        }
        let fitting = hosting.fittingSize
        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // The window itself casts no shadow; each card draws its own.
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.animationBehavior = .utilityWindow
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.layer?.masksToBounds = false
        hosting.frame.size = fitting
        return window
    }

    /// Keeps the window hugging the SwiftUI content. Anchors the top edge so a
    /// height change (e.g. an error caption appearing) grows downward instead
    /// of making the popup jump.
    private func updateContentSize(_ size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        var frame = window.frame
        guard frame.size != size else { return }
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true)
        if tipVisible { layoutTip() }
    }

    func windowDidMove(_ notification: Notification) {
        if tipVisible { layoutTip() }
    }

    // MARK: - Command hints and shortcuts

    private static let commandHintDelay: TimeInterval = 0.4

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard window?.isKeyWindow == true else { return event }
        switch event.type {
        case .flagsChanged:
            noteCommandFlags(event.modifierFlags)
            return event
        case .keyDown:
            return handleCommandKey(event)
        default:
            return event
        }
    }

    private func noteCommandFlags(_ flags: NSEvent.ModifierFlags) {
        commandHintGeneration += 1
        let generation = commandHintGeneration
        if Self.isCommandOnly(flags) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandHintDelay) { [weak self] in
                guard let self, generation == self.commandHintGeneration else { return }
                guard Self.isCommandOnly(NSEvent.modifierFlags) else { return }
                guard self.store.hasLoadedDashboard else { return }
                withAnimation(self.hintAnimation) { self.commandHints.visible = true }
            }
        } else {
            hideCommandHints()
        }
    }

    private func hideCommandHints() {
        commandHintGeneration += 1
        guard commandHints.visible else { return }
        withAnimation(hintAnimation) { commandHints.visible = false }
    }

    private var hintAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.12)
            : .snappy(duration: 0.22)
    }

    private static func isCommandOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        let relevant = flags.intersection([.command, .shift, .option, .control])
        return relevant == .command
    }

    private func handleCommandKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            if tipVisible {
                tipPinned = false
                hideTip()
                return nil
            }
            return event
        }
        guard event.modifierFlags.contains(.command) else { return event }
        guard !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) else {
            return event
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "m":
            openTip(kind: .monthSpend)
            return nil
        case "x":
            openTip(kind: .expensive)
            return nil
        default:
            return event
        }
    }

    /// Demo/screenshot hook (`MOUS_DEMO_TIP`): open and pin a tip exactly
    /// as ⌘M / ⌘X would.
    func openTipFromDemo(kind: DashboardTipKind) {
        openTip(kind: kind)
    }

    private func openTip(kind: DashboardTipKind) {
        guard store.hasLoadedDashboard else { return }
        hoverGeneration += 1
        if tipVisible, tipPinned, tipChrome.kind == kind {
            tipPinned = false
            hideTip()
            return
        }
        tipChrome.kind = kind
        tipPinned = true
        showTip()
    }

    // MARK: - Spend tip (sibling panel, never overlays the cards)

    private static let tipGap: CGFloat = 8
    private static let preferredTipHeight: CGFloat = 320
    private static let minTipHeight: CGFloat = 44

    private func noteSpendHover(_ inside: Bool) {
        hoveringSpend = inside
        if inside { tipChrome.kind = .monthSpend }
        scheduleTip()
    }

    private func noteSavedHover(_ inside: Bool) {
        hoveringSaved = inside
        if inside { tipChrome.kind = .expensive }
        scheduleTip()
    }

    private func noteAppHover(_ inside: Bool) {
        hoveringApp = inside
        scheduleTip()
    }

    private func noteTipHover(_ inside: Bool) {
        hoveringTip = inside
        scheduleTip()
    }

    private var wantsTip: Bool {
        hoveringSpend || hoveringSaved || tipPinned || (tipVisible && (hoveringApp || hoveringTip))
    }

    private func scheduleTip() {
        hoverGeneration += 1
        let generation = hoverGeneration
        let want = wantsTip
        if want, tipVisible {
            layoutTip()
            return
        }
        let delay = want ? 0.12 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.hoverGeneration else { return }
            if want {
                self.showTip()
            } else {
                self.hideTip()
            }
        }
    }

    private func showTip() {
        if tipWindow == nil { tipWindow = makeTipWindow() }
        guard let tipWindow else { return }

        tipVisible = true
        layoutTip()
        tipWindow.orderFront(nil)

        if !tipChrome.appeared {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            DispatchQueue.main.async { [weak self] in
                guard let self, self.tipVisible else { return }
                withAnimation(reduce ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18)) {
                    self.tipChrome.appeared = true
                }
            }
        }
    }

    private func hideTip() {
        guard tipVisible else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduce ? 0.1 : 0.16
        withAnimation(.easeOut(duration: duration)) { tipChrome.appeared = false }
        let generation = hoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.hoverGeneration else { return }
            self.dismissTipImmediately()
        }
    }

    private func dismissTipImmediately() {
        hoverGeneration += 1
        tipVisible = false
        hoveringSpend = false
        hoveringSaved = false
        hoveringApp = false
        hoveringTip = false
        tipPinned = false
        tipChrome.appeared = false
        tipWindow?.orderOut(nil)
    }

    /// Usable gap between the visual cards and the screen's visible edge.
    private func usableSpace() -> (above: CGFloat, below: CGFloat, visible: NSRect, visualTop: CGFloat, visualBottom: CGFloat) {
        let parent = window?.frame ?? .zero
        let screen = NSScreen.screens.max(by: {
            $0.frame.intersection(parent).width * $0.frame.intersection(parent).height
                < $1.frame.intersection(parent).width * $1.frame.intersection(parent).height
        }) ?? window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? parent
        let visualTop = parent.maxY - MousPopup.shadowMargin
        let visualBottom = parent.minY + MousPopup.shadowMargin
        return (
            visible.maxY - visualTop - Self.tipGap,
            visualBottom - visible.minY - Self.tipGap,
            visible,
            visualTop,
            visualBottom
        )
    }

    /// A real tip needs ~96pt above the cards, under the menu bar. Less than
    /// that is "no space on top" — always park below the app.
    private func pickEdge() -> SpendTipEdge {
        usableSpace().above >= 96 ? .above : .below
    }

    private func layoutTip() {
        guard let parent = window, let tip = tipWindow else { return }
        let shadow = SpendTipCard.shadowMargin
        let space = usableSpace()
        let reported = tip.frame.size
        var visualHeight = reported.height > 1
            ? max(reported.height - shadow * 2, Self.minTipHeight)
            : Self.preferredTipHeight
        visualHeight = min(visualHeight, Self.preferredTipHeight)

        let edge = pickEdge()
        let room = max(edge == .above ? space.above : space.below, Self.minTipHeight)
        let maxVisual = min(Self.preferredTipHeight, room)
        if hoveringSaved {
            tipChrome.kind = .expensive
        } else if hoveringSpend {
            tipChrome.kind = .monthSpend
        }
        tipChrome.edge = edge
        tipChrome.maxHeight = maxVisual

        var size = reported.width > 1
            ? reported
            : NSSize(width: 244 + shadow * 2, height: min(visualHeight, maxVisual) + shadow * 2)
        size.height = min(size.height, maxVisual + shadow * 2)
        size.height = max(size.height, Self.minTipHeight + shadow * 2)

        // Spend tip lines up with the app's left; saved tip with the right.
        let appCardLeft = parent.frame.minX + MousPopup.shadowMargin
        let appCardRight = parent.frame.maxX - MousPopup.shadowMargin
        var x: CGFloat
        if tipChrome.kind == .expensive {
            x = appCardRight - (size.width - shadow)
        } else {
            x = appCardLeft - shadow
        }
        x = min(max(x, space.visible.minX + 8 - shadow), space.visible.maxX - size.width - 8 + shadow)

        let y: CGFloat
        switch edge {
        case .above:
            y = space.visualTop + Self.tipGap - shadow
        case .below:
            y = space.visualBottom - Self.tipGap - (size.height - shadow)
        }
        tip.setFrame(
            NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height),
            display: true
        )
    }

    private func updateTipSize(_ size: CGSize) {
        guard tipVisible, size.width > 0, size.height > 0, let tip = tipWindow else { return }
        var frame = tip.frame
        frame.size = size
        tip.setFrame(frame, display: false)
        layoutTip()
    }

    private func makeTipWindow() -> NSWindow {
        let root = SpendTipHost(
            store: store,
            chrome: tipChrome,
            onHover: { [weak self] inside in self?.noteTipHover(inside) },
            onSizeChange: { [weak self] size in self?.updateTipSize(size) }
        )
        let hosting = ClearHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.masksToBounds = false
        if hosting.responds(to: Selector(("setDrawsBackground:"))) {
            hosting.setValue(false, forKey: "drawsBackground")
        }
        let fitting = hosting.fittingSize
        let panel = TipPanel(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = false
        hosting.frame.size = fitting
        return panel
    }

    /// Centers horizontally, a bit below the top third of the screen.
    private func positionOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let frame = window.frame
        let x = visible.midX - frame.width / 2
        let y = visible.minY + visible.height * 0.58 - frame.height / 2
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}

private final class TipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        contentView?.scrollWheel(with: event)
    }
}

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        if responds(to: Selector(("setDrawsBackground:"))) {
            setValue(false, forKey: "drawsBackground")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}
