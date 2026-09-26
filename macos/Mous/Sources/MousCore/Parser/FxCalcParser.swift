import Foundation

/// Inline FX calculator: `{sign}{amount}{from} to {to}` → `{sign}{amount}{to}`.
///
/// Only a bare amount+currency on the left and a single currency on the right
/// count. `-50 coffee to go` is a normal spending line, not a conversion.
public enum FxCalcParser {
    public enum Outcome: Equatable, Sendable {
        case notCalc
        case converted(String)
        case failed
    }

    public enum Kind: Equatable, Sendable {
        case notCalc
        case ready
        case failed
    }

    public static func kind(
        line: String,
        currencies: [Currency],
        fx: FXBook = MoneyDisplay.book
    ) -> Kind {
        switch apply(line: line, currencies: currencies, fx: fx) {
        case .notCalc:
            return .notCalc
        case .converted:
            return .ready
        case .failed:
            return .failed
        }
    }

    public static func apply(
        line: String,
        currencies: [Currency],
        fx: FXBook = MoneyDisplay.book
    ) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = trimmed.range(
            of: #"\s+to\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return .notCalc
        }
        let left = trimmed[..<split.lowerBound].trimmingCharacters(in: .whitespaces)
        let right = trimmed[split.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return .notCalc }
        guard FxSymbols.isTicker(String(right)), let target = FxSymbols.exact(String(right)) else {
            return .notCalc
        }
        guard let parsed = parseLeft(Substring(left)) else { return .notCalc }

        let converted = MoneyDisplay.convert(
            parsed.magnitude,
            from: parsed.source,
            to: target,
            using: fx
        )
        guard let converted, converted.isFinite else { return .failed }
        let magnitude = abs(converted)
        guard let amount = formatMagnitude(magnitude, places: FxSymbols.fractionDigits(target)) else {
            return .failed
        }
        return .converted("\(parsed.signPrefix)\(amount)\(target)")
    }

    private struct Left {
        var signPrefix: String
        var magnitude: Double
        var source: String
    }

    private static func parseLeft(_ left: Substring) -> Left? {
        var rest = left
        var signPrefix = ""
        if let first = rest.first {
            if first == "+" {
                signPrefix = "+"
                rest = rest.dropFirst()
                rest = rest.drop(while: { $0.isWhitespace })
            } else if first == "-" || first == "\u{2212}" {
                signPrefix = "-"
                rest = rest.dropFirst()
                rest = rest.drop(while: { $0.isWhitespace })
            }
        }
        guard let scanned = scanAmount(rest) else { return nil }
        var afterAmount = scanned.rest
        if afterAmount.first?.isWhitespace == true {
            afterAmount = afterAmount.drop(while: { $0.isWhitespace })
        }
        guard FxSymbols.isTicker(String(afterAmount)), let source = FxSymbols.exact(String(afterAmount)) else {
            return nil
        }
        return Left(signPrefix: signPrefix, magnitude: scanned.magnitude, source: source)
    }

    private static func scanAmount(_ input: Substring) -> (magnitude: Double, rest: Substring)? {
        var index = input.startIndex
        let end = input.endIndex
        guard index < end, input[index] >= "0", input[index] <= "9" else { return nil }

        if input[index] == "0" {
            index = input.index(after: index)
            if index < end, input[index] >= "0", input[index] <= "9" { return nil }
        } else {
            var digits = 0
            while index < end, input[index] >= "0", input[index] <= "9" {
                digits += 1
                if digits > 12 { return nil }
                index = input.index(after: index)
            }
        }

        var fraction = 0
        if index < end, input[index] == "." {
            index = input.index(after: index)
            while index < end, input[index] >= "0", input[index] <= "9" {
                fraction += 1
                if fraction > 8 { return nil }
                index = input.index(after: index)
            }
            if fraction == 0 { return nil }
        }

        guard let magnitude = Double(input[..<index]), magnitude.isFinite, magnitude > 0 else {
            return nil
        }
        return (magnitude, input[index...])
    }

    /// Always uses `.` so the converted insert re-parses as a spend amount in every locale.
    /// `places` is the currency's minor unit (0, 2, 3) or 8 for crypto.
    private static func formatMagnitude(_ value: Double, places: Int) -> String? {
        guard value > 0, value.isFinite, (0...8).contains(places) else { return nil }
        if places == 0 {
            let whole = value.rounded()
            guard whole > 0, whole <= Double(Int.max), let total = Int(exactly: whole) else { return nil }
            return String(total)
        }
        var scale = 1
        for _ in 0..<places { scale *= 10 }
        let units = (value * Double(scale)).rounded()
        guard units > 0, units.isFinite, units <= Double(Int.max), let total = Int(exactly: units) else {
            return nil
        }
        let whole = total / scale
        var frac = total % scale
        var digits = places
        while digits > 0, frac % 10 == 0 {
            frac /= 10
            digits -= 1
        }
        if digits == 0 { return String(whole) }
        let fracText = String(frac)
        let pad = digits - fracText.count
        if pad > 0 {
            return "\(whole)." + String(repeating: "0", count: pad) + fracText
        }
        return "\(whole).\(fracText)"
    }
}
