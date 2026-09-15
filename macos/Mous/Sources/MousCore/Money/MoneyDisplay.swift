import Foundation

/// In-memory quotes for later live FX. Lookups are a dictionary hit;
/// missing pairs stay identity so totals never block on a rate fetch.
public struct FXBook: Equatable, Sendable {
    public static let identity = FXBook()

    private var rates: [String: Double]

    public init() {
        rates = [:]
    }

    /// `rate` is quote units per one base unit (`EUR`→`USD` 1.1 means $1.10 per €1).
    public mutating func set(base: String, quote: String, rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        let src = Self.normalized(base)
        let dst = Self.normalized(quote)
        guard src != dst else { return }
        rates[Self.key(src, dst)] = rate
        rates[Self.key(dst, src)] = 1 / rate
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double {
        guard amount.isFinite else { return amount }
        let src = Self.normalized(from)
        let dst = Self.normalized(to)
        if src == dst { return amount }
        if let rate = rates[Self.key(src, dst)] {
            let converted = amount * rate
            return converted.isFinite ? converted : amount
        }
        if src != "EUR", dst != "EUR",
           let toEUR = rates[Self.key(src, "EUR")],
           let fromEUR = rates[Self.key("EUR", dst)]
        {
            let converted = amount * toEUR * fromEUR
            return converted.isFinite ? converted : amount
        }
        return amount
    }

    public var isEmpty: Bool { rates.isEmpty }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func key(_ a: String, _ b: String) -> String {
        "\(a)|\(b)"
    }
}

/// Display-currency conversion. Plug quotes into `book` later; until then
/// every amount is returned unchanged (fast path).
public enum MoneyDisplay {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = FXBook.identity

    public static var book: FXBook {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }

    public static func convert(
        _ amount: Double,
        from: String,
        to: String,
        using book: FXBook? = nil
    ) -> Double {
        (book ?? Self.book).convert(amount, from: from, to: to)
    }
}
