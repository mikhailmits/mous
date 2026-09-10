import Observation
import MousCore
import SwiftUI

@Observable
@MainActor
final class CommandHintState {
    var visible = false
}

struct DashboardCard: View {
    var snapshot: DashboardSnapshot
    /// True once at least one fetch has succeeded. Until then, amounts show €0.00.
    var hasLoaded: Bool
    var isRefreshing: Bool
    var statusMessage: String?
    var onSpendHover: (Bool) -> Void = { _ in }
    var onSavedHover: (Bool) -> Void = { _ in }
    var showCommandHints: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spendHotspot: CGRect = .zero

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
            .overlay(alignment: .topLeading) {
                CommandKeycap(letter: "m", visible: showCommandHints, reduceMotion: reduceMotion)
                    .offset(x: -44, y: -2)
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
                    .overlay(alignment: .leading) {
                        CommandKeycap(letter: "x", visible: showCommandHints, reduceMotion: reduceMotion)
                            .offset(x: -44, y: -2)
                    }
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
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .mousCard()
        .redacted(reason: isRefreshing && !hasLoaded ? .placeholder : [])
        .animation(Self.tickAnimation(reduceMotion: reduceMotion), value: tickToken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Command M shows History. Command X shows Most expensive.")
    }

    /// Any visible dashboard change — numbers, load state, or status copy.
    private var tickToken: TickToken {
        TickToken(
            spentToday: displayedSpentToday,
            spentMonth: displayedSpentMonth,
            left: hasLoaded ? snapshot.left : 0,
            saved: hasLoaded ? (snapshot.savedRatio ?? 0) : 0,
            hasLoaded: hasLoaded,
            status: statusMessage ?? ""
        )
    }

    private struct TickToken: Equatable {
        var spentToday: Double
        var spentMonth: Double
        var left: Double
        var saved: Double
        var hasLoaded: Bool
        var status: String
    }

    private static func tickAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3)
    }

    @ViewBuilder
    private var heroValue: some View {
        Text(displayedSpentToday, format: Self.eur)
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
        // Green at 50% opacity is locked; bold rounded weight keeps it readable
        // against the material at that opacity.
        Text("\(hasLoaded ? snapshot.left : 0, format: Self.eur) left")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color.green.opacity(0.5))
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
        Text(displayedSpentMonth, format: Self.eur)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .mousTick(numeric: true, reduceMotion: reduceMotion)
    }

    private var savedLabel: some View {
        let ratio = hasLoaded ? (snapshot.savedRatio ?? 0) : 0
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Saved \(ratio, format: Self.percent).")
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

    private var accessibilityText: String {
        if !hasLoaded {
            var text = "Spent today 0, 0 left, spent this month 0, saved 0 percent this month"
            if let statusMessage, !statusMessage.isEmpty {
                text += ", \(statusMessage)"
            }
            return text
        }
        let today = displayedSpentToday.formatted(Self.eur)
        let left = snapshot.left.formatted(Self.eur)
        let month = displayedSpentMonth.formatted(Self.eur)
        let saved = (snapshot.savedRatio ?? 0).formatted(Self.percent)
        var text = "Spent today \(today), \(left) left, spent this month \(month), saved \(saved) this month"
        if let statusMessage, !statusMessage.isEmpty {
            text += ", \(statusMessage)"
        }
        return text
    }

    private static let eur = FloatingPointFormatStyle<Double>.Currency(code: "EUR")
        .precision(.fractionLength(2))
    private static let percent = FloatingPointFormatStyle<Double>.Percent()
        .precision(.fractionLength(0))
}

private struct CommandKeycap: View {
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
