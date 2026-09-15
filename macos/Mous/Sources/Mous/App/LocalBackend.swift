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
    private var startTask: Task<Void, Never>?

    private init() {}

    var isBundled: Bool { Self.apiBinaryURL() != nil }

    /// Spawn the helper immediately so boot overlaps window setup.
    func kickoff() {
        guard isBundled else { return }
        MousConfigFile.ensure()
        Self.installCommandLineTool()
        if startTask == nil {
            startTask = Task { await self.runStart() }
        }
    }

    func start() async {
        kickoff()
        await startTask?.value
    }

    private func runStart() async {
        if await Self.healthOK() { return }
        guard let binary = Self.apiBinaryURL() else { return }
        if process?.isRunning != true {
            spawn(binary)
        }
        for attempt in 1...ConnectRetry.bootAttempts {
            if Task.isCancelled { return }
            if await Self.healthOK() { return }
            do {
                try await ConnectRetry.sleepForBoot(attempt: attempt)
            } catch {
                return
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
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
        process.currentDirectoryURL = binary.deletingLastPathComponent()
        process.environment = Self.childEnvironment()
        process.standardInput = FileHandle.nullDevice
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
        let macos = bundle.bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let onedir = macos.appendingPathComponent("mous-api/mous-api", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: onedir.path) {
            return onedir
        }
        let onefile = macos.appendingPathComponent("mous-api", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: onefile.path) ? onefile : nil
    }

    private static func supportDirectory() -> URL {
        let dir = MousConfigFile.directory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let support = supportDirectory()
        env["MOUS_CONFIG_DIR"] = support.path
        if let resources = Bundle.main.resourceURL {
            env["MOUS_PROJECT_ROOT"] = resources.path
        }
        return env
    }

    /// `~/.local/bin/mous` → bundled helper. No admin; PATH must include ~/.local/bin.
    private static func installCommandLineTool() {
        guard let binary = apiBinaryURL() else { return }
        let fm = FileManager.default
        let binDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true)
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let link = binDir.appendingPathComponent("mous")
        let dest = binary.path
        if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if existing == dest { return }
            try? fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path) {
            return
        }
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: dest)
    }

    private static let healthSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.2
        config.timeoutIntervalForResource = 0.2
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func apiBaseURL() -> URL {
        let cfg = MousConfigFile.load()
        return URL(string: "http://\(cfg.host):\(cfg.port)") ?? APIClient.defaultBaseURL
    }

    private static func healthOK() async -> Bool {
        let url = apiBaseURL().appendingPathComponent("health")
        var request = URLRequest(url: url, timeoutInterval: 0.2)
        request.httpShouldHandleCookies = false
        do {
            let (_, response) = try await healthSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
