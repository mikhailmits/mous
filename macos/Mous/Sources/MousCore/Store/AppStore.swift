import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public var text = "" {
        didSet { reparse() }
    }

    public private(set) var parseResult: ParseResult = .empty
    public private(set) var snapshot = DashboardSnapshot.empty
    /// This month's rows, newest first — the hover tip on the spend rows.
    public private(set) var monthTransactions: [Transaction] = []
    /// Categories (or goods, if none are tagged) for the Most expensive tip.
    public private(set) var expensiveMonthRows: [SpendRankRow] = []
    private var categories: [Category] = []
    public private(set) var hasLoadedDashboard = false
    public private(set) var isRefreshing = false
    public private(set) var isSubmitting = false
    public private(set) var statusMessage: String?
    public private(set) var returnFailed = false
    public private(set) var commitTick = 0
    public private(set) var rejectTick = 0
    /// Line that just posted; EntryCard ticks it out before the field stays empty.
    public private(set) var outgoingLine = ""

    public var currenciesLoading = true
    /// ISO 4217 code for on-screen amounts. Conversion uses `MoneyDisplay.book`;
    /// missing pairs are omitted from totals instead of treated as 1:1.
    public private(set) var displayCurrencyCode: String
    /// Settings: scramble spent, left, history, and most-expensive amounts.
    public private(set) var hideBalance = false
    /// True while the eye is held down. Amounts show through the dots.
    public var balancePeek = false
    public var amountsConcealed: Bool { hideBalance && !balancePeek }

    private var currencies: [Currency] = []
    private var currencyCodes: [Int: String] = [:]
    /// API balance already converted to `ledgerBalanceCode`. Used only when
    /// `ledgerParts` is empty.
    private var ledgerBalance: Double = 0
    /// ISO code for `ledgerBalance` (`GET .../balance` `currency`).
    private var ledgerBalanceCode: String?
    /// Per-currency signed nets from `GET .../balance` `by_currency`.
    private var ledgerParts: [CurrencyAmount] = []
    private var mainAccount: Account?
    private var loadGeneration = 0
    private let client: APIClient
    private let timeZone: TimeZone
    private let now: () -> Date

    public init(
        client: APIClient = APIClient(),
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.timeZone = timeZone
        self.now = now
        let cfg = MousConfigFile.load()
        self.displayCurrencyCode = MousCurrencyPref.isoCode(for: cfg.currency)
        self.hideBalance = cfg.hideBalance
    }

    public var presentation: EntryPresentation {
        SpendingLineParser.presentation(
            parseResult,
            returnFailed: returnFailed,
            currenciesLoading: currenciesLoading
        )
    }

    public var isFxCalcReady: Bool {
        FxCalcParser.kind(line: text, currencies: currencies) == .ready
    }

    public var fieldDisabled: Bool { isSubmitting }

    /// Blank logo-spin until the API has answered once. Unreachable retries
    /// stay on the splash; a real server error falls through to the cards.
    public var showLaunchSplash: Bool {
        guard !hasLoadedDashboard else { return false }
        if isRefreshing { return true }
        if let statusMessage {
            return statusMessage == APIError.transport.userMessage
        }
        return true
    }

    public func appear() async {
        applyDisplayCurrencyFromConfig()
        await refresh(firstLoad: !hasLoadedDashboard)
    }

    /// Re-read Settings currency when home is shown again. `appear` only
    /// runs once from `MousPopup.task`. Figures convert locally first so the
    /// dashboard does not wait on the default-currency PATCH.
    public func reloadPreferences() async {
        applyDisplayCurrencyFromConfig()
        applyDisplayedFigures()
        loadGeneration += 1
        let generation = loadGeneration
        do {
            try await loadCurrenciesAndAccount()
            guard generation == loadGeneration else { return }
            rememberCurrencyCodes()
            guard generation == loadGeneration else { return }
            applyDisplayedFigures()
            reparse(clearFailed: false)
        } catch {
            guard generation == loadGeneration else { return }
            reparse(clearFailed: false)
        }
    }

    public var assistSuggestion: InputAssist.Suggestion? {
        InputAssist.suggest(line: text, currencies: currencies)
    }

    /// Return or a click on the calculator row. Does not post.
    @discardableResult
    public func acceptAssist() -> Bool {
        guard let suggestion = assistSuggestion else { return false }
        text = suggestion.insert
        // `text` didSet already reparses and clears `returnFailed`.
        return true
    }

    /// Tab / Enter: `{amount}{from} to {to}` or `45+34` becomes the result and does not post.
    /// A failed FX calc still consumes Return so the line is never posted as a good.
    @discardableResult
    public func applyFxCalc() -> Bool {
        if acceptAssist() { return true }
        switch FxCalcParser.apply(line: text, currencies: currencies) {
        case .notCalc:
            return false
        case .converted(let line):
            text = line
            return true
        case .failed:
            returnFailed = true
            rejectTick += 1
            return true
        }
    }

    public func toggleHideBalance() {
        var cfg = MousConfigFile.load()
        cfg.hideBalance.toggle()
        MousConfigFile.save(cfg)
        hideBalance = cfg.hideBalance
        if !hideBalance { balancePeek = false }
    }

    public func submit() async {
        guard !isSubmitting else { return }
        if applyFxCalc() { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if currencies.isEmpty {
            do {
                try await loadCurrenciesAndAccount()
            } catch let error as APIError where !error.isUnreachable {
                statusMessage = error.userMessage
                returnFailed = true
                rejectTick += 1
                return
            } catch {
                if let error = error as? APIError {
                    statusMessage = error.userMessage
                } else {
                    statusMessage = APIError.transport.userMessage
                }
                return
            }
            if applyFxCalc() { return }
        }
        reparse(clearFailed: false)
        let posted: Bool
        switch parseResult {
        case .complete(let draft):
            posted = await post(draft)
        default:
            returnFailed = true
            rejectTick += 1
            posted = false
        }
        if posted {
            await refresh(firstLoad: !hasLoadedDashboard)
        }
    }

    public func retrySubmit() async {
        await submit()
    }

    private func reparse(clearFailed: Bool = true) {
        if clearFailed {
            returnFailed = false
        }
        parseResult = SpendingLineParser.parse(line: text, currencies: currencies)
    }

    private func post(_ draft: ParsedDraft) async -> Bool {
        statusMessage = nil
        let submitted = text
        var attempt = 0
        while true {
            do {
                if currencies.isEmpty {
                    try await loadCurrenciesAndAccount()
                }
                guard mainAccount != nil else { throw APIError.missingMainAccount }
                let today = CivilDate.localToday(timeZone: timeZone, now: now())
                _ = try await client.createTransaction(
                    description: draft.description,
                    value: draft.signedValue,
                    currency: draft.currencySymbol,
                    occurredOn: today
                )
                loadGeneration += 1
                outgoingLine = submitted
                if text == submitted {
                    text = ""
                    parseResult = .empty
                }
                commitTick += 1
                return true
            } catch let error as APIError where error.isUnreachable {
                attempt += 1
                statusMessage = error.userMessage
                do {
                    try await ConnectRetry.sleep(attempt: attempt)
                } catch {
                    rejectTick += 1
                    return false
                }
            } catch let error as APIError {
                statusMessage = error.userMessage
                rejectTick += 1
                return false
            } catch {
                attempt += 1
                statusMessage = APIError.transport.userMessage
                do {
                    try await ConnectRetry.sleep(attempt: attempt)
                } catch {
                    rejectTick += 1
                    return false
                }
            }
        }
    }

    private func refresh(firstLoad: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        isRefreshing = firstLoad && !hasLoadedDashboard
        var attempt = 0
        while true {
            do {
                try await loadCurrenciesAndAccount()
                guard generation == loadGeneration else { return }
                guard mainAccount != nil else { throw APIError.missingMainAccount }
                let today = CivilDate.localToday(timeZone: timeZone, now: now())
                let monthStart = CivilDate.localMonthStart(timeZone: timeZone, now: now())
                let goodsList = try await client.transactions(from: monthStart, to: today)
                rememberCurrencyCodes()
                guard generation == loadGeneration else { return }
                monthTransactions = goodsList
                    .filter { $0.signedValue.isFinite }
                    .sorted {
                        if $0.civilDate != $1.civilDate { return $1.civilDate < $0.civilDate }
                        return $0.id > $1.id
                    }
                applyDisplayedFigures(today: today)
                hasLoadedDashboard = true
                if statusMessage == APIError.transport.userMessage
                    || statusMessage == APIError.timeout.userMessage
                {
                    statusMessage = nil
                }
                isRefreshing = false
                reparse(clearFailed: false)
                return
            } catch let error as APIError where error.isUnreachable {
                guard generation == loadGeneration else { return }
                isRefreshing = false
                statusMessage = error.userMessage
                attempt += 1
                do {
                    if firstLoad {
                        try await ConnectRetry.sleepForBoot(attempt: attempt)
                    } else {
                        try await ConnectRetry.sleep(attempt: attempt)
                    }
                } catch {
                    return
                }
            } catch let error as APIError {
                guard generation == loadGeneration else { return }
                statusMessage = error.userMessage
                isRefreshing = false
                reparse(clearFailed: false)
                return
            } catch {
                guard generation == loadGeneration else { return }
                isRefreshing = false
                statusMessage = APIError.transport.userMessage
                attempt += 1
                do {
                    if firstLoad {
                        try await ConnectRetry.sleepForBoot(attempt: attempt)
                    } else {
                        try await ConnectRetry.sleep(attempt: attempt)
                    }
                } catch {
                    return
                }
            }
        }
    }

    private func loadCurrenciesAndAccount() async throws {
        currenciesLoading = currencies.isEmpty
        currencies = try await client.currencies()
        currenciesLoading = false
        applyDisplayCurrencyFromConfig()
        await syncPreferredDefaultCurrency()
        mainAccount = Account(id: 0, name: "main")
    }

    public func displayedAmount(_ signedValue: Double, currencyID: Int) -> Double? {
        guard let from = currencyCodes[currencyID]
            ?? currencies.first(where: { $0.id == currencyID })?.symbol
        else { return nil }
        return MoneyDisplay.convert(signedValue, from: from, to: displayCurrencyCode)
    }

    private func rememberCurrencyCodes() {
        currencyCodes = Dictionary(uniqueKeysWithValues: currencies.map { ($0.id, $0.symbol) })
    }

    private func applyDisplayedFigures(today: CivilDate? = nil) {
        let day = today ?? CivilDate.localToday(timeZone: timeZone, now: now())
        snapshot = DashboardSnapshot.compute(
            balance: ledgerBalance,
            goods: monthTransactions,
            today: day,
            displayCode: displayCurrencyCode,
            currencyCodeByID: currencyCodes,
            fx: MoneyDisplay.book,
            balanceCode: ledgerBalanceCode
                ?? currencies.first(where: { $0.isDefault })?.symbol,
            balances: ledgerParts
        )
        expensiveMonthRows = SpendRank.mostExpensive(
            transactions: displayed(monthTransactions),
            categories: categories
        )
    }

    private func displayed(_ goods: [Transaction]) -> [Transaction] {
        goods.compactMap { tx in
            guard let amount = displayedAmount(tx.signedValue, currencyID: tx.currencyID) else {
                return nil
            }
            var copy = tx
            copy.signedValue = amount
            return copy
        }
    }

    private func applyDisplayCurrencyFromConfig() {
        let cfg = MousConfigFile.load()
        displayCurrencyCode = MousCurrencyPref.isoCode(for: cfg.currency)
        hideBalance = cfg.hideBalance
        if !hideBalance { balancePeek = false }
    }

    /// Make config `currency` the API default so unsuffixed quick-entry uses it.
    /// `--set-default` auto-creates the currency if the daemon has not seen it
    /// yet, so there is no separate "create currency" step (and no `cur new`).
    private func syncPreferredDefaultCurrency() async {
        let pref = MousCurrencyPref.pref(for: MousConfigFile.load().currency)
        let symbol = pref.rawValue
        if let existing = currencyMatching(symbol), existing.isDefault {
            return
        }
        do {
            adopt(try await client.setDefaultCurrency(symbol: symbol))
        } catch {
            if let list = try? await client.currencies() {
                currencies = list
            }
        }
    }

    private func currencyMatching(_ symbol: String) -> Currency? {
        currencies.first { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
    }

    private func adopt(_ selected: Currency) {
        var next = currencies.filter { $0.id != selected.id }.map {
            Currency(id: $0.id, symbol: $0.symbol, name: $0.name, isDefault: false)
        }
        next.append(
            Currency(id: selected.id, symbol: selected.symbol, name: selected.name, isDefault: true)
        )
        currencies = next
    }
}
