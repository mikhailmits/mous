/// One row in the Most expensive tip: a category total, or a good when
/// nothing this month is categorized. Ordered most expensive first.
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
    /// Categories with spend this month, most expensive first. If no
    /// expense has a known `categoryID`, fall back to individual goods
    /// in the same order. Dates ride along so the tip can label Today /
    /// Yesterday without changing rank.
    public static func mostExpensive(
        transactions: [Transaction],
        categories: [Category]
    ) -> [SpendRankRow] {
        let expenses = transactions.filter(\.isExpense)
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var totals: [Int: (sum: Double, latest: CivilDate)] = [:]
        for tx in expenses {
            guard let id = tx.categoryID, names[id] != nil else { continue }
            if let existing = totals[id] {
                totals[id] = (existing.sum + tx.signedValue, max(existing.latest, tx.civilDate))
            } else {
                totals[id] = (tx.signedValue, tx.civilDate)
            }
        }
        if !totals.isEmpty {
            return totals
                .map { id, value in
                    SpendRankRow(
                        id: "c-\(id)",
                        title: names[id] ?? "",
                        signedValue: value.sum,
                        civilDate: value.latest
                    )
                }
                .sorted(by: Self.rankOrder)
        }
        return expenses
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
    }

    private static func rankOrder(_ a: SpendRankRow, _ b: SpendRankRow) -> Bool {
        if a.signedValue != b.signedValue { return a.signedValue < b.signedValue }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
