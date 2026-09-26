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

public struct MouResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public typealias MouRunner = @Sendable ([String]) throws -> MouResult

/// Finds `mou` / `mousd` and runs one CLI invocation.
public enum MouLaunch {
    public static func resolve() -> (mou: String, mousd: String?) {
        let env = ProcessInfo.processInfo.environment
        if let mou = env["MOU_BIN"], !mou.isEmpty {
            let daemon = env["MOUSD_BIN"].flatMap { $0.isEmpty ? nil : $0 }
            return (mou, daemon)
        }
        let fm = FileManager.default
        if let exe = Bundle.main.executableURL {
            let dir = exe.deletingLastPathComponent()
            let beside = executablePair(mou: dir.appendingPathComponent("mou"), mousd: dir.appendingPathComponent("mousd"))
            if let beside { return beside }
        }
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<8 {
            for config in ["release", "debug"] {
                let root = dir.appendingPathComponent("rust/target/\(config)", isDirectory: true)
                if let pair = executablePair(
                    mou: root.appendingPathComponent("mou"),
                    mousd: root.appendingPathComponent("mousd")
                ) {
                    return pair
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return ("mou", nil)
    }

    public static func run(_ args: [String]) throws -> MouResult {
        let found = resolve()
        let process = Process()
        if found.mou.contains("/") {
            process.executableURL = URL(fileURLWithPath: found.mou)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [found.mou] + args
        }
        var env = ProcessInfo.processInfo.environment
        if let mousd = found.mousd {
            env["MOUSD_BIN"] = mousd
        }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let stdout = LockedData()
        let stderr = LockedData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdout.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderr.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return MouResult(status: process.terminationStatus, stdout: stdout.get(), stderr: stderr.get())
    }

    private static func executablePair(mou: URL, mousd: URL) -> (String, String?)? {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: mou.path) else { return nil }
        let daemon = fm.isExecutableFile(atPath: mousd.path) ? mousd.path : nil
        return (mou.path, daemon)
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }
    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public actor APIClient {
    /// Kept so older loopback checks still have a pinned fallback URL.
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8000")!

    private let runner: MouRunner
    private let decoder: JSONDecoder

    public init(runner: MouRunner? = nil) {
        if let runner {
            self.runner = runner
        } else {
            self.runner = { args in try MouLaunch.run(args) }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    public func currencies() async throws -> [Currency] {
        let rows: [CurrencyDTO] = try decode(try await invoke(["cur", "--all", "--json"]))
        return rows.map(\.domain)
    }

    public func createCurrency(symbol: String, name: String, isDefault: Bool) async throws -> Currency {
        var args = ["cur", "new", symbol, "--name", name]
        if isDefault { args.append("--default") }
        args.append("--json")
        let dto: CurrencyDTO = try decode(try await invoke(args))
        return dto.domain
    }

    public func setDefaultCurrency(symbol: String) async throws -> Currency {
        let dto: CurrencyDTO = try decode(
            try await invoke(["cur", "--set-default", symbol, "--json"])
        )
        return dto.domain
    }

    public func transactions(from: CivilDate, to: CivilDate) async throws -> [Transaction] {
        let rows: [TransactionDTO] = try decode(
            try await invoke([
                "--all",
                "--since", from.isoDay,
                "--until", to.isoDay,
                "--json",
            ])
        )
        return try rows.map { try $0.domain() }
    }

    public func createTransaction(
        description: String,
        value: Double,
        currency: String,
        occurredOn: CivilDate
    ) async throws -> Transaction {
        guard value.isFinite, value != 0 else { throw APIError.undecodable }
        let dto: TransactionDTO = try decode(
            try await invoke([
                "new", amountString(value),
                "--name", description,
                "--curr", currency,
                "--date", occurredOn.isoDay,
                "--json",
            ])
        )
        return try dto.domain()
    }

    private func invoke(_ args: [String]) async throws -> Data {
        let result: MouResult
        do {
            result = try runner(args)
        } catch {
            throw APIError.transport
        }
        if result.status == 0 {
            return result.stdout
        }
        let err = String(data: result.stderr, encoding: .utf8) ?? ""
        let lower = err.lowercased()
        if lower.contains("cannot talk to daemon")
            || lower.contains("failed to spawn")
            || lower.contains("no such file or directory")
        {
            throw APIError.transport
        }
        throw APIError.server(
            status: 422,
            code: "error",
            detail: err.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.undecodable
        }
    }

    /// Locale-independent. `String(Double)` does not use the user's decimal comma.
    private func amountString(_ value: Double) -> String {
        String(value)
    }
}
