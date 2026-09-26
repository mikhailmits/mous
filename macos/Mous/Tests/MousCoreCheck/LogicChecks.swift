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
        ("-24 uah", "uah", -24.0, ""),
        ("-24 uah latte", "uah", -24.0, "latte"),
        ("-24 uber", "eur", -24.0, "uber"),
        ("+ 10 hii", "eur", 10.0, "hii"),
        ("- 10 hii", "eur", -10.0, "hii"),
        ("+10hii", "eur", 10.0, "hii"),
        ("-10hii", "eur", -10.0, "hii"),
        ("+10eur", "eur", 10.0, ""),
        ("-50k beer", "eur", -50.0, "k beer"),
        ("-50grocery", "eur", -50.0, "grocery"),
        ("-24.5xyz", "eur", -24.5, "xyz"),
        ("-24uahidk", "eur", -24.0, "uahidk"),
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

    switch SpendingLineParser.parse(
        line: "-50",
        currencies: [
            Currency(id: 1, symbol: "eur", name: "Euro", isDefault: false),
            Currency(id: 9, symbol: "usd", name: "US Dollar", isDefault: true),
        ]
    ) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "usd")
    default:
        Check.fail("isDefault currency should win")
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
    Check.equal(SpendingLineParser.parse(line: "-24ua", currencies: [eur, uah]), .incomplete(.currencyPrefix))
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
    switch SpendingLineParser.parse(line: "-24uahidk", currencies: [uah]) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "uah")
        Check.accuracy(draft.signedValue, -24)
        Check.equal(draft.description, "uahidk")
    default:
        Check.fail("uah then extra letters is a note")
    }
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
    Check.equal(SpendingLineParser.presentation(missing, returnFailed: false, currenciesLoading: false), .composing)
    Check.equal(SpendingLineParser.presentation(missing, returnFailed: true, currenciesLoading: false), .committedInvalid)
    let noFx = SpendingLineParser.parse(line: "-50", currencies: [])
    Check.equal(SpendingLineParser.presentation(noFx, returnFailed: false, currenciesLoading: true), .composing)
    Check.equal(SpendingLineParser.presentation(.empty, returnFailed: false, currenciesLoading: false), .empty)
    Check.equal(SpendingLineParser.presentation(.empty, returnFailed: true, currenciesLoading: false), .empty)
    let notNumber = SpendingLineParser.parse(line: "-12.505", currencies: [eur])
    Check.equal(SpendingLineParser.presentation(notNumber, returnFailed: false, currenciesLoading: false), .composing)
    Check.equal(SpendingLineParser.presentation(notNumber, returnFailed: true, currenciesLoading: false), .committedInvalid)
    let unexpected = SpendingLineParser.parse(line: "+50-20", currencies: [eur])
    Check.equal(SpendingLineParser.presentation(unexpected, returnFailed: false, currenciesLoading: false), .composing)
    Check.equal(SpendingLineParser.presentation(unexpected, returnFailed: true, currenciesLoading: false), .committedInvalid)
    Check.equal(SpendingLineParser.presentation(noFx, returnFailed: false, currenciesLoading: false), .composing)
    Check.equal(SpendingLineParser.presentation(noFx, returnFailed: true, currenciesLoading: false), .committedInvalid)
    let prefix = SpendingLineParser.parse(line: "-24u", currencies: [eur, uah])
    Check.equal(SpendingLineParser.presentation(prefix, returnFailed: false, currenciesLoading: false), .composing)
    Check.equal(SpendingLineParser.presentation(prefix, returnFailed: true, currenciesLoading: false), .committedInvalid)
}

