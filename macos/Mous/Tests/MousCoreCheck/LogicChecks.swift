import Foundation
import MousCore

func parserChecks() {
    let eur = Currency(id: 1, symbol: "eur", name: "Euro", isDefault: true)
    let uah = Currency(id: 2, symbol: "uah", name: "Hryvnia", isDefault: false)
    let eu = Currency(id: 3, symbol: "eu", name: "EU", isDefault: false)

    let completeCases: [(String, String, Double, String)] = [
        ("-50 grocery shop", "eur", -50.0, "grocery shop"),
        ("-24uah idk", "uah", -24.0, "idk"),
        ("-24uah", "uah", -24.0, ""),
        ("-12.50 coffee", "eur", -12.50, "coffee"),
        ("-12.5uah", "uah", -12.5, ""),
        ("-0.50 coffee", "eur", -0.50, "coffee"),
        ("-0.5", "eur", -0.5, ""),
        ("-0.01", "eur", -0.01, ""),
        ("+1200.50 salary", "eur", 1200.50, "salary"),
        ("+100eur", "eur", 100.0, ""),
        ("\u{2212}12.50 food", "eur", -12.50, "food"),
        ("-50  grocery", "eur", -50.0, "grocery"),
        ("-50 grocery  shop", "eur", -50.0, "grocery  shop"),
        ("-24UAH idk", "uah", -24.0, "idk"),
        ("-24 uah", "eur", -24.0, "uah"),
    ]
    for (line, symbol, value, description) in completeCases {
        let result = SpendingLineParser.parse(line: line, currencies: [eur, uah])
        guard case .complete(let draft) = result else {
            Check.fail("expected complete for \(line), got \(result)")
            continue
        }
        Check.equal(draft.currencySymbol.lowercased(), symbol, line)
        Check.accuracy(draft.signedValue, value, 1e-9, line)
        Check.equal(draft.description, description, line)
    }

    switch SpendingLineParser.parse(line: "-50", currencies: [uah]) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "uah")
        Check.accuracy(draft.signedValue, -50)
    default:
        Check.fail("single currency default")
    }

    switch SpendingLineParser.parse(line: "-50", currencies: [eur, uah]) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "eur")
    default:
        Check.fail("two currency default eur")
    }

    switch SpendingLineParser.parse(line: "-24eur extra", currencies: [eu, eur]) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "eur")
        Check.equal(draft.description, "extra")
    default:
        Check.fail("longest prefix eur")
    }

    switch SpendingLineParser.parse(line: "-24eu extra", currencies: [eu, eur]) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "eu")
    default:
        Check.fail("shorter prefix eu")
    }

    Check.equal(SpendingLineParser.parse(line: "", currencies: [eur]), .empty)
    Check.equal(SpendingLineParser.parse(line: "   ", currencies: [eur]), .empty)
    Check.equal(SpendingLineParser.parse(line: "-", currencies: [eur]), .incomplete(.signOnly))
    Check.equal(SpendingLineParser.parse(line: "+", currencies: [eur]), .incomplete(.signOnly))
    Check.equal(SpendingLineParser.parse(line: "-12.", currencies: [eur]), .incomplete(.trailingDecimal))
    Check.equal(SpendingLineParser.parse(line: "-0", currencies: [eur]), .incomplete(.bareZero))
    Check.equal(SpendingLineParser.parse(line: "-0.", currencies: [eur]), .incomplete(.trailingDecimal))
    Check.equal(SpendingLineParser.parse(line: "-24u", currencies: [eur, uah]), .incomplete(.currencyPrefix))
    Check.equal(
        SpendingLineParser.parse(line: "-24uah ", currencies: [eur, uah]),
        .complete(ParsedDraft(signedValue: -24, currencyID: 2, currencySymbol: "uah", description: ""))
    )

    Check.equal(SpendingLineParser.parse(line: "50 grocery", currencies: [eur]), .invalid(.missingSign))
    Check.equal(SpendingLineParser.parse(line: "-12. coffee", currencies: [eur]), .invalid(.notNumber))
    Check.equal(SpendingLineParser.parse(line: "-12.uah", currencies: [uah]), .invalid(.notNumber))
    Check.equal(SpendingLineParser.parse(line: "-12.505", currencies: [eur]), .invalid(.tooManyFractionDigits))
    Check.equal(SpendingLineParser.parse(line: "-12,50 coffee", currencies: [eur]), .invalid(.notNumber))
    Check.equal(SpendingLineParser.parse(line: "-12.50.1", currencies: [eur]), .invalid(.notNumber))
    Check.equal(SpendingLineParser.parse(line: "-.50", currencies: [eur]), .invalid(.notNumber))
    Check.equal(SpendingLineParser.parse(line: "-0 coffee", currencies: [eur]), .invalid(.zeroAmount))
    Check.equal(SpendingLineParser.parse(line: "-0.00", currencies: [eur]), .invalid(.zeroAmount))
    Check.equal(SpendingLineParser.parse(line: "-0.0 coffee", currencies: [eur]), .invalid(.zeroAmount))
    Check.equal(SpendingLineParser.parse(line: "-050.20", currencies: [eur]), .invalid(.leadingZeros))
    Check.equal(SpendingLineParser.parse(line: "-1e2", currencies: [eur]), .invalid(.notNumber))
    Check.equal(SpendingLineParser.parse(line: "-50k beer", currencies: [eur]), .invalid(.unknownCurrency))
    Check.equal(SpendingLineParser.parse(line: "-24.5xyz", currencies: [eur, uah]), .invalid(.unknownCurrency))
    Check.equal(SpendingLineParser.parse(line: "-50grocery", currencies: [eur]), .invalid(.unknownCurrency))
    Check.equal(SpendingLineParser.parse(line: "-24uahidk", currencies: [uah]), .invalid(.unexpectedInput))
    Check.equal(SpendingLineParser.parse(line: "+50-20", currencies: [eur]), .invalid(.unexpectedInput))
    Check.equal(SpendingLineParser.parse(line: "-50", currencies: []), .invalid(.noCurrencies))
    Check.equal(
        SpendingLineParser.parse(
            line: "-50",
            currencies: [uah, Currency(id: 9, symbol: "usd", name: "USD", isDefault: false)]
        ),
        .invalid(.eurRequired)
    )

    let long = String(repeating: "a", count: 129)
    Check.equal(SpendingLineParser.parse(line: "-50 \(long)", currencies: [eur]), .invalid(.descriptionTooLong))
    let ok = String(repeating: "a", count: 128)
    switch SpendingLineParser.parse(line: "-50 \(ok)", currencies: [eur]) {
    case .complete(let draft):
        Check.equal(draft.description.count, 128)
    default:
        Check.fail("128 char description should complete")
    }

    let composing = SpendingLineParser.parse(line: "-12.", currencies: [eur])
    Check.equal(SpendingLineParser.presentation(composing, returnFailed: false, currenciesLoading: false), .composing)
    Check.equal(SpendingLineParser.presentation(composing, returnFailed: true, currenciesLoading: false), .committedInvalid)
    let valid = SpendingLineParser.parse(line: "-12.50 lunch", currencies: [eur])
    Check.equal(SpendingLineParser.presentation(valid, returnFailed: false, currenciesLoading: false), .valid)
    let missing = SpendingLineParser.parse(line: "12", currencies: [eur])
    Check.equal(SpendingLineParser.presentation(missing, returnFailed: false, currenciesLoading: false), .committedInvalid)
    let noFx = SpendingLineParser.parse(line: "-50", currencies: [])
    Check.equal(SpendingLineParser.presentation(noFx, returnFailed: false, currenciesLoading: true), .composing)
}

