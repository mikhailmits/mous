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
