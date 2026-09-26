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

    /// Units of each code per one EUR. Cross rates are one division, not a stored inverse.
    private var perPivot: [String: Double]

    public init() {
        perPivot = [:]
    }

    /// `rate` is quote units per one base unit (`EUR`→`USD` 1.1 means $1.10 per €1).
    public mutating func set(base: String, quote: String, rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        let src = Self.normalized(base)
        let dst = Self.normalized(quote)
        guard src != dst else { return }
        if src == Self.pivotCode {
            perPivot[dst] = rate
            return
        }
        if dst == Self.pivotCode {
            let inverse = 1 / rate
            if inverse.isFinite, inverse > 0 { perPivot[src] = inverse }
            return
        }
        if let srcPer = perPivot[src] {
            let next = srcPer * rate
            if next.isFinite, next > 0 { perPivot[dst] = next }
            return
        }
        if let dstPer = perPivot[dst] {
            let next = dstPer / rate
            if next.isFinite, next > 0 { perPivot[src] = next }
        }
    }

    /// Quote units of `to` per one `from`. Same currency is 1. Missing pair is nil.
    public func quote(from: String, to: String) -> Double? {
        let src = Self.normalized(from)
        let dst = Self.normalized(to)
        guard !src.isEmpty, !dst.isEmpty else { return nil }
        if src == dst { return 1 }
        let srcPer = src == Self.pivotCode ? 1.0 : perPivot[src]
        let dstPer = dst == Self.pivotCode ? 1.0 : perPivot[dst]
        guard let srcPer, let dstPer, srcPer > 0, dstPer > 0 else { return nil }
        let rate = dstPer / srcPer
        return rate.isFinite && rate > 0 ? rate : nil
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard amount.isFinite, let rate = quote(from: from, to: to) else { return nil }
        let converted = amount * rate
        return converted.isFinite ? converted : nil
    }

    public var isEmpty: Bool { perPivot.isEmpty }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// Display-currency conversion. Headless keeps `FXBook.stub`; the live app
/// refreshes `book` in the background via `FxRateFeed`.
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
