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
    ///
    /// Amounts convert into `displayCode` before ranking. Missing FX pairs and
    /// unknown currency ids are omitted so a large UAH line never outranks a
    /// smaller EUR line by raw face value.
    public static func mostExpensive(
        transactions: [Transaction],
        categories: [Category],
        displayCode: String = "EUR",
        currencyCodeByID: [Int: String] = [:],
        fx: FXBook = .identity
    ) -> [SpendRankRow] {
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var totals: [Int: (sum: Double, latest: CivilDate)] = [:]
        var untagged: [(id: Int, title: String, signedValue: Double, civilDate: CivilDate)] = []
        for tx in transactions {
            guard tx.isExpense else { continue }
            guard let source = sourceCode(
                currencyID: tx.currencyID,
                map: currencyCodeByID,
                displayCode: displayCode
            ) else { continue }
            guard let signed = MoneyDisplay.convert(
                tx.signedValue,
                from: source,
                to: displayCode,
                using: fx
            ), signed.isFinite, signed < 0 else { continue }
            if let id = tx.categoryID, names[id] != nil {
                if let existing = totals[id] {
                    totals[id] = (existing.sum + signed, max(existing.latest, tx.civilDate))
                } else {
                    totals[id] = (signed, tx.civilDate)
                }
            } else {
                untagged.append(
                    (id: tx.id, title: tx.description, signedValue: signed, civilDate: tx.civilDate)
                )
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
                    title: $0.title,
                    signedValue: $0.signedValue,
                    civilDate: $0.civilDate
                )
            }
        return (categoryRows + goodRows).sorted(by: Self.rankOrder)
    }

    private static func sourceCode(
        currencyID: Int,
        map: [Int: String],
        displayCode: String
    ) -> String? {
        if let mapped = map[currencyID] { return mapped }
        // Homogeneous ledger / already-converted rows: treat as display units.
        if map.isEmpty { return displayCode }
        return nil
    }

    private static func rankOrder(_ a: SpendRankRow, _ b: SpendRankRow) -> Bool {
        if a.signedValue != b.signedValue { return a.signedValue < b.signedValue }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
