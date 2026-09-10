import Foundation

public enum SpendingLineParser {
    public static let descriptionMaxLength = 128
    private static let maxIntegerDigits = 12

    /// Parses `+/-amount[currency] [description]`.
    /// The sign is stored on the good: `+` → positive income, `-` → negative expense.

    public static func parse(line: String, currencies: [Currency]) -> ParseResult {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }

        let signChar = trimmed[trimmed.startIndex]
        let sign: Double
        switch signChar {
        case "+":
            sign = 1
        case "-", "\u{2212}":
            sign = -1
        default:
            return .invalid(.missingSign)
        }

        let afterSign = trimmed[trimmed.index(after: trimmed.startIndex)...]
        if afterSign.isEmpty {
            return .incomplete(.signOnly)
        }

        switch scanAmount(afterSign) {
        case .failed(let error):
            return .invalid(error)
        case .incomplete(let reason):
            return .incomplete(reason)
        case .scanned(let magnitude, let rest, let zeroOpen):
            if zeroOpen {
                if rest.isEmpty {
                    return .incomplete(.bareZero)
                }
                return .invalid(.zeroAmount)
            }
            return finish(
                sign: sign,
                magnitude: magnitude,
                rest: rest,
                currencies: currencies
            )
        }
    }

    public static func presentation(
        _ result: ParseResult,
        returnFailed: Bool,
        currenciesLoading: Bool
    ) -> EntryPresentation {
        switch result {
        case .empty:
            return .empty
        case .incomplete:
            return returnFailed ? .committedInvalid : .composing
        case .complete:
            return .valid
        case .invalid(.noCurrencies) where currenciesLoading:
            return returnFailed ? .committedInvalid : .composing
        case .invalid:
            return .committedInvalid
        }
    }

    private enum AmountScan {
        case scanned(magnitude: Double, rest: Substring, zeroOpen: Bool)
        case incomplete(IncompleteReason)
        case failed(ParseError)
    }

    private static func scanAmount(_ input: Substring) -> AmountScan {
        var index = input.startIndex
        let end = input.endIndex

        guard index < end, isASCIIDigit(input[index]) else {
            return .failed(.notNumber)
        }

        var intDigits = 0
        if input[index] == "0" {
            intDigits = 1
            index = input.index(after: index)
            if index < end, isASCIIDigit(input[index]) {
                return .failed(.leadingZeros)
            }
        } else {
            while index < end, isASCIIDigit(input[index]) {
                intDigits += 1
                if intDigits > maxIntegerDigits {
                    return .failed(.amountOverflow)
                }
                index = input.index(after: index)
            }
        }

        var fractionDigits = 0
        var hadDot = false
        if index < end, input[index] == "." {
            hadDot = true
            index = input.index(after: index)
            while index < end, isASCIIDigit(input[index]) {
                fractionDigits += 1
                if fractionDigits > 2 {
                    return .failed(.tooManyFractionDigits)
                }
                index = input.index(after: index)
            }
        }

        let amountSlice = input[..<index]
        let rest = input[index...]

        if hadDot, fractionDigits == 0 {
            if rest.isEmpty {
                return .incomplete(.trailingDecimal)
            }
            return .failed(.notNumber)
        }

        if looksLikeScientific(rest) || rest.first == "," || rest.first == "." {
            return .failed(.notNumber)
        }

        guard let magnitude = Double(amountSlice), magnitude.isFinite else {
            return .failed(.notNumber)
        }

        if magnitude == 0 {
            let canExtendFraction = !hadDot || fractionDigits < 2
            if rest.isEmpty, canExtendFraction {
                return .scanned(magnitude: 0, rest: rest, zeroOpen: true)
            }
            return .failed(.zeroAmount)
        }

        return .scanned(magnitude: magnitude, rest: rest, zeroOpen: false)
    }

    private static func finish(
        sign: Double,
        magnitude: Double,
        rest: Substring,
        currencies: [Currency]
    ) -> ParseResult {
        if currencies.isEmpty {
            if rest.isEmpty || rest.first?.isLetter == true || rest.first?.isWhitespace == true {
                return .invalid(.noCurrencies)
            }
        }

        var remaining = rest
        var currency: Currency?

        if let first = remaining.first, first.isLetter {
            switch matchCurrency(remaining, currencies: currencies) {
            case .matched(let matched, let after):
                currency = matched
                remaining = after
            case .incompletePrefix:
                return .incomplete(.currencyPrefix)
            case .unknown:
                return .invalid(.unknownCurrency)
            case .unexpected:
                return .invalid(.unexpectedInput)
            }
        } else if looksLikeScientific(remaining) || remaining.first == "," || remaining.first == "." {
            return .invalid(.notNumber)
        } else if let first = remaining.first, !first.isWhitespace {
            return .invalid(.unexpectedInput)
        }

        if remaining.first?.isWhitespace == true {
            remaining = remaining.drop(while: { $0.isWhitespace })
        } else if !remaining.isEmpty {
            return .invalid(.unexpectedInput)
        }

        let description = String(remaining)
        if description.count > descriptionMaxLength {
            return .invalid(.descriptionTooLong)
        }

        let resolved: Currency
        if let currency {
            resolved = currency
        } else {
            switch defaultCurrency(currencies) {
            case .failed(let error):
                return .invalid(error)
            case .ok(let value):
                resolved = value
            }
        }

        return .complete(
            ParsedDraft(
                signedValue: sign * magnitude,
                currencyID: resolved.id,
                currencySymbol: resolved.symbol,
                description: description
            )
        )
    }

    private enum CurrencyMatch {
        case matched(Currency, Substring)
        case incompletePrefix
        case unknown
        case unexpected
    }

    private static func matchCurrency(_ rest: Substring, currencies: [Currency]) -> CurrencyMatch {
        let lower = rest.lowercased()
        let sorted = currencies.sorted { $0.symbol.count > $1.symbol.count }
        for currency in sorted {
            let symbol = currency.symbol.lowercased()
            guard lower.hasPrefix(symbol) else { continue }
            let cut = rest.index(rest.startIndex, offsetBy: symbol.count)
            let after = rest[cut...]
            if after.isEmpty || after.first?.isWhitespace == true {
                return .matched(currency, after)
            }
            return .unexpected
        }

        let letterRun = rest.prefix { $0.isLetter }
        if letterRun.count == rest.count {
            let prefix = String(letterRun).lowercased()
            let isStrictPrefix = currencies.contains {
                let symbol = $0.symbol.lowercased()
                return symbol.hasPrefix(prefix) && symbol != prefix
            }
            if isStrictPrefix {
                return .incompletePrefix
            }
        }
        return .unknown
    }

    private enum DefaultCurrency {
        case ok(Currency)
        case failed(ParseError)
    }

    private static func defaultCurrency(_ currencies: [Currency]) -> DefaultCurrency {
        if currencies.isEmpty {
            return .failed(.noCurrencies)
        }
        if currencies.count == 1 {
            return .ok(currencies[0])
        }
        if let eur = currencies.first(where: { $0.symbol.lowercased() == "eur" }) {
            return .ok(eur)
        }
        return .failed(.eurRequired)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

    /// `1e2` / `1E-1` — not a currency like `eur`.
    private static func looksLikeScientific(_ rest: Substring) -> Bool {
        guard let first = rest.first, first == "e" || first == "E" else { return false }
        var index = rest.index(after: rest.startIndex)
        if index < rest.endIndex {
            let next = rest[index]
            if next == "+" || next == "-" || next == "\u{2212}" {
                index = rest.index(after: index)
            }
        }
        return index < rest.endIndex && isASCIIDigit(rest[index])
    }
}
