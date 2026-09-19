import Foundation

/// In-memory quotes for display FX. Lookups are a dictionary hit.
/// Missing pairs return nil so totals never pretend 1:1 across currencies.
public struct FXBook: Equatable, Sendable {
    public static let identity = FXBook()

    /// Stand-in EUR-pivoted quotes until a live feed exists.
    /// `EUR→USD` 1.1, `EUR→UAH` 40; cross pairs go through EUR.
    public static let stub: FXBook = {
        var book = FXBook()
        book.set(base: "EUR", quote: "USD", rate: 1.1)
        book.set(base: "EUR", quote: "UAH", rate: 40)
        return book
    }()

    /// Pivot used when a ledger bucket has no currency of its own.
    public static let pivotCode = "EUR"

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

    /// Quote units of `to` per one `from`. Same currency is 1. Missing pair is nil.
    public func quote(from: String, to: String) -> Double? {
        let src = Self.normalized(from)
        let dst = Self.normalized(to)
        if src == dst { return 1 }
        if let rate = rates[Self.key(src, dst)], rate.isFinite, rate > 0 {
            return rate
        }
        if src != "EUR", dst != "EUR",
           let toEUR = rates[Self.key(src, "EUR")],
           let fromEUR = rates[Self.key("EUR", dst)]
        {
            let crossed = toEUR * fromEUR
            return crossed.isFinite && crossed > 0 ? crossed : nil
        }
        return nil
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard amount.isFinite, let rate = quote(from: from, to: to) else { return nil }
        let converted = amount * rate
        return converted.isFinite ? converted : nil
    }

    public var isEmpty: Bool { rates.isEmpty }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func key(_ a: String, _ b: String) -> String {
        "\(a)|\(b)"
    }
}

/// Display-currency conversion. The app installs `FXBook.stub` at launch;
/// tests can swap `book` for `.identity`.
public enum MoneyDisplay {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = FXBook.identity

    public static func useStubQuotes() {
        book = .stub
    }

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
    ) -> Double? {
        (book ?? Self.book).convert(amount, from: from, to: to)
    }
}
