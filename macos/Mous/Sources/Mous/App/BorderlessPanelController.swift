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
    private let reportNotice: ReportNoticeChrome
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
    /// Last flags from a local event. Synthetic pid-posted command keys do
    /// not show up in `NSEvent.modifierFlags`.
    private var lastHintFlags: NSEvent.ModifierFlags = []

    init(store: AppStore, reportNotice: ReportNoticeChrome) {
        self.store = store
        self.reportNotice = reportNotice
        super.init()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !MousHarness.keepsPanelVisible else { return }
                self.hide()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .mouseMoved]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalEvent(event)
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
        if MousHarness.isHeadless {
            concealHeadless(window)
            window.acceptsMouseMovedEvents = true
            window.orderFrontRegardless()
            hasPositioned = true
            return
        }
        if !hasPositioned {
            positionOnScreen(window)
            hasPositioned = true
        }
        stealFocus(window, attempt: 0)
    }

    /// Invisible and off-screen so the harness never covers the user's display.
    private func concealHeadless(_ window: NSWindow) {
        window.alphaValue = 0
        window.hasShadow = false
        window.level = .normal
        window.collectionBehavior.insert(.ignoresCycle)
        window.collectionBehavior.insert(.stationary)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    }

    private func stealFocus(_ window: NSWindow, attempt: Int) {
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        if !commandHints.showSettings,
           !commandHints.showNotifications,
           !commandHints.showOptionsMenu,
           commandHints.focusedList == nil
        {
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
        }
        guard attempt < 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let window = self.window else { return }
            if !NSApp.isActive || !window.isKeyWindow || !window.isVisible {
                self.stealFocus(window, attempt: attempt + 1)
            }
        }
    }

    func hide() {
        if MousHarness.keepsPanelVisible { return }
        guard Date() >= suppressHideUntil else { return }
        // Stay up while the launch spin is playing so `mous dev` from a
        // terminal still shows the animation after the shell takes focus back.
        if store.showLaunchSplash { return }
        dismissTipImmediately()
        commandHints.focusedList = nil
        commandHints.showOptionsMenu = false
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
                if !self.store.showLaunchSplash, !NSApp.isActive, !MousHarness.keepsPanelVisible {
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
            reportNotice: reportNotice,
            onQuit: { [weak self] in self?.quitApp() },
            onEscape: { [weak self] in self?.handleEscape() ?? false },
            onSizeChange: { [weak self] size in self?.updateContentSize(size) },
            onSpendHover: { [weak self] inside in self?.noteSpendHover(inside) },
            onSavedHover: { [weak self] inside in self?.noteSavedHover(inside) },
            onAppHover: { [weak self] inside in self?.noteAppHover(inside) },
            onOpenSettings: { [weak self] in self?.prepareSettings() },
            onOpenNotifications: { [weak self] in self?.prepareNotifications() },
            onOpenOptionsMenu: { [weak self] in self?.prepareOptionsMenu() }
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
        window.title = "Mous"
        window.handleCancel = { [weak self] in self?.handleEscape() ?? false }
        window.contentView = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.layer?.masksToBounds = false
        hosting.frame.size = fitting
        if MousHarness.isHeadless {
            concealHeadless(window)
        }
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
        if MousHarness.isHeadless {
            frame.origin = NSPoint(x: -20000, y: -20000)
            window.setFrame(frame, display: false)
            window.alphaValue = 0
            return
        }
        window.setFrame(frame, display: true)
        if tipVisible { layoutTip() }
    }

    func windowDidMove(_ notification: Notification) {
        if tipVisible { layoutTip() }
    }

    // MARK: - Command hints and shortcuts

    private static let commandHintDelay: TimeInterval = 0.4

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            if handleEscape() {
                return nil
            }
            if MousHarness.isHeadless {
                return nil
            }
        }
        if MousHarness.isHeadless, event.type == .mouseMoved {
            ingestHeadlessMouse(event)
            return event
        }
        if MousHarness.isHeadless, event.type == .keyDown, !event.modifierFlags.contains(.command) {
            if ingestHeadlessTyping(event) {
                return nil
            }
        }
        if !MousHarness.isHeadless, window?.isKeyWindow != true {
            return event
        }
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

    /// Headless e2e posts keys to this pid while the panel is not key, so the
    /// field never becomes first responder. Feed letters into `store.text`.
    private func ingestHeadlessTyping(_ event: NSEvent) -> Bool {
        if commandHints.showSettings || commandHints.showNotifications || commandHints.focusedList != nil {
            return false
        }
        if event.keyCode == 36 {
            Task { await store.submit() }
            return true
        }
        if event.keyCode == 48 {
            _ = store.applyFxCalc()
            return true
        }
        if event.keyCode == 51 {
            if !store.text.isEmpty { store.text.removeLast() }
            return true
        }
        if let letter = Self.commandLetter(from: event) {
            store.text.append(contentsOf: letter)
            return true
        }
        if let chars = event.characters, chars.contains("+") {
            store.text.append("+")
            return true
        }
        if event.modifierFlags.contains(.shift), event.keyCode == 24 {
            store.text.append("+")
            return true
        }
        if event.keyCode == 69 {
            store.text.append("+")
            return true
        }
        if let typed = Self.typingKeyCodes[event.keyCode] {
            store.text.append(typed)
            return true
        }
        if let raw = event.charactersIgnoringModifiers {
            let allowed = raw.filter {
                $0.isNumber || $0 == "." || $0 == " " || $0 == "+" || $0 == "-" || $0 == "\u{2212}"
            }
            if !allowed.isEmpty {
                store.text.append(contentsOf: allowed)
                return true
            }
        }
        return false
    }

    private func ingestHeadlessMouse(_ event: NSEvent) {
        guard let window,
              commandHints.focusedList == nil,
              !commandHints.showSettings,
              !commandHints.showNotifications,
              !commandHints.showOptionsMenu
        else { return }
        let size = window.frame.size
        guard size.width > 1, size.height > 1 else { return }
        let loc = event.locationInWindow
        let xFrac = loc.x / size.width
        let yFromTop = 1 - (loc.y / size.height)
        noteSpendHover(xFrac < 0.45 && yFromTop < 0.42)
        noteSavedHover(xFrac > 0.68 && yFromTop < 0.55 && yFromTop > 0.12)
    }

    private func noteCommandFlags(_ flags: NSEvent.ModifierFlags) {
        lastHintFlags = flags
        commandHintGeneration += 1
        let generation = commandHintGeneration
        if Self.isCommandOnly(flags) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandHintDelay) { [weak self] in
                guard let self, generation == self.commandHintGeneration else { return }
                guard Self.isCommandOnly(self.lastHintFlags) else { return }
                guard self.store.hasLoadedDashboard else { return }
                guard !self.commandHints.showSettings else { return }
                guard !self.commandHints.showNotifications else { return }
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

    /// Carbon letter key codes. Synthetic CG events often have an empty
    /// `charactersIgnoringModifiers`.
    private static let letterKeyCodes: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c",
        9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k",
        45: "n", 46: "m",
    ]

    /// Digits and punctuation. Synthetic CG events often have empty `characters`.
    private static let typingKeyCodes: [UInt16: Character] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 47: ".", 49: " ",
    ]

    private static func commandLetter(from event: NSEvent) -> String? {
        if let raw = event.charactersIgnoringModifiers?.lowercased(),
           let first = raw.first,
           first.isLetter
        {
            return String(first)
        }
        if let ch = letterKeyCodes[event.keyCode] {
            return String(ch)
        }
        return nil
    }

    /// Esc: ⋯ menu → home; same-key duplicates; clear the entry if home has text;
    /// then settings / inbox / list / tip; otherwise let it quit.
    private var swallowEscape = false

    private func handleEscape() -> Bool {
        if commandHints.showOptionsMenu {
            withAnimation(optionsCloseAnimation) { commandHints.showOptionsMenu = false }
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
            noteSwallowEscape()
            return true
        }
        if swallowEscape {
            swallowEscape = false
            return true
        }
        let onHome = !commandHints.showSettings
            && !commandHints.showNotifications
            && commandHints.focusedList == nil
            && !tipVisible
        if onHome, !store.text.isEmpty {
            store.text = ""
            noteSwallowEscape()
            return true
        }
        if commandHints.showSettings {
            withAnimation(hintAnimation) { commandHints.showSettings = false }
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
            noteSwallowEscape()
            return true
        }
        if commandHints.showNotifications {
            if reportNotice.popSelection() {
                noteSwallowEscape()
                return true
            }
            reportNotice.closeInbox()
            withAnimation(hintAnimation) { commandHints.showNotifications = false }
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
            noteSwallowEscape()
            return true
        }
        if commandHints.focusedList != nil {
            restoreDashboard()
            noteSwallowEscape()
            return true
        }
        if tipVisible {
            tipPinned = false
            hideTip()
            noteSwallowEscape()
            return true
        }
        return false
    }

    /// Same-key Esc can hit the monitor, `onExitCommand`, and `cancelOperation`.
    /// Drop the flag on the next turn so the following Esc can clear or quit.
    private func noteSwallowEscape() {
        swallowEscape = true
        DispatchQueue.main.async { [weak self] in
            self?.swallowEscape = false
        }
    }

    private var optionsCloseAnimation: Animation {
        .easeOut(duration: 0.12)
    }

    private func prepareOptionsMenu() {
        dismissTipImmediately()
        commandHints.focusedList = nil
        commandHints.showSettings = false
        commandHints.showNotifications = false
    }

    private func prepareSettings() {
        dismissTipImmediately()
        hideCommandHints()
        commandHints.focusedList = nil
        commandHints.showOptionsMenu = false
        commandHints.showNotifications = false
    }

    private func prepareNotifications() {
        dismissTipImmediately()
        hideCommandHints()
        commandHints.focusedList = nil
        commandHints.showOptionsMenu = false
        commandHints.showSettings = false
        reportNotice.closeInbox()
    }

    private func handleCommandKey(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command) else { return event }
        guard !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) else {
            return event
        }
        guard !store.showLaunchSplash else { return event }
        let key = Self.commandLetter(from: event)
        if MousHarness.isHeadless, key == "a" {
            store.text = ""
            return nil
        }
        if commandHints.showSettings || commandHints.showNotifications {
            return event
        }
        if commandHints.showOptionsMenu {
            switch key {
            case "o":
                withAnimation(optionsCloseAnimation) { commandHints.showOptionsMenu = false }
                return nil
            case "s":
                openSettingsFromShortcut()
                return nil
            case "n":
                openNotificationsFromShortcut()
                return nil
            default:
                return event
            }
        }
        switch key {
        case "o":
            openOptionsFromShortcut()
            return nil
        case "s":
            openSettingsFromShortcut()
            return nil
        case "n":
            openNotificationsFromShortcut()
            return nil
        case "m":
            openTip(kind: .monthSpend)
            return nil
        case "x":
            openTip(kind: .expensive)
            return nil
        case "f":
            toggleFocusedList()
            return nil
        default:
            return event
        }
    }

    /// ⌘O: open or close the ⋯ menu.
    private func openOptionsFromShortcut() {
        prepareOptionsMenu()
        withAnimation(hintAnimation) { commandHints.showOptionsMenu = true }
    }

    /// ⌘S: Settings, from home or the open ⋯ menu.
    private func openSettingsFromShortcut() {
        prepareSettings()
        withAnimation(hintAnimation) { commandHints.showSettings = true }
    }

    /// ⌘N: Notifications, from home or the open ⋯ menu.
    private func openNotificationsFromShortcut() {
        prepareNotifications()
        withAnimation(hintAnimation) { commandHints.showNotifications = true }
    }

    /// macOS report banner: open the matching inbox row (or the newest unread).
    func openFromReportAlert(capturedAt: TimeInterval? = nil) {
        show()
        prepareNotifications()
        withAnimation(hintAnimation) { commandHints.showNotifications = true }
        reportNotice.selectFromAlert(capturedAt: capturedAt)
    }

    /// Demo/screenshot hook (`MOUS_DEMO_TIP`): open and pin a tip exactly
    /// as ⌘M / ⌘X would.
    func openTipFromDemo(kind: DashboardTipKind) {
        openTip(kind: kind)
    }

    private func openTip(kind: DashboardTipKind) {
        guard store.hasLoadedDashboard else { return }
        hoverGeneration += 1
        if commandHints.focusedList != nil {
            if commandHints.focusedList == kind {
                restoreDashboard()
            } else {
                withAnimation(hintAnimation) { commandHints.focusedList = kind }
            }
            return
        }
        if tipVisible, tipPinned, tipChrome.kind == kind {
            tipPinned = false
            hideTip()
            return
        }
        tipChrome.kind = kind
        tipPinned = true
        showTip()
    }

    /// ⌘F: swap the dashboard for the list in this window, or restore it.
    private func toggleFocusedList() {
        guard store.hasLoadedDashboard else { return }
        if commandHints.focusedList != nil {
            restoreDashboard()
            return
        }
        let kind: DashboardTipKind
        if tipVisible {
            kind = tipChrome.kind
        } else if hoveringSaved {
            kind = .expensive
        } else {
            kind = .monthSpend
        }
        dismissTipImmediately()
        withAnimation(hintAnimation) { commandHints.focusedList = kind }
    }

    private func restoreDashboard() {
        hoverGeneration += 1
        withAnimation(hintAnimation) { commandHints.focusedList = nil }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }

    // MARK: - Spend tip (sibling panel, never overlays the cards)

    private static let tipGap: CGFloat = 8
    private static let preferredTipHeight: CGFloat = 320
    private static let minTipHeight: CGFloat = 44

    private func noteSpendHover(_ inside: Bool) {
        hoveringSpend = inside
        if inside, commandHints.focusedList == nil { tipChrome.kind = .monthSpend }
        scheduleTip()
    }

    private func noteSavedHover(_ inside: Bool) {
        hoveringSaved = inside
        if inside, commandHints.focusedList == nil { tipChrome.kind = .expensive }
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
        if commandHints.focusedList != nil
            || commandHints.showSettings
            || commandHints.showNotifications
            || commandHints.showOptionsMenu
        {
            return false
        }
        return hoveringSpend || hoveringSaved || tipPinned || (tipVisible && (hoveringApp || hoveringTip))
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
        if MousHarness.isHeadless {
            concealHeadless(tipWindow)
        }
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
        if MousHarness.isHeadless {
            concealHeadless(tip)
            return
        }
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
        if !tipPinned {
            if hoveringSaved {
                tipChrome.kind = .expensive
            } else if hoveringSpend {
                tipChrome.kind = .monthSpend
            }
        }
        tipChrome.edge = edge
        tipChrome.maxHeight = maxVisual

        var size = reported.width > 1
            ? reported
            : NSSize(width: SpendTipCard.compactWidth + shadow * 2, height: min(visualHeight, maxVisual) + shadow * 2)
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
            commandHints: commandHints,
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
        if MousHarness.isHeadless {
            concealHeadless(panel)
        }
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
    var handleCancel: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if handleCancel?() == true { return }
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
