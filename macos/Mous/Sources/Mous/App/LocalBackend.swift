import Foundation
import MousCore

/// Starts the bundled `mous-api` helper when this binary lives inside Mous.app.
/// `swift run` / `mous dev` skip this and talk to whatever is already on :8000.
@MainActor
final class LocalBackend {
    static let shared = LocalBackend()

    private var process: Process?
    private var stdout: FileHandle?
    private var stderr: FileHandle?

    private init() {}

    var isBundled: Bool { Self.apiBinaryURL() != nil }

    func start() async {
        if await Self.healthOK() { return }
        guard let binary = Self.apiBinaryURL() else { return }
        spawn(binary)
        for attempt in 1...12 {
            if await Self.healthOK() { return }
            do {
                try await ConnectRetry.sleep(attempt: min(attempt, 5))
            } catch {
                return
            }
        }
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil
        try? stdout?.close()
        try? stderr?.close()
        stdout = nil
        stderr = nil
    }

    private func spawn(_ binary: URL) {
        let support = Self.supportDirectory()
        let logs = support.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let outURL = logs.appendingPathComponent("api.log")
        let errURL = logs.appendingPathComponent("api.err.log")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let stdout = try? FileHandle(forWritingTo: outURL)
        let stderr = try? FileHandle(forWritingTo: errURL)
        stdout?.seekToEndOfFile()
        stderr?.seekToEndOfFile()

        let process = Process()
        process.executableURL = binary
        process.environment = Self.childEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                if self?.process === process {
                    self?.process = nil
                }
            }
        }
        do {
            try process.run()
            self.process = process
            self.stdout = stdout
            self.stderr = stderr
        } catch {
            try? stdout?.close()
            try? stderr?.close()
        }
    }

    private static func apiBinaryURL() -> URL? {
        let bundle = Bundle.main
        guard bundle.bundlePath.hasSuffix(".app") else { return nil }
        let url = bundle.bundleURL
            .appendingPathComponent("Contents/MacOS/mous-api", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("mous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let support = supportDirectory()
        let db = support.appendingPathComponent("data.db")
        env["MOUS_DATABASE_URL"] = "sqlite:///\(db.path)"
        env["MOUS_API_HOST"] = "127.0.0.1"
        env["MOUS_API_PORT"] = "8000"
        if let resources = Bundle.main.resourceURL {
            env["MOUS_PROJECT_ROOT"] = resources.path
        }
        return env
    }

    private static func healthOK() async -> Bool {
        let url = URL(string: "http://127.0.0.1:8000/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.httpShouldHandleCookies = false
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
