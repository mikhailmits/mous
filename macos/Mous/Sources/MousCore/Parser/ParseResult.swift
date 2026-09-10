public struct ParsedDraft: Equatable, Sendable {
    public var signedValue: Double
    public var currencyID: Int
    public var currencySymbol: String
    public var description: String

    public init(signedValue: Double, currencyID: Int, currencySymbol: String, description: String) {
        self.signedValue = signedValue
        self.currencyID = currencyID
        self.currencySymbol = currencySymbol
        self.description = description
    }
}

public enum IncompleteReason: Equatable, Sendable {
    case signOnly
    case trailingDecimal
    case bareZero
    case currencyPrefix
}

public enum ParseError: Equatable, Sendable {
    case missingSign
    case notNumber
    case leadingZeros
    case tooManyFractionDigits
    case zeroAmount
    case amountOverflow
    case unknownCurrency
    case unexpectedInput
    case noCurrencies
    case eurRequired
    case descriptionTooLong
}

public enum ParseResult: Equatable, Sendable {
    case empty
    case incomplete(IncompleteReason)
    case complete(ParsedDraft)
    case invalid(ParseError)
}

public enum EntryPresentation: Equatable, Sendable {
    case empty
    case composing
    case valid
    case committedInvalid
}
