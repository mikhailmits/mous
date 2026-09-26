import Foundation
import MousCore

/// Background EUR-pivot quotes for the calculator and dashboard.
/// Keystrokes never wait on the network; only `MoneyDisplay.book` is swapped.
enum FxRateFeed {
    private static let fiatURL = URL(string: "https://open.er-api.com/v6/latest/EUR")!
    private static let timeout: TimeInterval = 4

    /// Install stub immediately, then refresh once in the background when not headless.
    static func start(headless: Bool) {
        MoneyDisplay.useStubQuotes()
        guard !headless else { return }
        Task.detached(priority: .utility) {
            if let book = await fetchBook() {
                MoneyDisplay.book = book
            }
        }
    }

    private static func fetchBook() async -> FXBook? {
        async let fiat = fetchFiat()
        async let crypto = fetchCrypto()
        let (fiatRates, cryptoRates) = await (fiat, crypto)
        guard !fiatRates.isEmpty || !cryptoRates.isEmpty else { return nil }

        var book = FXBook.stub
        for (code, rate) in fiatRates {
            book.set(base: "EUR", quote: code, rate: rate)
        }
        for (code, eurosPerCoin) in cryptoRates {
            // CoinGecko returns EUR per 1 coin; FXBook wants coin units per 1 EUR.
            let perEur = 1 / eurosPerCoin
            guard perEur.isFinite, perEur > 0 else { continue }
            book.set(base: "EUR", quote: code, rate: perEur)
        }
        return book
    }

    private static func fetchFiat() async -> [String: Double] {
        guard let data = await get(url: fiatURL) else { return [:] }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rates = json["rates"] as? [String: Any]
        else { return [:] }

        var out: [String: Double] = [:]
        out.reserveCapacity(rates.count)
        for (code, value) in rates {
            let key = code.uppercased()
            guard key != "EUR" else { continue }
            let rate: Double?
            if let number = value as? Double {
                rate = number
            } else if let number = value as? NSNumber {
                rate = number.doubleValue
            } else {
                rate = nil
            }
            guard let rate, rate.isFinite, rate > 0 else { continue }
            out[key] = rate
        }
        return out
    }

    private static func fetchCrypto() async -> [String: Double] {
        let ids = Array(Set(FxSymbols.cryptoIDs.values)).sorted()
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "eur"),
            URLQueryItem(name: "precision", value: "full"),
        ]
        guard let url = components.url, let data = await get(url: url) else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        let idToTicker: [String: String] = Dictionary(
            uniqueKeysWithValues: FxSymbols.cryptoIDs.map { ($0.value, $0.key.uppercased()) }
        )
        var out: [String: Double] = [:]
        out.reserveCapacity(idToTicker.count)
        for (id, payload) in json {
            guard let ticker = idToTicker[id] else { continue }
            guard let body = payload as? [String: Any] else { continue }
            let raw = body["eur"]
            let euros: Double?
            if let number = raw as? Double {
                euros = number
            } else if let number = raw as? NSNumber {
                euros = number.doubleValue
            } else if let text = raw as? String {
                euros = Double(text)
            } else {
                euros = nil
            }
            guard let euros, euros.isFinite, euros > 0 else { continue }
            out[ticker] = euros
        }
        return out
    }

    private static func get(url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
