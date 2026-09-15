import AppKit
import MousCore
import SwiftUI

private struct MousAccentKey: EnvironmentKey {
    static let defaultValue = Color(red: 0.4824, green: 1, blue: 0).opacity(0.55)
}

extension EnvironmentValues {
    var mousAccent: Color {
        get { self[MousAccentKey.self] }
        set { self[MousAccentKey.self] = newValue }
    }
}

/// Mark color sampled from `logo-variant-2`; light theme darkens it the same
/// way the themed icons darken their marks.
enum MousPalette {
    static let fallbackMark = NSColor(srgbRed: 0.4824, green: 1, blue: 0, alpha: 1)

    static func markColor(isDark: Bool) -> NSColor {
        let sampled = MousIcons.sampledMarkColor() ?? fallbackMark
        if isDark { return sampled }
        return sampled.blended(withFraction: 0.38, of: .black) ?? sampled
    }

    static func accent(isDark: Bool) -> Color {
        Color(nsColor: markColor(isDark: isDark)).opacity(isDark ? 0.55 : 0.78)
    }
}

struct MousThemedChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.mousAccent, MousPalette.accent(isDark: colorScheme == .dark))
    }
}

/// Maps the saved `theme` config onto AppKit, SwiftUI, dock, and accent.
@MainActor
enum MousAppearance {
    private static var appearanceObservation: NSKeyValueObservation?

    static func nsAppearance(for theme: MousTheme) -> NSAppearance? {
        switch theme {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static func colorScheme(for theme: MousTheme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func colorScheme(from rawValue: String) -> ColorScheme? {
        colorScheme(for: MousTheme(rawValue: rawValue) ?? .system)
    }

    static func isDark(theme: MousTheme, appearance: NSAppearance) -> Bool {
        switch theme {
        case .dark: return true
        case .light: return false
        case .system:
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    static func apply(_ theme: MousTheme) {
        NSApp.appearance = nsAppearance(for: theme)
        MousIcons.applyDockIcon(isDark: isDark(theme: theme, appearance: NSApp.effectiveAppearance))
        NotificationCenter.default.post(name: .mousAppearanceDidChange, object: theme.rawValue)
        observeSystemAppearance()
    }

    static func apply(_ rawValue: String) {
        apply(MousTheme(rawValue: rawValue) ?? .system)
    }

    static func observeSystemAppearance() {
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in
                let theme = MousTheme(rawValue: MousConfigFile.load().theme) ?? .system
                MousIcons.applyDockIcon(isDark: isDark(theme: theme, appearance: NSApp.effectiveAppearance))
                NotificationCenter.default.post(name: .mousAppearanceDidChange, object: theme.rawValue)
            }
        }
    }
}

extension Notification.Name {
    static let mousAppearanceDidChange = Notification.Name("mous.appearanceDidChange")
}
