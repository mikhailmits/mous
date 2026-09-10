import AppKit
import MousCore
import SwiftUI

struct EntryCard: View {
    @Bindable var store: AppStore
    var commitTick: Int
    var rejectTick: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var body: some View {
        HStack(spacing: 10) {
            glyph
                .frame(width: 16, height: 16)
                .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18), value: store.presentation)
            ZStack(alignment: .leading) {
                AlwaysFocusedLineField(
                    text: $store.text,
                    placeholder: "-30 coffee with dave",
                    onSubmit: {
                        Task {
                            await store.submit()
                            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
                        }
                    }
                )
                .opacity(fieldOpacity)
                .accessibilityLabel("New transaction")
                .accessibilityHint("Plus for income, minus for expense, then amount, optional currency, optional description")

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
            playCommit()
            restoreFocusAfter(seconds: 0.36)
        }
    }

    private func restoreFocusAfter(seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
        }
    }

    // Settle: glyph changes are a plain crossfade inside a fixed 16pt slot.
    // No bounce, no scale, no reflow of the field.
    @ViewBuilder
    private var glyph: some View {
        switch store.presentation {
        case .empty, .composing:
            Color.clear
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.45))
                .transition(.opacity)
        case .committedInvalid:
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
            (0.0, 6), (0.07, -5), (0.14, 3), (0.21, 0),
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