func dashboardChecks() {
    let today = CivilDate(year: 2026, month: 9, day: 8)
    func tx(value: Double, day: Int) -> Transaction {
        Transaction(
            id: day,
            description: "",
            signedValue: value,
            currencyID: 1,
            accountID: 1,
            civilDate: CivilDate(year: 2026, month: 9, day: day)
        )
    }

    let mixed = DashboardSnapshot.compute(
        balance: 137.5,
        goods: [
            tx(value: -50, day: 8),
            tx(value: -12.5, day: 1),
            tx(value: 200, day: 2),
        ],
        today: today
    )
    Check.accuracy(mixed.spentToday, 50)
    Check.accuracy(mixed.spentMonth, 62.5)
    Check.accuracy(mixed.left, 137.5)
    Check.true(mixed.savedRatio != nil)
    Check.accuracy(mixed.savedRatio ?? 0, (200 - 62.5) / 200)

    let incomeOnly = DashboardSnapshot.compute(
        balance: 80,
        goods: [tx(value: 80, day: 3)],
        today: today
    )
    Check.accuracy(incomeOnly.spentMonth, 0)
    Check.accuracy(incomeOnly.savedRatio ?? -1, 1)

    let zero = DashboardSnapshot.compute(
        balance: 0,
        goods: [tx(value: -0.0, day: 8)],
        today: today
    )
    Check.accuracy(zero.spentToday, 0)
    Check.accuracy(zero.spentMonth, 0)
    Check.true(zero.savedRatio == nil)

    let over = DashboardSnapshot.compute(
        balance: -30,
        goods: [
            tx(value: 10, day: 1),
            tx(value: -40, day: 8),
        ],
        today: today
    )
    Check.accuracy(over.savedRatio ?? 0, (10.0 - 40.0) / 10.0)

    let nonFinite = DashboardSnapshot.compute(
        balance: .nan,
        goods: [
            tx(value: .infinity, day: 8),
            tx(value: .nan, day: 8),
            tx(value: -5, day: 8),
        ],
        today: today
    )
    Check.accuracy(nonFinite.spentToday, 5)
    Check.accuracy(nonFinite.spentMonth, 5)
    Check.accuracy(nonFinite.left, 0)
}

