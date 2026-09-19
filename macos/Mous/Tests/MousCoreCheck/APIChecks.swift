import Foundation
import MousCore

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let current = Self.handler else { throw URLError(.unknown) }
            let (status, data) = try current(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class LockBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
    init(_ value: Value) { storage = value }
}

func apiClientChecks() async {
    let capturedBody = LockBox<Data?>(nil)
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        let body = """
        {"id":1,"name":"coffee","value":-12.5,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600,"category_id":null}
        """
        return (201, Data(body.utf8))
    }
    defer { StubURLProtocol.handler = nil }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    let client = APIClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)
    let date = CivilDate(year: 2026, month: 9, day: 8)
    do {
        let tx = try await client.createTransaction(
            description: "",
            value: -12.5,
            currencyID: 1,
            occurredOn: date
        )
        Check.accuracy(tx.signedValue, -12.5)
        Check.equal(tx.description, "coffee")
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing POST body")
            return
        }
        Check.true(json["account_id"] == nil, "account_id should be omitted")
        Check.equal(json["name"] as? String ?? "missing", "")
        Check.accuracy((json["value"] as? NSNumber)?.doubleValue ?? 0, -12.5)
        Check.equal((json["currency_id"] as? NSNumber)?.intValue ?? -1, 1)
        Check.equal((json["occurred_unix_time"] as? NSNumber)?.intValue ?? -1, date.unixUTCMidnight)
    } catch {
        Check.fail("createTransaction failed: \(error)")
    }

    capturedBody.value = nil
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        let body = """
        {"id":2,"name":"tea","value":-3,"currency_id":1,"account_id":9,"occurred_unix_time":1757289600}
        """
        return (201, Data(body.utf8))
    }
    do {
        _ = try await client.createTransaction(
            description: "tea",
            value: -3,
            currencyID: 1,
            occurredOn: date,
            accountID: 9
        )
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing POST body with account_id")
            return
        }
        Check.equal((json["account_id"] as? NSNumber)?.intValue ?? -1, 9)
    } catch {
        Check.fail("createTransaction with accountID failed: \(error)")
    }

    StubURLProtocol.handler = { _ in
        let body = """
        {"items":[{"id":1,"name":"food"},{"id":2,"name":"rent"}],"count":2}
        """
        return (200, Data(body.utf8))
    }
    do {
        let cats = try await client.categories()
        Check.equal(cats.map(\.name), ["food", "rent"])
    } catch {
        Check.fail("categories failed: \(error)")
    }

    StubURLProtocol.handler = { _ in
        return (404, Data(#"{"detail":"Not Found"}"#.utf8))
    }
    do {
        let cats = try await client.categories()
        Check.equal(cats.count, 0)
    } catch {
        Check.fail("missing categories catalog should be empty: \(error)")
    }

    capturedBody.value = nil
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        return (201, Data(#"{"id":7,"name":"coffee"}"#.utf8))
    }
    do {
        let cat = try await client.createCategory(name: "coffee")
        Check.equal(cat.id, 7)
        Check.equal(cat.name, "coffee")
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing createCategory body")
            return
        }
        Check.equal(json["name"] as? String ?? "", "coffee")
    } catch {
        Check.fail("createCategory failed: \(error)")
    }

    StubURLProtocol.handler = { _ in
        return (200, Data(#"{"id":7,"name":"coffee"}"#.utf8))
    }
    do {
        let cat = try await client.category(named: "coffee")
        Check.equal(cat?.id ?? -1, 7)
    } catch {
        Check.fail("category(named:) failed: \(error)")
    }

    StubURLProtocol.handler = { _ in
        return (404, Data(#"{"detail":"Not Found"}"#.utf8))
    }
    do {
        let cat = try await client.category(named: "missing")
        Check.true(cat == nil, "missing category is nil")
    } catch {
        Check.fail("missing category should be nil: \(error)")
    }

    capturedBody.value = nil
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        let body = """
        {"id":3,"name":"coffee","value":-4,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600,"category_id":7}
        """
        return (200, Data(body.utf8))
    }
    do {
        let tx = try await client.patchTransaction(id: 3, categoryID: 7)
        Check.equal(tx.categoryID ?? -1, 7)
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing patchTransaction body")
            return
        }
        Check.equal((json["category_id"] as? NSNumber)?.intValue ?? -1, 7)
    } catch {
        Check.fail("patchTransaction failed: \(error)")
    }

    capturedBody.value = nil
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        let body = """
        {"id":9,"name":"coffee","value":-4,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600,"category_id":7}
        """
        return (201, Data(body.utf8))
    }
    do {
        _ = try await client.createTransaction(
            description: "coffee",
            value: -4,
            currencyID: 1,
            occurredOn: date,
            categoryID: 7
        )
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing POST body with category_id")
            return
        }
        Check.equal((json["category_id"] as? NSNumber)?.intValue ?? -1, 7)
        Check.true(json["account_id"] == nil, "account_id still omitted")
    } catch {
        Check.fail("createTransaction with categoryID failed: \(error)")
    }

    StubURLProtocol.handler = { _ in
        let body = """
        {"id":3,"name":"coffee","value":-12.5,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600,"category_id":1}
        """
        return (201, Data(body.utf8))
    }
    do {
        let tx = try await client.createTransaction(
            description: "coffee",
            value: -12.5,
            currencyID: 1,
            occurredOn: date
        )
        Check.equal(tx.categoryID ?? -1, 1)
    } catch {
        Check.fail("createTransaction with category_id failed: \(error)")
    }

    capturedBody.value = nil
    let capturedMethod = LockBox<String?>(nil)
    let capturedPath = LockBox<String?>(nil)
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        capturedMethod.value = request.httpMethod
        capturedPath.value = request.url?.path
        let body = """
        {"id":4,"symbol":"usd","name":"US Dollar","is_default":true}
        """
        return (201, Data(body.utf8))
    }
    do {
        let currency = try await client.createCurrency(symbol: "usd", name: "US Dollar", isDefault: true)
        Check.equal(currency.symbol, "usd")
        Check.equal(currency.name, "US Dollar")
        Check.true(currency.isDefault)
        Check.equal(capturedMethod.value ?? "", "POST")
        Check.true(capturedPath.value?.hasSuffix("/currencies") == true, "POST /currencies")
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing createCurrency body")
            return
        }
        Check.equal(json["symbol"] as? String ?? "", "usd")
        Check.equal(json["name"] as? String ?? "", "US Dollar")
        Check.equal((json["is_default"] as? NSNumber)?.boolValue ?? false, true)
    } catch {
        Check.fail("createCurrency failed: \(error)")
    }

    capturedBody.value = nil
    StubURLProtocol.handler = { request in
        capturedBody.value = requestBody(request)
        capturedMethod.value = request.httpMethod
        capturedPath.value = request.url?.path
        let body = """
        {"id":1,"symbol":"eur","name":"Euro","is_default":true}
        """
        return (200, Data(body.utf8))
    }
    do {
        let currency = try await client.setDefaultCurrency(id: 1)
        Check.equal(currency.id, 1)
        Check.true(currency.isDefault)
        Check.equal(capturedMethod.value ?? "", "PATCH")
        Check.true(capturedPath.value?.hasSuffix("/currencies/1") == true, "PATCH /currencies/1")
        guard let body = capturedBody.value,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Check.fail("missing setDefaultCurrency body")
            return
        }
        Check.equal((json["is_default"] as? NSNumber)?.boolValue ?? false, true)
        Check.true(json["symbol"] == nil, "patch should only send is_default")
    } catch {
        Check.fail("setDefaultCurrency failed: \(error)")
    }

    await finiteJSONChecks(session: session, date: date)
}

