import AppKit
import SwiftUI

extension Notification.Name {
    static let mousRestoreInputFocus = Notification.Name("mous.restoreInputFocus")
}

/// Single-line field that stays first responder through Return.
/// SwiftUI `TextField` + `onSubmit` ends editing on Enter on macOS.
struct AlwaysFocusedLineField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onTab: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onTab: onTab)
    }

    func makeNSView(context: Context) -> StickyTextField {
        let field = StickyTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        let font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        field.font = font
        field.textColor = .labelColor
        applyPlaceholder(placeholder, to: field, font: font)
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.refusesFirstResponder = false
        field.setAccessibilityLabel("New transaction")
        field.setAccessibilityIdentifier("New transaction")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field
        context.coordinator.startObserving()
        return field
    }

    func updateNSView(_ field: StickyTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onTab = onTab
        if field.stringValue != text {
            field.stringValue = text
            // Programmatic rewrite (FX convert, demo type): keep the caret at
            // the end. Setting stringValue without an editor selects all.
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        applyPlaceholder(placeholder, to: field, font: field.font)
        context.coordinator.claimFocusIfNeeded()
    }

    private func applyPlaceholder(_ placeholder: String, to field: NSTextField, font: NSFont?) {
        let font = font ?? NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        // Quieter placeholder than the default secondary color, so typed text
        // clearly outranks the hint.
        if field.placeholderAttributedString?.string != placeholder {
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: font,
                ]
            )
        }
    }

    static func dismantleNSView(_ field: StickyTextField, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onTab: () -> Void
        weak var field: StickyTextField?
        private var observers: [NSObjectProtocol] = []

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onTab: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onTab = onTab
        }

        func startObserving() {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                    guard let field = self?.field, note.object as? NSWindow === field.window else { return }
                    self?.claimFocusIfNeeded()
                },
                center.addObserver(forName: .mousRestoreInputFocus, object: nil, queue: .main) { [weak self] _ in
                    self?.claimFocusIfNeeded()
                },
            ]
        }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        func claimFocusIfNeeded() {
            guard let field, let window = field.window, window.isKeyWindow else { return }
            if field.currentEditor() != nil { return }
            window.makeFirstResponder(field)
        }

        func controlTextDidChange(_ obj: Notification) {
            text.wrappedValue = (obj.object as? NSTextField)?.stringValue ?? ""
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
                || commandSelector == #selector(NSResponder.insertLineBreak(_:))
            {
                onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:))
                || commandSelector == #selector(NSResponder.insertBacktab(_:))
                || commandSelector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:))
            {
                onTab()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.claimFocusIfNeeded()
            }
        }
    }
}

final class StickyTextField: NSTextField {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isKeyWindow else { return }
            window.makeFirstResponder(self)
        }
    }
}
