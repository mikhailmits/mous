/// A signed ledger row. `signedValue` is >0 for income and <0 for expense.
public struct Transaction: Equatable, Sendable, Identifiable {
    public var id: Int
    public var description: String
    public var signedValue: Double
    public var currencyID: Int
    public var accountID: Int
    public var civilDate: CivilDate
    public var categoryID: Int?

    public init(
        id: Int,
        description: String,
        signedValue: Double,
        currencyID: Int,
        accountID: Int,
        civilDate: CivilDate,
        categoryID: Int? = nil
    ) {
        self.id = id
        self.description = description
        self.signedValue = signedValue
        self.currencyID = currencyID
        self.accountID = accountID
        self.civilDate = civilDate
        self.categoryID = categoryID
    }

    public var isExpense: Bool { signedValue.isFinite && signedValue < 0 }
    public var isIncome: Bool { signedValue.isFinite && signedValue > 0 }
}
