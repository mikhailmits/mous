import Foundation

/// Backoff for reaching the local API. Caps at 5 s so a down server is not a spin loop.
public enum ConnectRetry: Sendable {
    public static let maxDelay: TimeInterval = 5

    /// `attempt` is 1-based: 0.4 s, 0.8 s, 1.6 s, 3.2 s, then 5 s.
    public static func delay(attempt: Int) -> TimeInterval {
        let clamped = max(1, attempt)
        return min(maxDelay, 0.4 * pow(2.0, Double(clamped - 1)))
    }

    public static func sleep(attempt: Int) async throws {
        let nanos = UInt64(delay(attempt: attempt) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}
