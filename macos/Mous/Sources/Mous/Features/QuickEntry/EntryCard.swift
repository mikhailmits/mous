import AppKit
import MousCore
import SwiftUI

struct EntryCard: View {
    @Bindable var store: AppStore
    var commitTick: Int
    var rejectTick: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mousAccent) private var mousAccent

    // Real field visibility. Floored at 0.01 during commit so AppKit never
    // resigns first responder for a fully transparent view.
    @State private var fieldOpacity: Double = 1
    // Reject: left-right shake of the input card.
    @State private var shakeOffset: CGFloat = 0
    // Commit: the just-posted line rolls its digits away (numericText).
    @State private var departingLine = ""
    @State private var isDeparting = false
    // Invalidates stale asyncAfter callbacks if motions overlap.
    @State private var motionGeneration = 0
    // First open keeps the coffee hint; each successful save rotates the next.
    @State private var placeholderIndex = 0

    private static let placeholderHints = [
        "-30 coffee with dave",
        "- 10 hii",
        "+10hii",
        "10 eur to usd",
    ]

    private var placeholder: String {
        Self.placeholderHints[placeholderIndex]
    }

    var body: some View {
        HStack(spacing: 10) {
            glyph
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
                .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18), value: leadingGlyph)
            ZStack(alignment: .leading) {
                AlwaysFocusedLineField(
                    text: $store.text,
                    placeholder: placeholder,
                    onSubmit: {
                        // Convert on the key event, same as Tab, so the field
                        // editor stays up and the caret stays after the amount.
                        if store.applyFxCalc() {
                            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
                            return
                        }
                        Task {
                            await store.submit()
                            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
                        }
                    },
                    onTab: {
                        _ = store.applyFxCalc()
                        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
                    }
                )
                .opacity(fieldOpacity)
                .accessibilityLabel("New transaction")
                .accessibilityHint("Plus for income, minus for expense, then amount, optional currency, optional description. Amount currency to currency, then Tab or Return, converts.")

                if isDeparting {
                    // The sent line rolls its digits away, same Tick as the dashboard.
                    Text(departingLine)
                        .font(.system(size: 16).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .mousTick(numeric: true, reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .mousCard()
        .offset(x: shakeOffset)
        .onChange(of: store.presentation) { _, new in
            if new == .committedInvalid {
                AccessibilityNotification.Announcement("Couldn't parse that line").post()
            }
        }
        .onChange(of: rejectTick) { _, _ in
            playReject()
            restoreFocusAfter(seconds: 0.3)
        }
        .onChange(of: commitTick) { _, _ in
            placeholderIndex = (placeholderIndex + 1) % Self.placeholderHints.count
            playCommit()
            restoreFocusAfter(seconds: 0.36)
        }
    }

    private func restoreFocusAfter(seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
        }
    }

    private enum LeadingGlyph: Equatable {
        case none
        case check
        case convert
        case invalid
    }

    // Convert glyph wins over the spend check. Invalid stays the orange bang.
    private var leadingGlyph: LeadingGlyph {
        switch store.presentation {
        case .committedInvalid:
            return .invalid
        case .empty:
            return .none
        case .composing, .valid:
            if store.isFxCalcReady { return .convert }
            return store.presentation == .valid ? .check : .none
        }
    }

    // Settle: glyph changes are a plain crossfade inside a fixed 16pt slot.
    // No bounce, no scale, no reflow of the field.
    @ViewBuilder
    private var glyph: some View {
        switch leadingGlyph {
        case .none:
            Color.clear
                .transition(.opacity)
        case .check:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mousAccent.opacity(0.82))
                .transition(.opacity)
        case .convert:
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mousAccent.opacity(0.82))
                .transition(.opacity)
        case .invalid:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
                .transition(.opacity)
        }
    }

    /// Reject: a short damped left-right shake. The text stays for editing.
    private func playReject() {
        motionGeneration += 1
        let generation = motionGeneration
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.08)) { fieldOpacity = 0.55 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard generation == motionGeneration else { return }
                withAnimation(.easeOut(duration: 0.18)) { fieldOpacity = 1 }
            }
            return
        }
        let swings: [(delay: Double, offset: CGFloat)] = [
            (0.0, 4), (0.07, -3), (0.14, 2), (0.21, 0),
        ]
        for swing in swings {
            DispatchQueue.main.asyncAfter(deadline: .now() + swing.delay) {
                guard generation == motionGeneration else { return }
                withAnimation(.easeInOut(duration: 0.07)) {
                    shakeOffset = swing.offset
                }
            }
        }
    }

    /// Commit: the posted line rolls its digits away (numericText → empty),
    /// then the placeholder is back. Same Tick as the dashboard numbers.
    /// FX convert only rewrites `store.text` — it does not call this.
    private func playCommit() {
        motionGeneration += 1
        let generation = motionGeneration

        departingLine = store.outgoingLine
        isDeparting = true
        // Hide the (already empty) real field; the overlay owns the visual.
        // Floor at 0.01 so AppKit keeps first responder.
        fieldOpacity = 0.01

        let tick = reduceMotion ? Animation.easeOut(duration: 0.15) : .snappy(duration: 0.3)
        DispatchQueue.main.async {
            guard generation == motionGeneration else { return }
            withAnimation(tick) {
                departingLine = ""
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard generation == motionGeneration else { return }
            withAnimation(.easeOut(duration: 0.15)) { fieldOpacity = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.32)) {
            guard generation == motionGeneration else { return }
            isDeparting = false
        }
    }
}
