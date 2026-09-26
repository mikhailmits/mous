import Foundation
import MousCore

final class ScriptedMou: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String]] = []
    var handler: ([String]) -> MouResult = { _ in
        MouResult(status: 0, stdout: Data(), stderr: Data())
    }

    func run(_ args: [String]) throws -> MouResult {
        lock.lock()
        calls.append(args)
        let result = handler(args)
        lock.unlock()
        return result
    }

    var argv: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func last() -> [String] {
        argv.last ?? []
    }
}

func apiClientChecks() async {
    let script = ScriptedMou()
    let client = APIClient(runner: script.run)
    let date = CivilDate(year: 2026, month: 9, day: 8)

    script.handler = { _ in
        MouResult(status: 0, stdout: Data("""
        {"id":1,"name":"coffee","value":-12.5,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600,"category_id":null}
        """.utf8), stderr: Data())
    }
    do {
        let tx = try await client.createTransaction(
            description: "",
            value: -12.5,
            currency: "eur",
            occurredOn: date
        )
        Check.accuracy(tx.signedValue, -12.5)
        Check.equal(tx.description, "coffee")
        let args = script.last()
        Check.equal(args.first ?? "", "new")
        Check.true(args.contains("-12.5"), "amount argv")
        Check.true(args.contains("--name"), "name flag")
        Check.equal(args[args.firstIndex(of: "--name")! + 1], "")
        Check.equal(args[args.firstIndex(of: "--curr")! + 1], "eur")
        Check.equal(args[args.firstIndex(of: "--date")! + 1], date.isoDay)
        Check.true(!args.contains("--account-id"), "account id omitted")
        Check.true(!args.contains("--currency-id"), "currency id omitted")
        Check.true(!args.contains("--category-id"), "category id omitted")
        Check.true(args.contains("--json"), "json flag")
    } catch {
        Check.fail("createTransaction failed: \(error)")
    }

    script.handler = { _ in
        MouResult(status: 0, stdout: Data("""
        {"id":3,"name":"coffee","value":-12.5,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600,"category_id":1}
        """.utf8), stderr: Data())
    }
    do {
        let tx = try await client.createTransaction(
            description: "coffee",
            value: -12.5,
            currency: "eur",
            occurredOn: date
        )
        Check.equal(tx.categoryID ?? -1, 1)
    } catch {
        Check.fail("createTransaction with category_id failed: \(error)")
    }

    script.handler = { _ in
        MouResult(status: 0, stdout: Data("""
        {"id":4,"symbol":"usd","name":"US Dollar","is_default":true}
        """.utf8), stderr: Data())
    }
    do {
        let currency = try await client.createCurrency(symbol: "usd", name: "US Dollar", isDefault: true)
        Check.equal(currency.symbol, "usd")
        Check.equal(currency.name, "US Dollar")
        Check.true(currency.isDefault)
        Check.equal(script.last(), ["cur", "new", "usd", "--name", "US Dollar", "--default", "--json"])
    } catch {
        Check.fail("createCurrency failed: \(error)")
    }

    script.handler = { _ in
        MouResult(status: 0, stdout: Data("""
        {"id":1,"symbol":"eur","name":"Euro","is_default":true}
        """.utf8), stderr: Data())
    }
    do {
        let currency = try await client.setDefaultCurrency(symbol: "eur")
        Check.equal(currency.id, 1)
        Check.true(currency.isDefault)
        Check.equal(script.last(), ["cur", "--set-default", "eur", "--json"])
    } catch {
        Check.fail("setDefaultCurrency failed: \(error)")
    }

    await finiteJSONChecks(date: date)

    script.handler = { _ in
        MouResult(status: 1, stdout: Data(), stderr: Data("mou: cannot talk to daemon: connection refused\n".utf8))
    }
    do {
        _ = try await client.currencies()
        Check.fail("daemon failure should be unreachable")
    } catch let error as APIError {
        Check.true(error.isUnreachable, "daemon down is transport")
    } catch {
        Check.fail("daemon down: unexpected \(error)")
    }
}

private func finiteJSONChecks(date: CivilDate) async {
    let script = ScriptedMou()
    let client = APIClient(runner: script.run)

    script.handler = { _ in
        MouResult(status: 0, stdout: Data("""
        {"id":1,"name":"bad","value":1e309,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600}
        """.utf8), stderr: Data())
    }
    do {
        _ = try await client.createTransaction(
            description: "bad",
            value: -1,
            currency: "eur",
            occurredOn: date
        )
        Check.fail("infinite JSON value should be undecodable")
    } catch let error as APIError {
        Check.equal(error, .undecodable)
    } catch {
        Check.fail("infinite JSON: unexpected \(error)")
    }

    script.handler = { _ in
        MouResult(status: 0, stdout: Data("""
        [{"id":1,"name":"bad","value":-1e309,"currency_id":1,"account_id":1,"occurred_unix_time":1757289600}]
        """.utf8), stderr: Data())
    }
    do {
        _ = try await client.transactions(from: date, to: date)
        Check.fail("infinite JSON value should be undecodable")
    } catch let error as APIError {
        Check.equal(error, .undecodable)
    } catch {
        Check.fail("infinite value: unexpected \(error)")
    }
}