func accountChecks() {
    let card = Account(id: 1, name: "card")
    let main = Account(id: 2, name: "main")
    Check.equal(Account.preferred(from: [card, main])?.id ?? -1, 2)
    Check.equal(Account.preferred(from: [main, card])?.name ?? "", "main")
    Check.equal(Account.preferred(from: [card])?.name ?? "", "card")
    Check.true(Account.preferred(from: []) == nil, "empty accounts")
}

func loopbackChecks() {
    Check.true(LoopbackHTTP.isAllowed(URL(string: "http://127.0.0.1:8000/transactions")))
    Check.true(LoopbackHTTP.isAllowed(URL(string: "http://[::1]/")))
    Check.true(LoopbackHTTP.isLoopbackHost("127.0.0.1"))
    Check.true(LoopbackHTTP.isLoopbackHost("::1"))
    Check.true(!LoopbackHTTP.isAllowed(URL(string: "http://localhost:8000/")))
    Check.true(!LoopbackHTTP.isAllowed(URL(string: "http://example.com/")))
    Check.true(!LoopbackHTTP.isAllowed(URL(string: "https://evil.example/")))
    Check.true(!LoopbackHTTP.isAllowed(URL(string: "file:///etc/passwd")))
    Check.true(!LoopbackHTTP.isAllowed(URL(string: "http://127.0.0.1.attacker.test/")))
    Check.equal(
        LoopbackHTTP.pinBaseURL(URL(string: "http://localhost:8000")!).host ?? "",
        "127.0.0.1"
    )
    Check.equal(
        LoopbackHTTP.pinBaseURL(URL(string: "http://example.com")!).absoluteString,
        APIClient.defaultBaseURL.absoluteString
    )
    Check.true(APIError.transport.isUnreachable)
    Check.true(APIError.timeout.isUnreachable)
    Check.true(!APIError.undecodable.isUnreachable)
    Check.true(!APIError.missingMainAccount.isUnreachable)
    Check.accuracy(ConnectRetry.delay(attempt: 1), 0.4)
    Check.accuracy(ConnectRetry.delay(attempt: 2), 0.8)
    Check.accuracy(ConnectRetry.delay(attempt: 5), ConnectRetry.maxDelay)
    Check.accuracy(ConnectRetry.bootDelay(attempt: 1), ConnectRetry.bootPoll)
    Check.accuracy(ConnectRetry.bootDelay(attempt: ConnectRetry.bootAttempts), ConnectRetry.bootPoll)
    Check.accuracy(ConnectRetry.bootDelay(attempt: ConnectRetry.bootAttempts + 1), 0.4)
}

