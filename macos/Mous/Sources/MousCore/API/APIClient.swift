import Foundation

/// Loopback-only HTTP: pin the API to `127.0.0.1` / `::1`.
/// `localhost` is rewritten because it can resolve off-loopback via DNS or `/etc/hosts`.
public enum LoopbackHTTP: Sendable {
    public static func isLoopbackHost(_ host: String) -> Bool {
        var trimmed = host.lowercased()
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed == "127.0.0.1" || trimmed == "::1"
    }

    public static func isAllowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard url.user == nil, url.password == nil else { return false }
        guard let host = url.host else { return false }
        return isLoopbackHost(host)
    }

    public static func pinBaseURL(_ url: URL) -> URL {
        if isAllowed(url) { return url }
        if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https",
           url.user == nil, url.password == nil,
           let host = url.host?.lowercased(), host == "localhost"
        {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.host = "127.0.0.1"
            if let pinned = parts?.url, isAllowed(pinned) {
                return pinned
            }
        }
        return APIClient.defaultBaseURL
    }
}

public actor APIClient {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8000")!

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL = APIClient.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = LoopbackHTTP.pinBaseURL(baseURL)
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            config.timeoutIntervalForResource = 5
            config.waitsForConnectivity = false
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil
            config.urlCache = nil
            self.session = URLSession(
                configuration: config,
                delegate: LoopbackRedirectDelegate(),
                delegateQueue: nil
            )
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    public func accounts() async throws -> [Account] {
        let dto: CollectionDTO<AccountDTO> = try await get(path: "/accounts")
        return dto.items.map(\.domain)
    }

    public func currencies() async throws -> [Currency] {
        let dto: CollectionDTO<CurrencyDTO> = try await get(path: "/currencies")
        return dto.items.map(\.domain)
    }

    public func categories() async throws -> [Category] {
        do {
            let dto: CollectionDTO<CategoryDTO> = try await get(path: "/categories")
            return dto.items.map(\.domain)
        } catch APIError.server(let status, _, _) where status == 404 {
            return []
        }
    }

    public func balance(accountID: Int) async throws -> Double {
        let dto: BalanceDTO = try await get(path: "/accounts/\(accountID)/balance")
        return try dto.amountValue()
    }

    public func transactions(accountID: Int, from: CivilDate, to: CivilDate) async throws -> [Transaction] {
        var parts = URLComponents(
            url: baseURL.appending(path: "transactions"),
            resolvingAgainstBaseURL: false
        )!
        parts.queryItems = [
            URLQueryItem(name: "account_id", value: String(accountID)),
            URLQueryItem(name: "from_unix_time", value: String(from.unixUTCMidnight)),
            URLQueryItem(name: "to_unix_time", value: String(to.unixUTCMidnight)),
        ]
        guard let url = parts.url else { throw APIError.undecodable }
        let dto: CollectionDTO<TransactionDTO> = try await request(url: url, method: "GET", body: nil)
        return try dto.items.map { try $0.domain() }
    }

    public func createTransaction(
        description: String,
        value: Double,
        currencyID: Int,
        occurredOn: CivilDate,
        accountID: Int? = nil
    ) async throws -> Transaction {
        guard value.isFinite, value != 0 else { throw APIError.undecodable }
        let payload = TransactionCreateDTO(
            name: description,
            value: value,
            currencyId: currencyID,
            accountId: accountID,
            occurredUnixTime: occurredOn.unixUTCMidnight
        )
        let body = try encoder.encode(payload)
        let url = baseURL.appending(path: "transactions")
        let dto: TransactionDTO = try await request(url: url, method: "POST", body: body)
        return try dto.domain()
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return try await request(url: baseURL.appending(path: trimmed), method: "GET", body: nil)
    }

    private func request<T: Decodable>(url: URL, method: String, body: Data?) async throws -> T {
        guard LoopbackHTTP.isAllowed(url) else { throw APIError.transport }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        request.httpShouldHandleCookies = false
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timeout
        } catch {
            throw APIError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport
        }
        if (200..<300).contains(http.statusCode) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.undecodable
            }
        }
        let bodyError = try? decoder.decode(APIErrorBody.self, from: data)
        throw APIError.server(
            status: http.statusCode,
            code: bodyError?.error ?? "error",
            detail: bodyError?.detail ?? ""
        )
    }
}

final class LoopbackRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if LoopbackHTTP.isAllowed(request.url) {
            var pinned = request
            pinned.httpShouldHandleCookies = false
            completionHandler(pinned)
        } else {
            completionHandler(nil)
        }
    }
}
