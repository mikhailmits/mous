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

struct CurrencyCreateDTO: Encodable {
    var symbol: String
    var name: String
    var isDefault: Bool
}

struct CurrencyPatchDTO: Encodable {
    var isDefault: Bool
}

struct CategoryDTO: Decodable {
    var id: Int
    var name: String

    var domain: Category { Category(id: id, name: name) }
}

struct BalancePartDTO: Decodable {
    var currencyId: Int
    var amount: Double
}

struct BalanceDTO: Decodable {
    var accountId: Int
    var amount: Double
    var currency: String?
    var byCurrency: [BalancePartDTO]?

    func domain() throws -> AccountBalance {
        guard amount.isFinite else { throw APIError.undecodable }
        var parts: [AccountBalance.Part] = []
        for part in byCurrency ?? [] {
            guard part.amount.isFinite else { throw APIError.undecodable }
            parts.append(AccountBalance.Part(currencyID: part.currencyId, amount: part.amount))
        }
        return AccountBalance(amount: amount, currency: currency, byCurrency: parts)
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
    var categoryId: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
        try container.encode(currencyId, forKey: .currencyId)
        try container.encode(occurredUnixTime, forKey: .occurredUnixTime)
        if let accountId {
            try container.encode(accountId, forKey: .accountId)
        }
        if let categoryId {
            try container.encode(categoryId, forKey: .categoryId)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
        case currencyId
        case accountId
        case occurredUnixTime
        case categoryId
    }
}

struct TransactionPatchDTO: Encodable {
    var categoryId: Int
}

struct CategoryCreateDTO: Encodable {
    var name: String
}
