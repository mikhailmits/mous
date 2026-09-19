/// One row in the Most expensive tip: a category total, or an untagged
/// good. Ordered most expensive first.
public struct SpendRankRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var signedValue: Double
    public var civilDate: CivilDate?

    public init(id: String, title: String, signedValue: Double, civilDate: CivilDate? = nil) {
        self.id = id
        self.title = title
        self.signedValue = signedValue
        self.civilDate = civilDate
    }
}

public enum SpendRank {
    /// Categories with spend this month plus untagged goods, most expensive
    /// first. Tagged rows roll up; untagged stay individual so a large rent
    /// line is not hidden by a small coffee category.
    public static func mostExpensive(
        transactions: [Transaction],
        categories: [Category]
    ) -> [SpendRankRow] {
        let expenses = transactions.filter(\.isExpense)
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var totals: [Int: (sum: Double, latest: CivilDate)] = [:]
        var untagged: [Transaction] = []
        for tx in expenses {
            if let id = tx.categoryID, names[id] != nil {
                if let existing = totals[id] {
                    totals[id] = (existing.sum + tx.signedValue, max(existing.latest, tx.civilDate))
                } else {
                    totals[id] = (tx.signedValue, tx.civilDate)
                }
            } else {
                untagged.append(tx)
            }
        }
        let categoryRows = totals.map { id, value in
            SpendRankRow(
                id: "c-\(id)",
                title: names[id] ?? "",
                signedValue: value.sum,
                civilDate: value.latest
            )
        }
        let goodRows = untagged
            .sorted {
                if $0.signedValue != $1.signedValue { return $0.signedValue < $1.signedValue }
                return $0.id > $1.id
            }
            .map {
                SpendRankRow(
                    id: "g-\($0.id)",
                    title: $0.description,
                    signedValue: $0.signedValue,
                    civilDate: $0.civilDate
                )
            }
        return (categoryRows + goodRows).sorted(by: Self.rankOrder)
    }

    private static func rankOrder(_ a: SpendRankRow, _ b: SpendRankRow) -> Bool {
        if a.signedValue != b.signedValue { return a.signedValue < b.signedValue }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
