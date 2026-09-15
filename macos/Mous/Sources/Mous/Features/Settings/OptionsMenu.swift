import SwiftUI

struct OptionsMenuButton: View {
    @Binding var isOpen: Bool
    var unreadCount: Int = 0
    var onSettings: () -> Void
    var onNotifications: () -> Void
    var showCommandHints: Bool = false
    var reduceMotion: Bool
    @State private var hoveringButton = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                withAnimation(motion) { isOpen.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hoveringButton || isOpen ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(hoveringButton || isOpen ? 0.08 : 0))
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.primary.opacity(hoveringButton || isOpen ? 0.2 : 0.12),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .contentShape(Circle())
                    .overlay(alignment: .topTrailing) {
                        if unreadCount > 0 {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 7, height: 7)
                                .offset(x: 1, y: -1)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .onHover { hoveringButton = $0 }
            .help("Options")
            .accessibilityLabel(unreadCount > 0 ? "Options, \(unreadCount) unread" : "Options")
            .accessibilityHint("Command O opens or closes this menu. Command S opens Settings. Command N opens Notifications.")
            .accessibilityAddTraits(isOpen ? .isSelected : [])

            if isOpen {
                OptionsMenuList(
                    unreadCount: unreadCount,
                    showCommandHints: showCommandHints,
                    reduceMotion: reduceMotion,
                    onSettings: {
                        withAnimation(motion) { isOpen = false }
                        onSettings()
                    },
                    onNotifications: {
                        withAnimation(motion) { isOpen = false }
                        onNotifications()
                    }
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            CommandKeycap(letter: "o", visible: showCommandHints, reduceMotion: reduceMotion)
                .padding(.trailing, 34)
        }
        .animation(motion, value: isOpen)
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)
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
        .frame(width: 220, alignment: .leading)
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
        Button(action: action) {
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
                        .fill(Color.primary)
                        .frame(width: 7, height: 7)
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
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(unread ? "\(title), unread, Command \(shortcut)" : "\(title), Command \(shortcut)")
    }
}