func fxCalcChecks() {
    let eur = Currency(id: 1, symbol: "eur", name: "Euro", isDefault: true)
    let usd = Currency(id: 2, symbol: "usd", name: "US Dollar", isDefault: false)
    let uah = Currency(id: 3, symbol: "uah", name: "Hryvnia", isDefault: false)
    let gbp = Currency(id: 4, symbol: "gbp", name: "Pound", isDefault: false)
    let bag = [eur, usd, uah]

    func expectConverted(_ line: String, _ want: String) {
        switch FxCalcParser.apply(line: line, currencies: bag, fx: .stub) {
        case .converted(let got):
            Check.equal(got, want, line)
        default:
            Check.fail("expected converted for \(line)")
        }
    }

    expectConverted("10 eur to uah", "400uah")
    expectConverted("10eur to usd", "11usd")
    expectConverted("10 eur to usd", "11usd")
    expectConverted("-10 eur to usd", "-11usd")
    expectConverted("- 10 eur to usd", "-11usd")
    expectConverted("+ 10 eur to usd", "+11usd")
    expectConverted("+10 EUR TO UAH", "+400uah")
    expectConverted("10.5 eur to usd", "11.55usd")
    expectConverted("-10 eur to eur", "-10eur")
    expectConverted("40 uah to usd", "1.1usd")
    expectConverted("-10 eur  to  usd", "-11usd")

    Check.equal(FxCalcParser.kind(line: "10 eur to usd", currencies: bag, fx: .stub), .ready)
    Check.equal(FxCalcParser.kind(line: "- 10 eur to usd", currencies: bag, fx: .stub), .ready)
    Check.equal(FxCalcParser.kind(line: "10eur to usd", currencies: bag, fx: .stub), .ready)
    Check.equal(FxCalcParser.kind(line: "-50 coffee to go", currencies: bag, fx: .stub), .notCalc)
    Check.equal(FxCalcParser.kind(line: "10 gbp to eur", currencies: bag + [gbp], fx: .stub), .failed)
    Check.equal(FxCalcParser.kind(line: "10 gbp to eur", currencies: bag, fx: .stub), .failed)
    Check.equal(FxCalcParser.kind(line: "10 xyz to eur", currencies: bag, fx: .stub), .notCalc)

    Check.equal(
        FxCalcParser.apply(line: "-50 coffee to go", currencies: bag, fx: .stub),
        .notCalc
    )
    Check.equal(
        FxCalcParser.apply(line: "-10 eur to usd extra", currencies: bag, fx: .stub),
        .notCalc
    )
    Check.equal(
        FxCalcParser.apply(line: "10 eur to", currencies: bag, fx: .stub),
        .notCalc
    )
    Check.equal(
        FxCalcParser.apply(line: "-30 coffee with dave", currencies: bag, fx: .stub),
        .notCalc
    )
    Check.equal(
        FxCalcParser.apply(line: "10 gbp to eur", currencies: bag + [gbp], fx: .stub),
        .failed
    )
    Check.equal(
        FxCalcParser.apply(line: "10 gbp to eur", currencies: bag, fx: .stub),
        .failed
    )

    var cryptoBook = FXBook.stub
    cryptoBook.set(base: "EUR", quote: "BTC", rate: 0.00002)
    switch FxCalcParser.apply(line: "1 btc to eur", currencies: bag, fx: cryptoBook) {
    case .converted(let got):
        Check.equal(got, "50000eur")
    default:
        Check.fail("btc to eur")
    }
    switch FxCalcParser.apply(line: "100 eur to btc", currencies: bag, fx: cryptoBook) {
    case .converted(let got):
        Check.equal(got, "0.002btc")
    default:
        Check.fail("eur to btc")
    }
    Check.true(FxSymbols.exact("xbt") == "btc", "xbt aliases to btc")
    Check.true(FxSymbols.exact("jpy") != nil, "iso fiat is recognized")
    Check.true(FxSymbols.exact("xyz") == nil, "unknown ticker stays out")
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

func moneyDisplayChecks() {
    let previous = MoneyDisplay.book
    defer { MoneyDisplay.book = previous }
    MoneyDisplay.book = .identity

    Check.accuracy(MoneyDisplay.convert(10, from: "EUR", to: "eur") ?? .nan, 10)
    Check.true(MoneyDisplay.convert(10, from: "EUR", to: "USD") == nil, "missing pair is not 1:1")

    var book = FXBook()
    book.set(base: "EUR", quote: "USD", rate: 1.1)
    Check.accuracy(MoneyDisplay.convert(10, from: "EUR", to: "USD", using: book) ?? .nan, 11)
    Check.accuracy(MoneyDisplay.convert(11, from: "USD", to: "EUR", using: book) ?? .nan, 10)
    Check.true(
        MoneyDisplay.convert(10, from: "EUR", to: "UAH", using: book) == nil,
        "unquoted pair is omitted"
    )

    book.set(base: "EUR", quote: "UAH", rate: 40)
    Check.accuracy(MoneyDisplay.convert(11, from: "USD", to: "UAH", using: book) ?? .nan, 400)

    let today = CivilDate(year: 2026, month: 9, day: 8)
    let usdSpend = Transaction(
        id: 1,
        description: "coffee",
        signedValue: -11,
        currencyID: 2,
        accountID: 1,
        civilDate: today
    )
    let converted = DashboardSnapshot.compute(
        balance: 0,
        goods: [usdSpend],
        today: today,
        displayCode: "EUR",
        currencyCodeByID: [2: "USD"],
        fx: book
    )
    Check.accuracy(converted.spentToday, 10)
    Check.accuracy(converted.spentMonth, 10)

    let identity = DashboardSnapshot.compute(
        balance: 0,
        goods: [usdSpend],
        today: today,
        displayCode: "EUR",
        currencyCodeByID: [2: "USD"]
    )
    Check.accuracy(identity.spentToday, 0)
    Check.accuracy(identity.spentMonth, 0)

    Check.accuracy(MoneyDisplay.convert(10, from: "EUR", to: "USD", using: .stub) ?? .nan, 11)
    Check.accuracy(MoneyDisplay.convert(11, from: "USD", to: "EUR", using: .stub) ?? .nan, 10)
    Check.accuracy(MoneyDisplay.convert(10, from: "EUR", to: "UAH", using: .stub) ?? .nan, 400)
    Check.accuracy(MoneyDisplay.convert(40, from: "UAH", to: "USD", using: .stub) ?? .nan, 1.1)

    var ignored = FXBook()
    ignored.set(base: "EUR", quote: "USD", rate: 0)
    ignored.set(base: "EUR", quote: "USD", rate: .nan)
    Check.true(ignored.isEmpty, "non-positive rates stay unquoted")

    let eurSpend = Transaction(
        id: 2,
        description: "lunch",
        signedValue: -10,
        currencyID: 1,
        accountID: 1,
        civilDate: today
    )
    let eurIncome = Transaction(
        id: 3,
        description: "pay",
        signedValue: 200,
        currencyID: 1,
        accountID: 1,
        civilDate: today
    )
    let eurView = DashboardSnapshot.compute(
        balance: 100,
        goods: [eurSpend, eurIncome],
        today: today,
        displayCode: "EUR",
        currencyCodeByID: [1: "EUR"],
        fx: .stub,
        balanceCode: "EUR"
    )
    Check.accuracy(eurView.spentToday, 10)
    Check.accuracy(eurView.left, 100)
    Check.accuracy(eurView.savedRatio ?? 0, (200 - 10) / 200)

    let usdView = DashboardSnapshot.compute(
        balance: 100,
        goods: [eurSpend, eurIncome],
        today: today,
        displayCode: "USD",
        currencyCodeByID: [1: "EUR"],
        fx: .stub,
        balanceCode: "EUR"
    )
    Check.accuracy(usdView.spentToday, 11)
    Check.accuracy(usdView.spentMonth, 11)
    Check.accuracy(usdView.left, 110)
    Check.accuracy(usdView.savedRatio ?? 0, (220 - 11) / 220)

    let mixedLeft = DashboardSnapshot.compute(
        balance: 1989,
        goods: [eurIncome, usdSpend],
        today: today,
        displayCode: "USD",
        currencyCodeByID: [1: "EUR", 2: "USD"],
        fx: .stub,
        balanceCode: "USD",
        balances: [
            CurrencyAmount(code: "EUR", amount: 2000),
            CurrencyAmount(code: "USD", amount: -11),
        ]
    )
    Check.accuracy(mixedLeft.left, 2189)
    Check.accuracy(mixedLeft.spentToday, 11)

    let uahLeft = DashboardSnapshot.compute(
        balance: 127.268,
        goods: [],
        today: today,
        displayCode: "UAH",
        currencyCodeByID: [1: "EUR", 2: "UAH"],
        fx: .stub,
        balanceCode: "EUR",
        balances: [
            CurrencyAmount(code: "EUR", amount: 100),
            CurrencyAmount(code: "UAH", amount: 1090.72),
        ]
    )
    Check.accuracy(uahLeft.left, 5090.72)

    let leftFromApiAmount = DashboardSnapshot.compute(
        balance: 100,
        goods: [],
        today: today,
        displayCode: "UAH",
        fx: .stub,
        balanceCode: "EUR"
    )
    Check.accuracy(leftFromApiAmount.left, 4000)

    let gbp = Transaction(
        id: 4,
        description: "tea",
        signedValue: -8,
        currencyID: 3,
        accountID: 1,
        civilDate: today
    )
    let unquoted = DashboardSnapshot.compute(
        balance: 0,
        goods: [eurSpend, gbp],
        today: today,
        displayCode: "USD",
        currencyCodeByID: [1: "EUR", 3: "GBP"],
        fx: .stub
    )
    Check.accuracy(unquoted.spentToday, 11)
    Check.accuracy(unquoted.spentMonth, 11)

    let convertedRank = SpendRank.mostExpensive(
        transactions: [
            Transaction(
                id: 5,
                description: "usd coffee",
                signedValue: MoneyDisplay.convert(-11, from: "USD", to: "EUR", using: .stub) ?? .nan,
                currencyID: 2,
                accountID: 1,
                civilDate: today
            ),
            Transaction(
                id: 6,
                description: "eur snack",
                signedValue: -8,
                currencyID: 1,
                accountID: 1,
                civilDate: today
            ),
        ],
        categories: []
    )
    Check.equal(convertedRank.map(\.title), ["usd coffee", "eur snack"])
    Check.accuracy(convertedRank[0].signedValue, -10)

    MoneyDisplay.useStubQuotes()
    Check.accuracy(MoneyDisplay.convert(10, from: "EUR", to: "USD") ?? .nan, 11)
}

func repeatCategoryChecks() {
    let day = CivilDate(year: 2026, month: 9, day: 8)
    func tx(_ name: String, id: Int = 1, tagged: Int? = nil) -> Transaction {
        Transaction(
            id: id,
            description: name,
            signedValue: -4,
            currencyID: 1,
            accountID: 1,
            civilDate: day,
            categoryID: tagged
        )
    }
    Check.equal(RepeatCategory.normalized("  Coffee "), "coffee")
    Check.equal(RepeatCategory.displayName("  Coffee "), "Coffee")
    Check.true(!RepeatCategory.shouldPromote(description: "coffee", among: []), "first coffee is not a category")
    Check.true(
        RepeatCategory.shouldPromote(description: "Coffee", among: [tx("coffee")]),
        "second coffee becomes a category"
    )
    Check.true(!RepeatCategory.shouldPromote(description: "tea", among: [tx("coffee")]), "unrelated name")
    Check.true(!RepeatCategory.shouldPromote(description: "   ", among: [tx("   ")]), "blank is not a category")
    Check.equal(RepeatCategory.existingID(matching: "coffee", in: [Category(id: 9, name: "Coffee")]), 9)
    Check.true(RepeatCategory.existingID(matching: "tea", in: [Category(id: 9, name: "Coffee")]) == nil)
    let long = String(repeating: "a", count: 40)
    Check.equal(RepeatCategory.displayName(long).count, RepeatCategory.nameMaxLength)
    Check.equal(RepeatCategory.normalized(long).count, RepeatCategory.nameMaxLength)
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
    Check.equal(byCategory.map(\.title), ["rent", "food", "untagged"])
    Check.accuracy(byCategory[0].signedValue, -30)
    Check.accuracy(byCategory[1].signedValue, -14.5)
    Check.accuracy(byCategory[2].signedValue, -8)

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

func configChecks() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mous-config-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        MousConfigFile.directoryOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }
    MousConfigFile.directoryOverride = dir

    Check.equal(MousTheme.parse("system"), .lime)
    Check.equal(MousTheme.parse("dark"), .lime)
    Check.equal(MousTheme.parse("clay"), .clay)
    Check.equal(MousTheme.parse("white"), .white)
    Check.equal(MousTheme.parse("sea"), .sea)

    let first = MousConfigFile.ensure()
    Check.equal(first.host, "127.0.0.1")
    Check.equal(first.port, 8000)
    Check.equal(first.theme, "lime")
    Check.equal(first.currency, "eur")
    Check.equal(MousCurrencyPref.eur.isoCode, "EUR")
    Check.equal(MousCurrencyPref.usd.isoCode, "USD")
    Check.equal(MousCurrencyPref.uah.isoCode, "UAH")
    Check.equal(MousCurrencyPref.isoCode(for: "usd"), "USD")
    Check.equal(MousCurrencyPref.isoCode(for: "UAH"), "UAH")
    Check.equal(MousCurrencyPref.isoCode(for: "unknown"), "EUR")
    Check.equal(MousCurrencyPref.usd.englishName, "US Dollar")
    Check.equal(MousCurrencyPref.pref(for: "uah"), .uah)
    Check.equal(first.hideBalance, false)
    Check.equal(first.hideBalanceStyle, "scramble")
    Check.equal(HideBalanceStyle.parse("veil"), .veil)
    Check.equal(HideBalanceStyle.parse("  VEIL  "), .veil)
    Check.equal(HideBalanceStyle.parse("nope"), .scramble)
    Check.equal(MousCurrencyPref.usd.glyph, "$")
    Check.equal(MousCurrencyPref.eur.glyph, "€")
    Check.equal(MousCurrencyPref.uah.glyph, "₴")
    Check.equal(first.dev, false)
    Check.equal(first.databasePath, dir.appendingPathComponent("data.db").path)
    assertPublicConfigKeys(at: MousConfigFile.configURL())

    var cfg = first
    cfg.theme = "clay"
    cfg.currency = "uah"
    cfg.dev = true
    cfg.hideBalance = true
    cfg.hideBalanceStyle = "veil"
    MousConfigFile.save(cfg)
    let loaded = MousConfigFile.load()
    Check.equal(loaded.theme, "clay")
    Check.equal(loaded.currency, "uah")
    Check.equal(loaded.dev, true)
    Check.equal(loaded.hideBalance, true)
    Check.equal(loaded.hideBalanceStyle, "veil")
    assertPublicConfigKeys(at: MousConfigFile.configURL())

    let partial = dir.appendingPathComponent("config.json")
    try? Data("{ \"host\": \"0.0.0.0\", \"port\": 9000, \"theme\": \"dark\" }\n".utf8).write(to: partial)
    let filled = MousConfigFile.ensure()
    Check.equal(filled.host, "0.0.0.0")
    Check.equal(filled.port, 9000)
    Check.equal(filled.theme, "lime")
    Check.equal(filled.hideBalance, false)
    Check.equal(filled.hideBalanceStyle, "scramble")
    assertPublicConfigKeys(at: MousConfigFile.configURL())

    try? Data("{ \"hide_balance_style\": \"nope\" }\n".utf8).write(to: partial)
    let unknownStyle = MousConfigFile.load()
    Check.equal(unknownStyle.hideBalanceStyle, "scramble")
}

