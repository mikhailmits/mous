public struct Account: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// Prefer `main` when it exists; otherwise the first account in list order.
    public static func preferred(from accounts: [Account]) -> Account? {
        accounts.first(where: { $0.name == "main" }) ?? accounts.first
    }
}

/// `GET /accounts/{id}/balance`. `amount` is converted to the default currency;
/// `byCurrency` stays native so the client can convert each bucket.
public struct AccountBalance: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        public var currencyID: Int
        public var amount: Double

        public init(currencyID: Int, amount: Double) {
            self.currencyID = currencyID
            self.amount = amount
        }
    }

    public var amount: Double
    /// ISO code for `amount`. Native leftover lives in `byCurrency`.
    public var currency: String?
    public var byCurrency: [Part]

    public init(amount: Double, currency: String? = nil, byCurrency: [Part] = []) {
        self.amount = amount
        self.currency = currency
        self.byCurrency = byCurrency
    }
}
