import Foundation

struct CurrencyDTO: Decodable {
    var id: Int
    var symbol: String
    var name: String
    var isDefault: Bool

    var domain: Currency {
        Currency(id: id, symbol: symbol, name: name, isDefault: isDefault)
    }
}

struct TransactionDTO: Decodable {
    var id: Int
    var name: String
    /// Signed native amount (`>0` income, `<0` expense). Not the FX `amount` field.
    var value: Double
    var currencyId: Int
    var accountId: Int
    var occurredUnixTime: Int
    var categoryId: Int?
    /// Converted to default currency when quoted; ignored for the ledger row.
    var amount: Double?
    var currency: String?

    func domain() throws -> Transaction {
        guard value.isFinite else { throw APIError.undecodable }
        return Transaction(
            id: id,
            description: name,
            signedValue: value,
            currencyID: currencyId,
            accountID: accountId,
            civilDate: CivilDate.fromUnixUTCMidnight(occurredUnixTime),
            categoryID: categoryId
        )
    }
}
