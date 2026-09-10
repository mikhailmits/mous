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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Width of the two cards. The window is wider than this by `shadowMargin`
    /// on each side so the card shadows can render on the transparent glass.
    static let cardWidth: CGFloat = 432
    static let shadowMargin: CGFloat = 32

    var body: some View {
        VStack(spacing: 8) {
            DashboardCard(
                snapshot: store.snapshot,
                hasLoaded: store.hasLoadedDashboard,
                isRefreshing: store.isRefreshing,
                statusMessage: store.statusMessage,
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
        .frame(width: Self.cardWidth)
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
        .onExitCommand { onQuit() }
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
}
