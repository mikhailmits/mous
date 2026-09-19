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
        guard right.allSatisfy(\.isLetter) else { return .notCalc }
        guard let target = matchSymbol(right, currencies: currencies) else { return .notCalc }
        guard let parsed = parseLeft(Substring(left), currencies: currencies) else { return .notCalc }

        let converted = MoneyDisplay.convert(
            parsed.magnitude,
            from: parsed.source.symbol,
            to: target.symbol,
            using: fx
        )
        guard let converted, converted.isFinite else { return .failed }
        let magnitude = abs(converted)
        guard let amount = formatMagnitude(magnitude) else { return .failed }
        return .converted("\(parsed.signPrefix)\(amount)\(target.symbol.lowercased())")
    }

    private struct Left {
        var signPrefix: String
        var magnitude: Double
        var source: Currency
    }

    private static func parseLeft(_ left: Substring, currencies: [Currency]) -> Left? {
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
        guard let source = matchSymbol(afterAmount, currencies: currencies) else { return nil }
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
                if fraction > 2 { return nil }
                index = input.index(after: index)
            }
            if fraction == 0 { return nil }
        }

        guard let magnitude = Double(input[..<index]), magnitude.isFinite, magnitude > 0 else {
            return nil
        }
        return (magnitude, input[index...])
    }

    private static func matchSymbol<S: StringProtocol>(_ raw: S, currencies: [Currency]) -> Currency? {
        let lower = raw.lowercased()
        guard !lower.isEmpty else { return nil }
        let sorted = currencies.sorted { $0.symbol.count > $1.symbol.count }
        for currency in sorted {
            if lower == currency.symbol.lowercased() {
                return currency
            }
        }
        return nil
    }

    private static func formatMagnitude(_ value: Double) -> String? {
        let cents = (value * 100).rounded()
        guard cents > 0, cents.isFinite else { return nil }
        let rounded = cents / 100
        if cents.truncatingRemainder(dividingBy: 100) == 0 {
            return String(Int(rounded))
        }
        if cents.truncatingRemainder(dividingBy: 10) == 0 {
            return String(format: "%.1f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}
