import AppKit
import SwiftUI

/// Logo cycle while the local API is not reachable. No card chrome — just
/// the transparent marks, so it sits on whatever is behind the popup.
struct LaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var images = MousIcons.variantImages()
    @State private var index = 0
    @State private var flipDegrees: Double = 0

    /// Same footprint as dashboard + gap + entry, so the window does not jump.
    static let contentHeight: CGFloat = 136 + 8 + 58

    var body: some View {
        ZStack {
            if images.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(nsImage: images[index])
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .rotation3DEffect(
                        .degrees(flipDegrees),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.65
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.contentHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starting mous")
        .task { await runLoop() }
    }

    @MainActor
    private func runLoop() async {
        guard images.count > 1 else { return }
        do {
            while !Task.isCancelled {
                if reduceMotion {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    index = (index + 1) % images.count
                    continue
                }
                try await Task.sleep(nanoseconds: 280_000_000)
                withAnimation(.easeIn(duration: 0.14)) { flipDegrees = 90 }
                try await Task.sleep(nanoseconds: 140_000_000)
                index = (index + 1) % images.count
                flipDegrees = -90
                withAnimation(.easeOut(duration: 0.18)) { flipDegrees = 0 }
                try await Task.sleep(nanoseconds: 180_000_000)
            }
        } catch {
            // Cancelled when the splash leaves the tree.
        }
    }
}
