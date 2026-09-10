import SwiftUI

struct CardBackground: ViewModifier {
    static let cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                shape
                    .fill(.regularMaterial)
                    .overlay {
                        // Single adaptive hairline, slightly brighter at the top
                        // edge so the cards catch light the way native panels do.
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
