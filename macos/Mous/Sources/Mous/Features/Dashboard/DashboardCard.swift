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
    var onToggleHide: () -> Void = {}
    var onPeek: (Bool) -> Void = { _ in }
    var onSpendHover: (Bool) -> Void = { _ in }
    var onSavedHover: (Bool) -> Void = { _ in }
    var showCommandHints: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mousAccent) private var mousAccent
    @State private var spendHotspot: CGRect = .zero
    @State private var eyeAnchor: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Spent today.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .mousTick(numeric: false, reduceMotion: reduceMotion)
                    // Layout only — the interactive eye is overlaid above the
                    // History hover catcher so peek/toggle clicks are not stolen.
                    Color.clear
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: EyeAnchorKey.self,
                                    value: proxy.frame(in: .named("spendHotspot"))
                                )
                            }
                        }
                }
                .spendHotspot()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    heroValue
                        .spendHotspot()
                    leftLabel
                        .layoutPriority(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
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
        .onPreferenceChange(EyeAnchorKey.self) { eyeAnchor = $0 }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: max(spendHotspot.width, 0), height: max(spendHotspot.height, 0))
                .offset(x: spendHotspot.minX, y: spendHotspot.minY)
                .contentShape(Rectangle())
                .onHover { onSpendHover($0) }
        }
        // Real control on top of the History hover catcher (placeholder eye below).
        .overlay(alignment: .topLeading) {
            BalanceEye(hidden: hideBalance, onToggle: onToggleHide, onPeek: onPeek)
                .offset(x: eyeAnchor.minX, y: eyeAnchor.minY)
                .opacity(eyeAnchor.width > 0 ? 1 : 0)
                .allowsHitTesting(eyeAnchor.width > 0)
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
        .animation(MousMotion.quick(reduceMotion: reduceMotion), value: hideBalance)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("Spent today")
        .accessibilityValue(hideBalance ? Self.heroDots : displayedSpentToday.formatted(money))
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
        MousMotion.tick(reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var heroValue: some View {
        Text(hideBalance ? Self.heroDots : displayedSpentToday.formatted(money))
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
        Text(hideBalance ? "\(Self.sideDots) left" : "\(hasLoaded ? snapshot.left : 0, format: money) left")
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
        Text(hideBalance ? Self.sideDots : displayedSpentMonth.formatted(money))
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
        let today = hideBalance ? Self.heroDots : displayedSpentToday.formatted(money)
        let left = hideBalance ? Self.sideDots : snapshot.left.formatted(money)
        let month = hideBalance ? Self.sideDots : displayedSpentMonth.formatted(money)
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

    private static let heroDots = BalanceMask.veil(length: 6)
    private static let sideDots = BalanceMask.veil(length: 4)

    private var money: FloatingPointFormatStyle<Double>.Currency {
        FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
            .precision(.fractionLength(2))
    }

    private static let percent = FloatingPointFormatStyle<Double>.Percent()
        .precision(.fractionLength(0))
}

/// Click toggles hide. A longer press, while hidden, peeks until release.
private struct BalanceEye: View {
    var hidden: Bool
    var onToggle: () -> Void
    var onPeek: (Bool) -> Void
    @Environment(\.mousAccent) private var mousAccent
    @State private var hovering = false

    var body: some View {
        Image(systemName: hidden ? "eye.slash" : "eye")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hovering ? AnyShapeStyle(mousAccent) : AnyShapeStyle(.secondary))
            .frame(width: 22, height: 22)
            .background {
                Circle().fill(Color.white.opacity(hovering ? 0.10 : 0.05))
            }
            .overlay {
                HoldEye(hidden: hidden, onToggle: onToggle, onPeek: onPeek, onHover: { hovering = $0 })
            }
            .help(hidden ? "Hold to peek. Click to show amounts." : "Hide amounts")
            .accessibilityLabel("Hide balance")
            .accessibilityIdentifier("Hide balance")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(hidden ? "On" : "Off")
            .accessibilityHint("Hides amounts. Hold to peek while they are hidden.")
            .accessibilityAction(.default) { onToggle() }
    }
}

private struct HoldEye: NSViewRepresentable {
    var hidden: Bool
    var onToggle: () -> Void
    var onPeek: (Bool) -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoldEyeView {
        let view = HoldEyeView()
        view.onToggle = onToggle
        view.onPeek = onPeek
        view.onHover = onHover
        view.amountsHidden = hidden
        return view
    }

    func updateNSView(_ view: HoldEyeView, context: Context) {
        view.onToggle = onToggle
        view.onPeek = onPeek
        view.onHover = onHover
        view.amountsHidden = hidden
    }
}

private final class HoldEyeView: NSView {
    var amountsHidden = false
    var onToggle: () -> Void = {}
    var onPeek: (Bool) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }
    private var tracking: NSTrackingArea?
    private var downAt = Date()
    private var peeking = false
    private var pressActive = false
    private var upMonitor: Any?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        stopUpMonitor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        downAt = Date()
        pressActive = true
        peeking = amountsHidden
        if peeking { onPeek(true) }
        // Local monitor so releasing outside the eye still ends peek
        // without a tracking loop that would block SwiftUI from revealing.
        if upMonitor == nil {
            upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] up in
                self?.finishPress(with: up)
                return up
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        finishPress(with: event)
    }

    private func finishPress(with event: NSEvent) {
        guard pressActive else { return }
        pressActive = false
        // Removing a local monitor inside its own handler can crash.
        stopUpMonitor()
        endPeek()
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        if Date().timeIntervalSince(downAt) < 0.35 {
            onToggle()
        }
    }

    private func stopUpMonitor() {
        guard let monitor = upMonitor else { return }
        upMonitor = nil
        DispatchQueue.main.async {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func endPeek() {
        guard peeking else { return }
        peeking = false
        onPeek(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool { false }
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
            MousMotion.quick(reduceMotion: reduceMotion),
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

private struct EyeAnchorKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 { value = next }
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
