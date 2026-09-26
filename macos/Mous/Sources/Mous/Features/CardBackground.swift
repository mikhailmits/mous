import SwiftUI

struct CardBackground: ViewModifier {
    static let cornerRadius: CGFloat = 16
    @Environment(\.mousCanvas) private var canvas

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                shape
                    .fill(canvas)
                    // Soft ambient shadow plus a tight contact shadow: shared by
                    // both cards so they read as one floating popup.
                    .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
    }
}

extension View {
    func mousCard() -> some View {
        modifier(CardBackground())
    }

    /// Tick: digit roll for amounts, interpolate for other copy. Reduce Motion fades.
    func mousTick(numeric: Bool, reduceMotion: Bool) -> some View {
        contentTransition(
            reduceMotion ? .opacity : (numeric ? .numericText() : .interpolate)
        )
    }
}
