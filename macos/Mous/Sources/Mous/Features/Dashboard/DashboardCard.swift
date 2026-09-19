import Observation
import MousCore
import SwiftUI

@Observable
@MainActor
final class CommandHintState {
    var visible = false
    /// In-place list replacing the dashboard. `nil` is the normal home view.
    var focusedList: DashboardTipKind? = nil
    var showSettings = false
    var showNotifications = false
    var showOptionsMenu = false
}

struct DashboardCard: View {
    var snapshot: DashboardSnapshot
    /// True once at least one fetch has succeeded. Until then, amounts show 0.00.
    var hasLoaded: Bool
    var isRefreshing: Bool
    var statusMessage: String?
    /// ISO 4217 code for the Settings currency.
    var currencyCode: String
    var hideBalance: Bool = false
    var onSpendHover: (Bool) -> Void = { _ in }
    var onSavedHover: (Bool) -> Void = { _ in }
    var showCommandHints: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mousAccent) private var mousAccent
    @State private var spendHotspot: CGRect = .zero
    @State private var spentTodayMask = BalanceMask.make()
    @State private var leftMask = BalanceMask.make()
    @State private var spentMonthMask = BalanceMask.make()
    @State private var lastTick: TickToken?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spent today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .mousTick(numeric: false, reduceMotion: reduceMotion)
                    .spendHotspot()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    heroValue
                        .spendHotspot()
                    leftLabel
                }
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Spent this month.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .mousTick(numeric: false, reduceMotion: reduceMotion)
                    monthValue
                }
                .spendHotspot()
                Spacer(minLength: 12)
                savedLabel
                    .contentShape(Rectangle())
                    .onHover { onSavedHover($0) }
            }
            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .mousTick(numeric: false, reduceMotion: reduceMotion)
                    .transition(.opacity)
            }
        }
        .coordinateSpace(name: "spendHotspot")
        .onPreferenceChange(SpendHotspotKey.self) { rects in
            let box = rects.reduce(CGRect.null) { $0.union($1) }
            spendHotspot = box.isNull ? .zero : box.insetBy(dx: -8, dy: -6)
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: max(spendHotspot.width, 0), height: max(spendHotspot.height, 0))
                .offset(x: spendHotspot.minX, y: spendHotspot.minY)
                .contentShape(Rectangle())
                .onHover { onSpendHover($0) }
        }
        .padding(20)
        .overlay(alignment: .topLeading) {
            CommandKeycap(letter: "m", visible: showCommandHints, reduceMotion: reduceMotion)
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            CommandKeycap(letter: "x", visible: showCommandHints, reduceMotion: reduceMotion)
                .padding(8)
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .mousCard()
        .redacted(reason: isRefreshing && !hasLoaded ? .placeholder : [])
        .animation(tickAnimation, value: tickToken)
        .onAppear {
            if lastTick == nil { lastTick = tickToken }
            if hideBalance { reshuffleMasks() }
        }
        .onChange(of: hideBalance) { _, on in
            if on { reshuffleMasks() }
        }
        .onChange(of: displayedSpentToday) { _, _ in
            if hideBalance { spentTodayMask = freshMask() }
        }
        .onChange(of: snapshot.left) { _, _ in
            if hideBalance { leftMask = freshMask() }
        }
        .onChange(of: displayedSpentMonth) { _, _ in
            if hideBalance { spentMonthMask = freshMask() }
        }
        .onChange(of: tickToken) { _, new in
            lastTick = new
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Command M shows History. Command X shows Most expensive. Command F expands an open list.")
    }

    /// Any visible dashboard change — numbers, load state, or status copy.
    private var tickToken: TickToken {
        TickToken(
            spentToday: displayedSpentToday,
            spentMonth: displayedSpentMonth,
            left: hasLoaded ? snapshot.left : 0,
            saved: hasLoaded ? snapshot.savedRatio : nil,
            hasLoaded: hasLoaded,
            status: statusMessage ?? "",
            currencyCode: currencyCode,
            hideBalance: hideBalance
        )
    }

    private struct TickToken: Equatable {
        var spentToday: Double
        var spentMonth: Double
        var left: Double
        var saved: Double?
        var hasLoaded: Bool
        var status: String
        var currencyCode: String
        var hideBalance: Bool
    }

    private var tickAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        return .snappy(duration: Self.snappyDuration(from: lastTick, to: tickToken))
    }

    private static func snappyDuration(from old: TickToken?, to new: TickToken) -> Double {
        guard let old else { return 0.28 }
        let delta = max(
            abs(new.spentToday - old.spentToday),
            abs(new.left - old.left),
            abs(new.spentMonth - old.spentMonth)
        )
        if delta < 0.005 { return 0.22 }
        let scale = max(
            abs(old.left), abs(new.left),
            abs(old.spentMonth), abs(new.spentMonth),
            abs(old.spentToday), abs(new.spentToday),
            25
        )
        let mag = min(1, delta / scale)
        return min(0.6, 0.22 + mag * 0.38)
    }

    @ViewBuilder
    private var heroValue: some View {
        Text(hideBalance ? spentTodayMask : displayedSpentToday.formatted(money))
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .mousTick(numeric: true, reduceMotion: reduceMotion)
    }

    private var displayedSpentToday: Double {
        guard hasLoaded else { return 0 }
        let spent = snapshot.spentToday
        return spent > 0 ? -spent : 0
    }

    @ViewBuilder
    private var leftLabel: some View {
        // Bold rounded weight keeps the sampled mark color readable
        // against the material at the themed opacity.
        Text(hideBalance ? "\(leftMask) left" : "\(hasLoaded ? snapshot.left : 0, format: money) left")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(mousAccent)
            .monospacedDigit()
            .mousTick(numeric: true, reduceMotion: reduceMotion)
    }

    private var displayedSpentMonth: Double {
        guard hasLoaded else { return 0 }
        let spent = snapshot.spentMonth
        return spent > 0 ? -spent : 0
    }

    @ViewBuilder
    private var monthValue: some View {
        // Secondary tier: quieter than the hero, still legible as an amount.
        Text(hideBalance ? spentMonthMask : displayedSpentMonth.formatted(money))
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .mousTick(numeric: true, reduceMotion: reduceMotion)
    }

    private var savedLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(savedText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .mousTick(numeric: true, reduceMotion: reduceMotion)
            Text("this month")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .mousTick(numeric: false, reduceMotion: reduceMotion)
        }
    }

    private var savedText: String {
        guard hasLoaded else { return "Saved 0%." }
        guard let ratio = snapshot.savedRatio else { return "Saved 0%." }
        return "Saved \(ratio.formatted(Self.percent))."
    }

    private var accessibilityText: String {
        if !hasLoaded {
            var text = "Spent today 0, 0 left, spent this month 0, saved 0% this month"
            if let statusMessage, !statusMessage.isEmpty {
                text += ", \(statusMessage)"
            }
            return text
        }
        let today = hideBalance ? spentTodayMask : displayedSpentToday.formatted(money)
        let left = hideBalance ? leftMask : snapshot.left.formatted(money)
        let month = hideBalance ? spentMonthMask : displayedSpentMonth.formatted(money)
        let saved: String
        if let ratio = snapshot.savedRatio {
            saved = ratio.formatted(Self.percent)
        } else {
            saved = "0%"
        }
        var text = "Spent today \(today), \(left) left, spent this month \(month), saved \(saved) this month"
        if let statusMessage, !statusMessage.isEmpty {
            text += ", \(statusMessage)"
        }
        return text
    }

    private func reshuffleMasks() {
        let style = hideStyle
        spentTodayMask = BalanceMask.make(style: style)
        leftMask = BalanceMask.make(style: style)
        spentMonthMask = BalanceMask.make(style: style)
    }

    private func freshMask() -> String {
        BalanceMask.make(style: hideStyle)
    }

    private var hideStyle: HideBalanceStyle {
        HideBalanceStyle.parse(MousConfigFile.load().hideBalanceStyle)
    }

    private var money: FloatingPointFormatStyle<Double>.Currency {
        FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
            .precision(.fractionLength(2))
    }

    private static let percent = FloatingPointFormatStyle<Double>.Percent()
        .precision(.fractionLength(0))
}

struct CommandKeycap: View {
    var letter: String
    var visible: Bool
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "command")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(letter)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(width: 36, height: 24)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible || reduceMotion ? 1 : 0.86)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22),
            value: visible
        )
        .allowsHitTesting(false)
        .accessibilityHidden(!visible)
        .accessibilityLabel("Command \(letter)")
    }
}

private struct SpendHotspotKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func spendHotspot() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SpendHotspotKey.self,
                    value: [proxy.frame(in: .named("spendHotspot"))]
                )
            }
        }
    }
}