func civilDateChecks() {
    let zone = TimeZone(secondsFromGMT: 2 * 3600)!
    let instant = Date(timeIntervalSince1970: 1_788_906_600)
    let local = CivilDate.localToday(timeZone: zone, now: instant)
    Check.equal(local, CivilDate(year: 2026, month: 9, day: 9))
    Check.equal(CivilDate.fromUnixUTCMidnight(local.unixUTCMidnight), local)
    Check.equal(
        CivilDate.fromUnixUTCMidnight(Int(instant.timeIntervalSince1970)),
        CivilDate(year: 2026, month: 9, day: 8)
    )
    Check.equal(
        CivilDate.localMonthStart(timeZone: zone, now: instant),
        CivilDate(year: 2026, month: 9, day: 1)
    )
}

func spendRankChecks() {
    let day = CivilDate(year: 2026, month: 9, day: 8)
    func tx(
        id: Int,
        value: Double,
        name: String = "",
        categoryID: Int? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            description: name,
            signedValue: value,
            currencyID: 1,
            accountID: 1,
            civilDate: day,
            categoryID: categoryID
        )
    }
    let food = Category(id: 1, name: "food")
    let rent = Category(id: 2, name: "rent")

    let goodsOnly = SpendRank.mostExpensive(
        transactions: [
            tx(id: 1, value: -10, name: "coffee"),
            tx(id: 2, value: -30, name: "taxi"),
            tx(id: 3, value: 100, name: "pay"),
        ],
        categories: []
    )
    Check.equal(goodsOnly.map(\.title), ["taxi", "coffee"])
    Check.accuracy(goodsOnly[0].signedValue, -30)
    Check.equal(goodsOnly[0].civilDate, day)

    let byCategory = SpendRank.mostExpensive(
        transactions: [
            tx(id: 1, value: -10, name: "coffee", categoryID: 1),
            tx(id: 2, value: -4.5, name: "lunch", categoryID: 1),
            tx(id: 3, value: -30, name: "flat", categoryID: 2),
            tx(id: 4, value: -8, name: "untagged"),
        ],
        categories: [food, rent]
    )
    Check.equal(byCategory.map(\.title), ["rent", "food"])
    Check.accuracy(byCategory[0].signedValue, -30)
    Check.accuracy(byCategory[1].signedValue, -14.5)

    let catalogButNoTags = SpendRank.mostExpensive(
        transactions: [tx(id: 1, value: -12, name: "coffee")],
        categories: [food]
    )
    Check.equal(catalogButNoTags.map(\.title), ["coffee"])

    let mixedDays = SpendRank.mostExpensive(
        transactions: [
            Transaction(
                id: 1,
                description: "today cheap",
                signedValue: -4,
                currencyID: 1,
                accountID: 1,
                civilDate: CivilDate(year: 2026, month: 9, day: 8)
            ),
            Transaction(
                id: 2,
                description: "yesterday big",
                signedValue: -40,
                currencyID: 1,
                accountID: 1,
                civilDate: CivilDate(year: 2026, month: 9, day: 7)
            ),
        ],
        categories: []
    )
    Check.equal(mixedDays.map(\.title), ["yesterday big", "today cheap"])
    Check.equal(mixedDays[0].civilDate, CivilDate(year: 2026, month: 9, day: 7))
    Check.equal(mixedDays[1].civilDate, day)
}

@MainActor
func storeChecks() {
    let store = AppStore()
    Check.true(store.showLaunchSplash, "fresh store shows launch splash")
    Check.equal(store.hasLoadedDashboard, false)
}
