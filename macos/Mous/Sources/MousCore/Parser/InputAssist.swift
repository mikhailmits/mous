import Foundation

/// Live calculator for the input bar.
///
/// FX (`4 eur to uah`) and arithmetic (`45+34`) produce a line the field can
/// accept. A normal spend line (`-450 uah groceries`) is not a suggestion.
public enum InputAssist {
    public struct Suggestion: Equatable, Sendable {
        /// Replaces the field when the row is clicked or Return is pressed.
        public var insert: String
        /// Row copy, already spaced: `= 160 uah`, `= 79`.
        public var label: String

        public init(insert: String, label: String) {
            self.insert = insert
            self.label = label
        }
    }

    public static func suggest(
        line: String,
        currencies: [Currency],
        fx: FXBook = MoneyDisplay.book
    ) -> Suggestion? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch FxCalcParser.apply(line: trimmed, currencies: currencies, fx: fx) {
        case .converted(let insert):
            return Suggestion(insert: insert, label: "= \(spaced(insert))")
        case .failed, .notCalc:
            break
        }
        return mathSuggestion(trimmed)
    }

    private static func mathSuggestion(_ line: String) -> Suggestion? {
        guard line.allSatisfy(isMathCharacter) else { return nil }
        guard hasBinaryOperator(line) else { return nil }
        guard let value = evaluate(line), value.isFinite else { return nil }
        guard let insert = formatNumber(value) else { return nil }
        if insert == line.filter({ !$0.isWhitespace }) { return nil }
        return Suggestion(insert: insert, label: "= \(insert)")
    }

    private static func isMathCharacter(_ character: Character) -> Bool {
        character.isNumber
            || character == "+"
            || character == "-"
            || character == "\u{2212}"
            || character == "*"
            || character == "/"
            || character == "("
            || character == ")"
            || character == "."
            || character == " "
    }

    /// A lone leading minus is a spend sign, not a calculator.
    private static func hasBinaryOperator(_ line: String) -> Bool {
        var seenOperand = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " {
                index = line.index(after: index)
                continue
            }
            if character.isNumber || character == "." || character == "(" {
                seenOperand = true
            } else if seenOperand, character == "+" || character == "-" || character == "\u{2212}"
                || character == "*" || character == "/"
            {
                return true
            }
            index = line.index(after: index)
        }
        return false
    }

    private static func spaced(_ insert: String) -> String {
        guard let range = insert.range(of: #"[A-Za-z]+$"#, options: .regularExpression) else {
            return insert
        }
        var copy = insert
        copy.insert(" ", at: range.lowerBound)
        return copy
    }

    /// Always uses `.` so the insert re-parses as a spend amount in every locale.
    private static func formatNumber(_ value: Double) -> String? {
        let negative = value < 0
        guard let body = formatMagnitude(abs(value)) else { return nil }
        return negative ? "-\(body)" : body
    }

    private static func formatMagnitude(_ value: Double) -> String? {
        let cents = (value * 100).rounded()
        guard cents.isFinite, let total = Int(exactly: cents) else { return nil }
        let whole = total / 100
        let frac = total % 100
        if frac == 0 { return String(whole) }
        if frac % 10 == 0 { return "\(whole).\(frac / 10)" }
        if frac < 10 { return "\(whole).0\(frac)" }
        return "\(whole).\(frac)"
    }

    // MARK: - Expression

    private static func evaluate(_ line: String) -> Double? {
        var parser = MathParser(line: line)
        guard let value = parser.parseExpression() else { return nil }
        guard parser.exhausted else { return nil }
        return value
    }

    private struct MathParser {
        private let characters: [Character]
        private var index = 0

        init(line: String) {
            characters = Array(line)
        }

        var exhausted: Bool {
            var cursor = index
            while cursor < characters.count, characters[cursor] == " " {
                cursor += 1
            }
            return cursor >= characters.count
        }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "+" || op == "-" || op == "\u{2212}" else { break }
                index += 1
                guard let rhs = parseTerm() else { return nil }
                if op == "+" {
                    value += rhs
                } else {
                    value -= rhs
                }
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "*" || op == "/" else { break }
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "*" {
                    value *= rhs
                } else {
                    if rhs == 0 { return nil }
                    value /= rhs
                }
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            skipSpaces()
            guard let character = peek() else { return nil }
            if character == "+" {
                index += 1
                return parseFactor()
            }
            if character == "-" || character == "\u{2212}" {
                index += 1
                guard let value = parseFactor() else { return nil }
                return -value
            }
            if character == "(" {
                index += 1
                guard let value = parseExpression() else { return nil }
                skipSpaces()
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            skipSpaces()
            let start = index
            var sawDigit = false
            var sawDot = false
            while let character = peek() {
                if character.isNumber {
                    sawDigit = true
                    index += 1
                } else if character == ".", !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard sawDigit, index > start else { return nil }
            return Double(String(characters[start..<index]))
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func skipSpaces() {
            while peek() == " " { index += 1 }
        }
    }
}
