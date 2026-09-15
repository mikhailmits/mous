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
    /// ISO 4217 code for on-screen amounts. Conversion uses `MoneyDisplay.book`
    /// when quotes exist; missing pairs stay identity.
    public private(set) var displayCurrencyCode: String

    private var currencies: [Currency] = []
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
        self.displayCurrencyCode = MousCurrencyPref.isoCode(for: MousConfigFile.load().currency)
    }

    public var presentation: EntryPresentation {
        SpendingLineParser.presentation(
            parseResult,
            returnFailed: returnFailed,
            currenciesLoading: currenciesLoading
        )
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
    /// runs once from `MousPopup.task`.
    public func reloadPreferences() async {
        applyDisplayCurrencyFromConfig()
        do {
            try await loadCurrenciesAndAccount()
            reparse(clearFailed: false)
        } catch {
            // Display already follows config; parser keeps the last default.
        }
    }

    public func submit() async {
        guard !isSubmitting else { return }
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
            }
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
            isSubmitting = false
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
        var attempt = 0
        while true {
            do {
                if currencies.isEmpty {
                    try await loadCurrenciesAndAccount()
                }
                guard let account = mainAccount else { throw APIError.missingMainAccount }
                let today = CivilDate.localToday(timeZone: timeZone, now: now())
                let categoryID = await promoteRepeatCategory(named: draft.description)
                _ = try await client.createTransaction(
                    description: draft.description,
                    value: draft.signedValue,
                    currencyID: draft.currencyID,
                    occurredOn: today,
                    accountID: account.id,
                    categoryID: categoryID
                )
                if let categoryID {
                    await backfillCategory(categoryID, named: draft.description)
                }
                loadGeneration += 1
                outgoingLine = text
                text = ""
                parseResult = .empty
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
                guard let mainAccount else { throw APIError.missingMainAccount }
                let today = CivilDate.localToday(timeZone: timeZone, now: now())
                let monthStart = CivilDate.localMonthStart(timeZone: timeZone, now: now())
                async let balance = client.balance(accountID: mainAccount.id)
                async let goods = client.transactions(accountID: mainAccount.id, from: monthStart, to: today)
                async let categoryList = client.categories()
                let goodsList = try await goods
                let loadedCategories = try await categoryList
                let codes = Dictionary(uniqueKeysWithValues: currencies.map { ($0.id, $0.symbol) })
                let snapshot = DashboardSnapshot.compute(
                    balance: try await balance,
                    goods: goodsList,
                    today: today,
                    displayCode: displayCurrencyCode,
                    currencyCodeByID: codes,
                    fx: MoneyDisplay.book
                )
                guard generation == loadGeneration else { return }
                self.snapshot = snapshot
                categories = loadedCategories
                monthTransactions = goodsList
                    .filter { $0.signedValue.isFinite }
                    .sorted {
                        if $0.civilDate != $1.civilDate { return $1.civilDate < $0.civilDate }
                        return $0.id > $1.id
                    }
                expensiveMonthRows = SpendRank.mostExpensive(
                    transactions: displayed(monthTransactions),
                    categories: categories
                )
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
        async let accountsTask = client.accounts()
        async let currenciesTask = client.currencies()
        let accounts = try await accountsTask
        currencies = try await currenciesTask
        currenciesLoading = false
        applyDisplayCurrencyFromConfig()
        await syncPreferredDefaultCurrency()
        guard let preferred = Account.preferred(from: accounts) else {
            throw APIError.missingMainAccount
        }
        mainAccount = preferred
    }

    public func displayedAmount(_ signedValue: Double, currencyID: Int) -> Double {
        let from = currencies.first { $0.id == currencyID }?.symbol ?? displayCurrencyCode
        return MoneyDisplay.convert(signedValue, from: from, to: displayCurrencyCode)
    }

    private func displayed(_ goods: [Transaction]) -> [Transaction] {
        goods.map { tx in
            var copy = tx
            copy.signedValue = displayedAmount(tx.signedValue, currencyID: tx.currencyID)
            return copy
        }
    }

    private func promoteRepeatCategory(named description: String) async -> Int? {
        let display = RepeatCategory.displayName(description)
        guard RepeatCategory.shouldPromote(description: display, among: monthTransactions) else {
            return nil
        }
        if let id = RepeatCategory.existingID(matching: display, in: categories) {
            return id
        }
        do {
            if let remote = try await client.category(named: display) {
                mergeCategory(remote)
                return remote.id
            }
            let created = try await client.createCategory(name: display)
            mergeCategory(created)
            return created.id
        } catch {
            do {
                let list = try await client.categories()
                categories = list
                return RepeatCategory.existingID(matching: display, in: list)
            } catch {
                return nil
            }
        }
    }

    private func backfillCategory(_ categoryID: Int, named description: String) async {
        let key = RepeatCategory.normalized(description)
        guard !key.isEmpty else { return }
        let targets = monthTransactions.filter {
            RepeatCategory.normalized($0.description) == key && $0.categoryID == nil
        }
        for tx in targets {
            do {
                _ = try await client.patchTransaction(id: tx.id, categoryID: categoryID)
            } catch {
                return
            }
        }
    }

    private func mergeCategory(_ category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
    }

    private func applyDisplayCurrencyFromConfig() {
        displayCurrencyCode = MousCurrencyPref.isoCode(for: MousConfigFile.load().currency)
    }

    /// Make config `currency` the API default so unsuffixed quick-entry uses it.
    private func syncPreferredDefaultCurrency() async {
        let pref = MousCurrencyPref.pref(for: MousConfigFile.load().currency)
        let symbol = pref.rawValue
        do {
            if let existing = currencyMatching(symbol) {
                if !existing.isDefault {
                    adopt(try await client.setDefaultCurrency(id: existing.id))
                }
                return
            }
            let created = try await client.createCurrency(
                symbol: symbol,
                name: pref.englishName,
                isDefault: true
            )
            adopt(created)
            if !created.isDefault {
                adopt(try await client.setDefaultCurrency(id: created.id))
            }
        } catch {
            do {
                currencies = try await client.currencies()
                if let existing = currencyMatching(symbol), !existing.isDefault {
                    adopt(try await client.setDefaultCurrency(id: existing.id))
                }
            } catch {
                return
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
