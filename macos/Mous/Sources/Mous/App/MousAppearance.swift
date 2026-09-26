import AppKit
import MousCore
import SwiftUI

private struct MousAccentKey: EnvironmentKey {
    static let defaultValue = MousTheme.lime.mark
}

private struct MousCanvasKey: EnvironmentKey {
    static let defaultValue = MousTheme.lime.canvas
}

extension EnvironmentValues {
    var mousAccent: Color {
        get { self[MousAccentKey.self] }
        set { self[MousAccentKey.self] = newValue }
    }

    var mousCanvas: Color {
        get { self[MousCanvasKey.self] }
        set { self[MousCanvasKey.self] = newValue }
    }
}

extension MousTheme {
    var mark: Color {
        Color(red: markRGB.red, green: markRGB.green, blue: markRGB.blue)
    }

    var canvas: Color {
        Color(red: canvasRGB.red, green: canvasRGB.green, blue: canvasRGB.blue)
    }

    var nsCanvas: NSColor {
        NSColor(srgbRed: canvasRGB.red, green: canvasRGB.green, blue: canvasRGB.blue, alpha: 1)
    }

    var nsMark: NSColor {
        NSColor(srgbRed: markRGB.red, green: markRGB.green, blue: markRGB.blue, alpha: 1)
    }

    /// White cards use light text colors. The other themes stay dark.
    var isLight: Bool { self == .white }
}

struct MousThemedChrome: ViewModifier {
    var theme: MousTheme

    func body(content: Content) -> some View {
        content
            .environment(\.mousAccent, theme.mark.opacity(0.92))
            .environment(\.mousCanvas, theme.canvas)
    }
}

/// The saved value picks the mark, the card tint, and light vs dark text.
@MainActor
enum MousAppearance {
    static func apply(_ theme: MousTheme) {
        NSApp.appearance = NSAppearance(named: theme.isLight ? .aqua : .darkAqua)
        MousIcons.applyDockIcon(theme: theme)
        // Always post the canonical rawValue (parse first) so "dark" /
        // "logo-variant-2" land on the same MousTheme as Settings.
        NotificationCenter.default.post(
            name: .mousAppearanceDidChange,
            object: theme.rawValue
        )
    }

    static func apply(_ rawValue: String) {
        apply(MousTheme.parse(rawValue))
    }
}

extension Notification.Name {
    static let mousAppearanceDidChange = Notification.Name("mous.appearanceDidChange")
}
