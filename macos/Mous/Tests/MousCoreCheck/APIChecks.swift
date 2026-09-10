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
        {"account_id":1,"amount":1e309}
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
