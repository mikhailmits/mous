public struct Currency: Equatable, Sendable, Identifiable, Hashable {
    public var id: Int
    public var symbol: String
    public var name: String
    public var isDefault: Bool

    public init(id: Int, symbol: String, name: String, isDefault: Bool) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.isDefault = isDefault
    }
}
