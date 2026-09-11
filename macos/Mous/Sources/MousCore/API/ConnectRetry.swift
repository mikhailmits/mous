import Foundation

/// Backoff for reaching the local API. Caps at 5 s so a down server is not a spin loop.
public enum ConnectRetry: Sendable {
    public static let maxDelay: TimeInterval = 5
    /// Tight poll while the bundled helper is still coming up (~8 s).
    public static let bootPoll: TimeInterval = 0.05
    public static let bootAttempts = 160

    /// `attempt` is 1-based: 0.4 s, 0.8 s, 1.6 s, 3.2 s, then 5 s.
    public static func delay(attempt: Int) -> TimeInterval {
        let clamped = max(1, attempt)
        return min(maxDelay, 0.4 * pow(2.0, Double(clamped - 1)))
    }

    /// 50 ms for the first `bootAttempts`, then the usual exponential backoff.
    public static func bootDelay(attempt: Int) -> TimeInterval {
        if attempt <= bootAttempts { return bootPoll }
        return delay(attempt: attempt - bootAttempts)
    }

    public static func sleep(attempt: Int) async throws {
        try await sleep(seconds: delay(attempt: attempt))
    }

    public static func sleepForBoot(attempt: Int) async throws {
        try await sleep(seconds: bootDelay(attempt: attempt))
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let nanos = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}
