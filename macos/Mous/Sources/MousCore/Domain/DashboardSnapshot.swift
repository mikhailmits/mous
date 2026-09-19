/// Unconverted signed net for one ISO currency, as stored by the API.
public struct CurrencyAmount: Equatable, Sendable {
    public var code: String
    public var amount: Double

    public init(code: String, amount: Double) {
        self.code = code
        self.amount = amount
    }
}

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
        today: CivilDate,
        displayCode: String = "EUR",
        currencyCodeByID: [Int: String] = [:],
        fx: FXBook = .identity,
        balanceCode: String? = nil,
        balances: [CurrencyAmount] = []
    ) -> DashboardSnapshot {
        var spentToday = 0.0
        var spentMonth = 0.0
        var incomeMonth = 0.0
        for good in goods {
            guard good.signedValue.isFinite else { continue }
            guard let source = sourceCode(
                currencyID: good.currencyID,
                map: currencyCodeByID,
                displayCode: displayCode
            ) else { continue }
            guard let signed = MoneyDisplay.convert(
                good.signedValue,
                from: source,
                to: displayCode,
                using: fx
            ) else { continue }
            if signed < 0 {
                let magnitude = -signed
                spentMonth += magnitude
                if good.civilDate == today {
                    spentToday += magnitude
                }
            } else if signed > 0 {
                incomeMonth += signed
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
            left: convertedLeft(
                balance: balance,
                displayCode: displayCode,
                fx: fx,
                balanceCode: balanceCode,
                balances: balances
            ),
            savedRatio: saved
        )
    }

    private static func sourceCode(
        currencyID: Int,
        map: [Int: String],
        displayCode: String
    ) -> String? {
        if let mapped = map[currencyID] { return mapped }
        if map.isEmpty { return displayCode }
        return nil
    }

    private static func convertedLeft(
        balance: Double,
        displayCode: String,
        fx: FXBook,
        balanceCode: String?,
        balances: [CurrencyAmount]
    ) -> Double {
        if !balances.isEmpty {
            var left = 0.0
            for part in balances {
                guard let converted = MoneyDisplay.convert(
                    part.amount,
                    from: part.code,
                    to: displayCode,
                    using: fx
                ) else { continue }
                left += converted
            }
            return left.isFinite ? left : 0
        }
        let unit = balanceCode ?? displayCode
        let converted = MoneyDisplay.convert(
            balance,
            from: unit,
            to: displayCode,
            using: fx
        )
        return converted ?? 0
    }
}
