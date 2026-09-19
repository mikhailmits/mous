import MousCore
import SwiftUI

struct MousPopup: View {
    @Bindable var store: AppStore
    @Bindable var commandHints: CommandHintState
    @Bindable var reportNotice: ReportNoticeChrome
    var onQuit: () -> Void = {}
    var onEscape: () -> Bool = { false }
    var onSizeChange: (CGSize) -> Void = { _ in }
    var onSpendHover: (Bool) -> Void = { _ in }
    var onSavedHover: (Bool) -> Void = { _ in }
    var onAppHover: (Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onOpenNotifications: () -> Void = {}
    var onOpenOptionsMenu: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var homeHeight: CGFloat = 0
    @State private var colorScheme = MousAppearance.colorScheme(from: MousConfigFile.load().theme)

    /// Width of the two cards. The window is wider than this by `shadowMargin`
    /// on each side so the card shadows can render on the transparent glass.
    static let cardWidth: CGFloat = 432
    static let shadowMargin: CGFloat = 32

    var body: some View {
        Group {
            if store.showLaunchSplash {
                LaunchSplash()
            } else if commandHints.showSettings {
                SettingsCard(onClose: closeSettings)
            } else if commandHints.showNotifications {
                NotificationsCard(notice: reportNotice, onClose: closeNotifications)
            } else if let kind = commandHints.focusedList {
                FocusedSpendList(
                    store: store,
                    kind: kind,
                    height: max(homeHeight, 200),
                    showCommandHints: commandHints.visible,
                    reduceMotion: reduceMotion
                )
            } else {
                homeStack
                    .overlay {
                        if commandHints.showOptionsMenu {
                            OptionsMenuDismissHit(action: closeOptionsMenu)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        OptionsMenuButton(
                            isOpen: $commandHints.showOptionsMenu,
                            unreadCount: reportNotice.unreadCount,
                            onSettings: openSettings,
                            onNotifications: openNotifications,
                            showCommandHints: commandHints.visible,
                            reduceMotion: reduceMotion,
                            dimmed: !store.text.isEmpty && !commandHints.showOptionsMenu
                        )
                        .padding(8)
                    }
            }
        }
        .frame(width: Self.cardWidth)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22), value: store.showLaunchSplash)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: commandHints.focusedList)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: commandHints.showSettings)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: commandHints.showNotifications)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: reportNotice.unreadCount)
        .onChange(of: commandHints.showOptionsMenu) { _, open in
            if open { onOpenOptionsMenu() }
        }
        .onChange(of: commandHints.showSettings) { _, showing in
            if !showing {
                colorScheme = MousAppearance.colorScheme(from: MousConfigFile.load().theme)
                Task { await store.reloadPreferences() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mousAppearanceDidChange)) { notification in
            guard let raw = notification.object as? String else { return }
            colorScheme = MousAppearance.colorScheme(from: raw)
        }
        .preferredColorScheme(colorScheme)
        .modifier(MousThemedChrome())
        .padding(Self.shadowMargin)
        .contentShape(Rectangle())
        .onHover { onAppHover($0) }
        .background(.clear)
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.98), anchor: .top)
        .offset(y: appeared || reduceMotion ? 0 : -6)
        .opacity(appeared ? 1 : 0)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onSizeChange(proxy.size) }
                    .onChange(of: proxy.size) { _, new in onSizeChange(new) }
            }
        }
        .onExitCommand {
            _ = onEscape()
        }
        .task { await store.appear() }
        .onAppear {
            // Short, native-feeling entrance: fade + slight settle from the
            // anchor edge, no bounce. Reduce Motion gets a plain fade.
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.15)) { appeared = true }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { appeared = true }
            }
        }
    }

    private var homeStack: some View {
        VStack(spacing: 8) {
            DashboardCard(
                snapshot: store.snapshot,
                hasLoaded: store.hasLoadedDashboard,
                isRefreshing: store.isRefreshing,
                statusMessage: store.statusMessage,
                currencyCode: store.displayCurrencyCode,
                hideBalance: store.hideBalance,
                onSpendHover: { inside in
                    guard store.hasLoadedDashboard else { return }
                    onSpendHover(inside)
                },
                onSavedHover: { inside in
                    guard store.hasLoadedDashboard else { return }
                    onSavedHover(inside)
                },
                showCommandHints: commandHints.visible
            )
            EntryCard(
                store: store,
                commitTick: store.commitTick,
                rejectTick: store.rejectTick
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { homeHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in homeHeight = height }
            }
        }
    }

    private func openSettings() {
        onOpenSettings()
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
            commandHints.showOptionsMenu = false
            commandHints.showNotifications = false
            commandHints.showSettings = true
        }
    }

    private func openNotifications() {
        onOpenNotifications()
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
            commandHints.showOptionsMenu = false
            commandHints.showSettings = false
            commandHints.showNotifications = true
        }
    }

    private func closeOptionsMenu() {
        withAnimation(.easeOut(duration: 0.12)) {
            commandHints.showOptionsMenu = false
        }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }

    private func closeSettings() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
            commandHints.showSettings = false
        }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }

    private func closeNotifications() {
        reportNotice.closeInbox()
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
            commandHints.showNotifications = false
        }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }
}