private func finiteJSONChecks(session: URLSession, date: CivilDate) async {
    let client = APIClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

    StubURLProtocol.handler = { _ in
        let body = """
        {"id":1,"name":"bad","value":1e309,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600}
        """
        return (201, Data(body.utf8))
    }
    do {
        _ = try await client.createTransaction(
            description: "bad",
            value: -1,
            currencyID: 1,
            occurredOn: date
        )
        Check.fail("infinite JSON value should be undecodable")
    } catch let error as APIError {
        Check.equal(error, .undecodable)
    } catch {
        Check.fail("infinite JSON: unexpected \(error)")
    }

    StubURLProtocol.handler = { _ in
        let body = """
        {"items":[{"id":1,"name":"bad","value":-1e309,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600}],"count":1}
        """
        return (200, Data(body.utf8))
    }
    do {
        _ = try await client.transactions(
            accountID: 1,
            from: date,
            to: date
        )
        Check.fail("infinite JSON value should be undecodable")
    } catch let error as APIError {
        Check.equal(error, .undecodable)
    } catch {
        Check.fail("infinite value: unexpected \(error)")
    }

    StubURLProtocol.handler = { _ in
        let body = """
        {"account_id":1,"amount":1e309,"by_currency":[]}
        """
        return (200, Data(body.utf8))
    }
    do {
        _ = try await client.balance(accountID: 1)
        Check.fail("infinite balance should be undecodable")
    } catch let error as APIError {
        Check.equal(error, .undecodable)
    } catch {
        Check.fail("infinite balance: unexpected \(error)")
    }

    StubURLProtocol.handler = { _ in
        let body = """
        {"account_id":1,"amount":0,"by_currency":[{"currency_id":1,"amount":1e309}]}
        """
        return (200, Data(body.utf8))
    }
    do {
        _ = try await client.balance(accountID: 1)
        Check.fail("infinite by_currency should be undecodable")
    } catch let error as APIError {
        Check.equal(error, .undecodable)
    } catch {
        Check.fail("infinite by_currency: unexpected \(error)")
    }
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
