public struct DashboardSnapshot: Equatable, Sendable {
    public var spentToday: Double
    public var spentMonth: Double
    public var left: Double
    public var savedRatio: Double?

    public init(
        spentToday: Double,
        spentMonth: Double,
        left: Double,
        savedRatio: Double?
    ) {
        self.spentToday = spentToday
        self.spentMonth = spentMonth
        self.left = left
        self.savedRatio = savedRatio
    }

    public static let empty = DashboardSnapshot(
        spentToday: 0,
        spentMonth: 0,
        left: 0,
        savedRatio: nil
    )

    public static func compute(
        balance: Double,
        goods: [Transaction],
        today: CivilDate
    ) -> DashboardSnapshot {
        var spentToday = 0.0
        var spentMonth = 0.0
        var incomeMonth = 0.0
        for good in goods {
            guard good.signedValue.isFinite else { continue }
            if good.isExpense {
                let magnitude = -good.signedValue
                spentMonth += magnitude
                if good.civilDate == today {
                    spentToday += magnitude
                }
            } else if good.isIncome {
                incomeMonth += good.signedValue
            }
        }
        let saved: Double?
        if incomeMonth == 0 || !incomeMonth.isFinite || !spentMonth.isFinite {
            saved = nil
        } else {
            let ratio = (incomeMonth - spentMonth) / incomeMonth
            saved = ratio.isFinite ? ratio : nil
        }
        return DashboardSnapshot(
            spentToday: spentToday,
            spentMonth: spentMonth,
            left: balance.isFinite ? balance : 0,
            savedRatio: saved
        )
    }
}