/// `config.json` must expose the public keys and must not revive removed ones.
func assertPublicConfigKeys(at url: URL) {
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        Check.fail("config.json unreadable at \(url.path)")
        return
    }
    for key in [
        "host", "port", "database_path", "dev", "theme", "currency",
        "hide_balance", "hide_balance_style",
    ] {
        Check.true(obj[key] != nil, "config missing \(key)")
    }
    for key in ["jev_api_key", "notify_in_app", "notify_macos", "report_period"] {
        Check.true(obj[key] == nil, "config must not contain \(key)")
    }
}

func assistChecks() {
    let eur = Currency(id: 1, symbol: "eur", name: "Euro", isDefault: true)
    let usd = Currency(id: 2, symbol: "usd", name: "US Dollar", isDefault: false)
    let uah = Currency(id: 3, symbol: "uah", name: "Hryvnia", isDefault: false)
    let bag = [eur, usd, uah]

    func expect(_ line: String, _ insert: String, _ label: String) {
        guard let suggestion = InputAssist.suggest(line: line, currencies: bag, fx: .stub) else {
            Check.fail("expected suggestion for \(line)")
            return
        }
        Check.equal(suggestion.insert, insert, line)
        Check.equal(suggestion.label, label, line)
    }

    expect("45+34", "79", "= 79")
    expect("45 + 34", "79", "= 79")
    expect("12*3", "36", "= 36")
    expect("100/4", "25", "= 25")
    expect("(2+3)*4", "20", "= 20")
    expect("4 eur to uah", "160uah", "= 160 uah")
    expect("-450 uah to eur", "-11.25eur", "= -11.25 eur")
    Check.true(InputAssist.suggest(line: "-450 uah", currencies: bag, fx: .stub) == nil, "spend line is not a calc")
    Check.true(InputAssist.suggest(line: "-450uah groceries", currencies: bag, fx: .stub) == nil, "glued spend is not a calc")
    Check.true(InputAssist.suggest(line: "-450", currencies: bag, fx: .stub) == nil, "a lone amount is not a calc")

    switch SpendingLineParser.parse(line: "-450 uah", currencies: bag) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "uah")
        Check.accuracy(draft.signedValue, -450, 1e-9)
        let shown = MoneyDisplay.convert(draft.signedValue, from: "uah", to: "eur", using: .stub)
        Check.accuracy(shown ?? 0, -11.25, 1e-9, "uah displays as eur")
    default:
        Check.fail("expected -450 uah to parse")
    }
    switch SpendingLineParser.parse(line: "-450uah", currencies: bag) {
    case .complete(let draft):
        Check.equal(draft.currencySymbol, "uah")
        Check.accuracy(draft.signedValue, -450, 1e-9)
    default:
        Check.fail("expected -450uah to parse")
    }
}

