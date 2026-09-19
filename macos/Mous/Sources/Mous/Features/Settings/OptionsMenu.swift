import AppKit
import SwiftUI

struct OptionsMenuButton: View {
    @Binding var isOpen: Bool
    var unreadCount: Int = 0
    var onSettings: () -> Void
    var onNotifications: () -> Void
    var showCommandHints: Bool = false
    var reduceMotion: Bool
    var dimmed: Bool = false
    @State private var hoveringButton = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            trigger
                .opacity(dimmed ? 0.4 : 1)

            if isOpen {
                OptionsMenuList(
                    unreadCount: unreadCount,
                    showCommandHints: showCommandHints,
                    reduceMotion: reduceMotion,
                    onSettings: {
                        withAnimation(closeMotion) { isOpen = false }
                        onSettings()
                    },
                    onNotifications: {
                        withAnimation(closeMotion) { isOpen = false }
                        onNotifications()
                    }
                )
                .padding(.top, 44)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(
                                with: .scale(scale: 0.96, anchor: .topTrailing)
                            ),
                            removal: .opacity
                        )
                )
            }
        }
        // Intrinsic size so the topTrailing overlay stays on the ⋯; the menu
        // hangs below instead of filling the dashboard over leftover.
        .fixedSize()
        .overlay(alignment: .topTrailing) {
            CommandKeycap(letter: "o", visible: showCommandHints, reduceMotion: reduceMotion)
                .padding(.trailing, 34)
        }
        .animation(isOpen ? openMotion : closeMotion, value: isOpen)
    }

    private var trigger: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(hoveringButton || isOpen ? .primary : .secondary)
            .frame(width: 26, height: 26)
            .background {
                Circle()
                    .fill(Color.primary.opacity(hoveringButton || isOpen ? 0.10 : 0.06))
                    .overlay {
                        Circle()
                            .strokeBorder(
                                Color.primary.opacity(hoveringButton || isOpen ? 0.2 : 0.14),
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(Circle())
            .overlay {
                NonActivatingClick(
                    circular: true,
                    action: {
                        isOpen.toggle()
                    },
                    onHover: { hoveringButton = $0 }
                )
            }
            .help("Options")
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            .accessibilityLabel(unreadCount > 0 ? "Options, \(unreadCount) unread" : "Options")
            .accessibilityHint("Command O opens or closes this menu. Command S opens Settings. Command N opens Notifications.")
            .accessibilityAction(.default) {
                isOpen.toggle()
                NotificationCenter.default.post(name: .mousRestoreInputFocus, object: nil)
            }
    }

    private var openMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)
    }

    private var closeMotion: Animation {
        .easeOut(duration: 0.12)
    }
}

/// Full-card hit target that dismisses the ⋯ menu without taking key focus.
struct OptionsMenuDismissHit: View {
    var action: () -> Void

    var body: some View {
        NonActivatingClick(action: action)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OptionsMenuList: View {
    var unreadCount: Int
    var showCommandHints: Bool
    var reduceMotion: Bool
    var onSettings: () -> Void
    var onNotifications: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OptionsMenuRow(
                icon: "gearshape",
                title: "Settings",
                shortcut: "s",
                showShortcut: showCommandHints,
                reduceMotion: reduceMotion,
                action: onSettings
            )
            OptionsMenuRow(
                icon: "bell",
                title: "Notifications",
                shortcut: "n",
                unread: unreadCount > 0,
                showShortcut: showCommandHints,
                reduceMotion: reduceMotion,
                action: onNotifications
            )
        }
        .padding(6)
        .frame(width: 192, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.16),
                                Color.primary.opacity(0.06),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Options")
    }
}

private struct OptionsMenuRow: View {
    var icon: String
    var title: String
    var shortcut: String
    var unread: Bool = false
    var showShortcut: Bool
    var reduceMotion: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            if unread {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
        }
        .overlay(alignment: .trailing) {
            CommandKeycap(letter: shortcut, visible: showShortcut, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            NonActivatingClick(
                action: action,
                onHover: { hovering = $0 }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(unread ? "\(title), unread, Command \(shortcut)" : "\(title), Command \(shortcut)")
        .accessibilityAction(.default, action)
    }
}

/// AppKit hit target that never becomes first responder, so the entry field keeps the caret.
private struct NonActivatingClick: NSViewRepresentable {
    var circular = false
    var action: () -> Void
    var onHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NonActivatingClickView {
        let view = NonActivatingClickView()
        view.circular = circular
        view.action = action
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: NonActivatingClickView, context: Context) {
        view.circular = circular
        view.action = action
        view.onHover = onHover
    }
}

private final class NonActivatingClickView: NSView {
    var circular = false
    var action: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if circular {
            let dx = point.x - bounds.midX
            let dy = point.y - bounds.midY
            let radius = min(bounds.width, bounds.height) / 2
            guard (dx * dx) + (dy * dy) <= radius * radius else { return nil }
        }
        return self
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

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        // Swallow without calling super so AppKit does not retarget first responder.
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if hitTest(loc) != nil {
            action()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool { false }
}
