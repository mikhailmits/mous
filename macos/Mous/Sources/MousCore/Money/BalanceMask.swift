import Foundation

/// Privacy stand-in for on-screen money. Scramble glyphs are `?`, `#`, `*`, `!`;
/// each scramble call is a new sequence so the same amount never reprints as a
/// fixed stand-in. Veil is repeated `•`.
public enum BalanceMask {
    public static let glyphs: [Character] = ["?", "#", "*", "!"]
    public static let veilGlyph: Character = "•"

    public static func make(length: Int = 6) -> String {
        let count = max(length, 1)
        return String((0..<count).map { _ in glyphs.randomElement() ?? "?" })
    }

    public static func veil(length: Int = 4) -> String {
        String(repeating: String(veilGlyph), count: max(length, 1))
    }

    public static func make(style: HideBalanceStyle, length: Int = 6) -> String {
        switch style {
        case .scramble: return make(length: length)
        case .veil: return veil(length: length)
        }
    }

    public static func isMasked(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { glyphs.contains($0) }
    }

    public static func isVeil(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 == veilGlyph }
    }
}