func balanceMaskChecks() {
    let samples = (0..<40).map { _ in BalanceMask.make() }
    for sample in samples {
        Check.true(BalanceMask.isMasked(sample), sample)
        Check.equal(sample.count, 6, sample)
    }
    Check.true(Set(samples).count > 1, "masks should not all match")
    Check.true(!BalanceMask.isMasked(""))
    Check.true(!BalanceMask.isMasked("€12.00"))
    Check.true(!BalanceMask.isMasked("Saved 59%."))
    let veil = BalanceMask.veil(length: 4)
    Check.equal(veil, "••••")
    Check.true(BalanceMask.isVeil(veil), veil)
    Check.true(!BalanceMask.isMasked(veil), veil)
    Check.true(!BalanceMask.isVeil("?#*!??"))
    Check.equal(BalanceMask.make(style: .veil, length: 4), "••••")
    Check.true(BalanceMask.isMasked(BalanceMask.make(style: .scramble)))
}

func updateVersionChecks() {
    Check.equal(UpdateChecker.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
    Check.true(UpdateChecker.isRemoteNewer(installed: "1.0.0", remote: "1.0.1"), "1.0.1 is newer than 1.0.0")
    Check.equal(UpdateChecker.compareVersions("v0.1.3", "0.1.3"), .orderedSame)
    Check.true(!UpdateChecker.isRemoteNewer(installed: "v0.1.3", remote: "0.1.3"), "v prefix is the same version")
    Check.equal(UpdateChecker.compareVersions("0.1.3", "0.1.3"), .orderedSame)
    Check.true(!UpdateChecker.isRemoteNewer(installed: "0.1.3", remote: "0.1.3"), "same version is not newer")
}

@MainActor
func storeChecks() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mous-store-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        MousConfigFile.directoryOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }
    MousConfigFile.directoryOverride = dir
    var cfg = MousConfigFile.ensure()
    cfg.currency = "uah"
    MousConfigFile.save(cfg)

    let store = AppStore()
    Check.true(store.showLaunchSplash, "fresh store shows launch splash")
    Check.equal(store.hasLoadedDashboard, false)
    Check.equal(store.displayCurrencyCode, "UAH")
}
