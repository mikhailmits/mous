import MousCore
import SwiftUI

struct MousPopup: View {
    @Bindable var store: AppStore
    @Bindable var commandHints: CommandHintState
    var onQuit: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }
    var onSpendHover: (Bool) -> Void = { _ in }
    var onSavedHover: (Bool) -> Void = { _ in }
    var onAppHover: (Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onOpenOptionsMenu: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var homeHeight: CGFloat = 0
    @State private var theme = MousTheme.parse(MousConfigFile.load().theme)

    /// Width of the two cards. The window is wider than this by `shadowMargin`
    /// on each side so the card shadows can render on the transparent glass.
    static let cardWidth: CGFloat = 432
    static let shadowMargin: CGFloat = 32

    var body: some View {
        Group {
            // Read hasLoadedDashboard in-body so Observation always invalidates
            // when the first fetch succeeds (computed showLaunchSplash alone can
            // leave the logo spin up after a good load).
            if store.showLaunchSplash && !store.hasLoadedDashboard {
                LaunchSplash()
            } else if commandHints.showSettings {
                SettingsCard(onClose: closeSettings)
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
                            onSettings: openSettings,
                            showCommandHints: commandHints.visible,
                            reduceMotion: reduceMotion,
                            dimmed: !store.text.isEmpty && !commandHints.showOptionsMenu
                        )
                        .padding(8)
                    }
            }
        }
        .frame(width: Self.cardWidth)
        .animation(MousMotion.fade(reduceMotion: reduceMotion), value: store.showLaunchSplash)
        .animation(MousMotion.fade(reduceMotion: reduceMotion), value: store.hasLoadedDashboard)
        .animation(MousMotion.spring(reduceMotion: reduceMotion), value: commandHints.focusedList)
        .animation(MousMotion.spring(reduceMotion: reduceMotion), value: commandHints.showSettings)
        .onChange(of: commandHints.showOptionsMenu) { _, open in
            if open { onOpenOptionsMenu() }
        }
        .onChange(of: commandHints.showSettings) { _, showing in
            if !showing {
                theme = MousTheme.parse(MousConfigFile.load().theme)
                Task { await store.reloadPreferences() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mousAppearanceDidChange)) { notification in
            if let raw = notification.object as? String {
                theme = MousTheme.parse(raw)
            } else if let next = notification.object as? MousTheme {
                theme = next
            }
        }
        .preferredColorScheme(theme.isLight ? .light : .dark)
        .modifier(MousThemedChrome(theme: theme))
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
        .task { await store.appear() }
        .onAppear {
            // Short, native-feeling entrance: fade + slight settle from the
            // anchor edge, no bounce. Reduce Motion gets a plain fade.
            withAnimation(MousMotion.spring(reduceMotion: reduceMotion)) { appeared = true }
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
                hideBalance: store.amountsConcealed,
                onToggleHide: { store.toggleHideBalance() },
                onPeek: { store.balancePeek = $0 },
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
        withAnimation(MousMotion.spring(reduceMotion: reduceMotion)) {
            commandHints.showOptionsMenu = false
            commandHints.showSettings = true
        }
    }

    private func closeOptionsMenu() {
        withAnimation(MousMotion.quick(reduceMotion: reduceMotion)) {
            commandHints.showOptionsMenu = false
        }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }

    private func closeSettings() {
        withAnimation(MousMotion.spring(reduceMotion: reduceMotion)) {
            commandHints.showSettings = false
        }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }
}
