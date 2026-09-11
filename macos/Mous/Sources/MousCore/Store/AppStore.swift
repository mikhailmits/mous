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
        await refresh(firstLoad: !hasLoadedDashboard)
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
                _ = try await client.createTransaction(
                    description: draft.description,
                    value: draft.signedValue,
                    currencyID: draft.currencyID,
                    occurredOn: today,
                    accountID: account.id
                )
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
                let snapshot = DashboardSnapshot.compute(
                    balance: try await balance,
                    goods: goodsList,
                    today: today
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
                    transactions: monthTransactions,
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
        guard let preferred = Account.preferred(from: accounts) else {
            throw APIError.missingMainAccount
        }
        mainAccount = preferred
    }
}
