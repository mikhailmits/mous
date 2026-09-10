import Foundation

struct CollectionDTO<Item: Decodable>: Decodable {
    var items: [Item]
    var count: Int
}

struct APIErrorBody: Decodable {
    var error: String
    var detail: String
}

struct AccountDTO: Decodable {
    var id: Int
    var name: String

    var domain: Account { Account(id: id, name: name) }
}

struct CurrencyDTO: Decodable {
    var id: Int
    var symbol: String
    var name: String
    var isDefault: Bool

    var domain: Currency {
        Currency(id: id, symbol: symbol, name: name, isDefault: isDefault)
    }
}

struct CategoryDTO: Decodable {
    var id: Int
    var name: String

    var domain: Category { Category(id: id, name: name) }
}

struct BalanceDTO: Decodable {
    var accountId: Int
    var amount: Double

    func amountValue() throws -> Double {
        guard amount.isFinite else { throw APIError.undecodable }
        return amount
    }
}

struct TransactionDTO: Decodable {
    var id: Int
    var name: String
    var value: Double
    var currencyId: Int
    var accountId: Int
    var occurredUnixTime: Int
    var categoryId: Int?

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

struct TransactionCreateDTO: Encodable {
    var name: String
    var value: Double
    var currencyId: Int
    var accountId: Int?
    var occurredUnixTime: Int

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
        try container.encode(currencyId, forKey: .currencyId)
        try container.encode(occurredUnixTime, forKey: .occurredUnixTime)
        if let accountId {
            try container.encode(accountId, forKey: .accountId)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
        case currencyId
        case accountId
        case occurredUnixTime
    }
}
