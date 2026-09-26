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
    // Dedupes SwiftUI onChange double-fires so the hint does not skip.
    @State private var lastHandledCommitTick = 0
    // After assist accept, ignore a follow-up Return/key-repeat that would post.
    @State private var submitSuppressed = false
    @State private var submitSuppressGeneration = 0
    // Synchronous lock so two Tasks cannot start before isSubmitting flips.
    @State private var localSubmitLock = false

    private static let placeholderHints = [
        "-450 uah groceries",
        "+1200 eur salary",
        "45 + 34",
        "4 eur to uah",
    ]

    private var placeholder: String {
        Self.placeholderHints[placeholderIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                glyph
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                    .animation(MousMotion.quick(reduceMotion: reduceMotion), value: leadingGlyph)
                ZStack(alignment: .leading) {
                    AlwaysFocusedLineField(
                        text: $store.text,
                        placeholder: placeholder,
                        onSubmit: handleReturn,
                        onTab: handleTab
                    )
                    .opacity(fieldOpacity)
                    .accessibilityLabel("New transaction")
                    .accessibilityHint("Plus for income, minus for expense, then amount, optional currency, optional description. A calculator row appears for math and currency conversion. Return uses it.")

                    if isDeparting {
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
            .padding(.top, 16)
            .padding(.bottom, store.assistSuggestion == nil ? 16 : 6)
            if let suggestion = store.assistSuggestion {
                calculatorRow(suggestion)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(MousMotion.spring(reduceMotion: reduceMotion), value: store.assistSuggestion)
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
        .onChange(of: commitTick) { _, new in
            guard new != lastHandledCommitTick else { return }
            lastHandledCommitTick = new
            placeholderIndex = (placeholderIndex + 1) % Self.placeholderHints.count
            playCommit()
            restoreFocusAfter(seconds: 0.36)
        }
    }

    /// Return: calculator inserts only; a signed spend line posts.
    private func handleReturn() {
        if acceptAssistFromUI() { return }
        guard !submitSuppressed else {
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
            return
        }
        guard !localSubmitLock, !store.isSubmitting else {
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
            return
        }
        localSubmitLock = true
        Task {
            defer { localSubmitLock = false }
            await store.submit()
            NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
        }
    }

    /// Tab: FX/math insert only — never posts.
    private func handleTab() {
        if acceptAssistFromUI() { return }
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
    }

    @discardableResult
    private func acceptAssistFromUI() -> Bool {
        guard store.acceptAssist() else { return false }
        // Key-repeat / second command selector after insert must not post
        // a signed FX result (e.g. `-11usd`).
        suppressSubmitBriefly()
        NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
        return true
    }

    private func suppressSubmitBriefly() {
        submitSuppressed = true
        submitSuppressGeneration += 1
        let generation = submitSuppressGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard generation == submitSuppressGeneration else { return }
            submitSuppressed = false
        }
    }

    private func calculatorRow(_ suggestion: InputAssist.Suggestion) -> some View {
        // Tap, not Button: a SwiftUI Button can become the window default
        // action and fire on Return in addition to the field's onSubmit,
        // which would accept then post a signed convert.
        HStack(spacing: 8) {
            Text(suggestion.label)
                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(mousAccent)
            Spacer(minLength: 8)
            Text("Return")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            _ = acceptAssistFromUI()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("Calculator result \(suggestion.label)")
        .accessibilityLabel(suggestion.label)
        .accessibilityValue(suggestion.label)
        .accessibilityHint("Inserts this result into the line.")
        .accessibilityAction(.default) {
            _ = acceptAssistFromUI()
        }
    }

    private func restoreFocusAfter(seconds: Double) {
        let generation = motionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard generation == motionGeneration else { return }
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
            if store.assistSuggestion != nil { return .convert }
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
        // Drop any in-flight commit overlay so opacity is not left at 0.01.
        isDeparting = false
        departingLine = ""
        shakeOffset = 0

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.08)) { fieldOpacity = 0.55 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard generation == motionGeneration else { return }
                withAnimation(.easeOut(duration: 0.18)) { fieldOpacity = 1 }
            }
            return
        }
        fieldOpacity = 1
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
        // Drop any in-flight shake so offset does not stick mid-swing.
        shakeOffset = 0

        departingLine = store.outgoingLine
        isDeparting = true
        // Hide the (already empty) real field; the overlay owns the visual.
        // Floor at 0.01 so AppKit keeps first responder.
        fieldOpacity = 0.01

        let tick = MousMotion.tick(reduceMotion: reduceMotion)
        DispatchQueue.main.async {
            guard generation == motionGeneration else { return }
            withAnimation(tick) {
                departingLine = ""
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.16 : 0.22)) {
            guard generation == motionGeneration else { return }
            withAnimation(MousMotion.fade(reduceMotion: reduceMotion)) { fieldOpacity = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.24 : 0.48)) {
            guard generation == motionGeneration else { return }
            isDeparting = false
        }
    }
}
