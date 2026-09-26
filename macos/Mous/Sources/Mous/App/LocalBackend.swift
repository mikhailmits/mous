import Foundation
import MousCore

/// Warms `mousd` by running `mou` once. The CLI auto-spawns the daemon, so the
/// app does not keep a server process of its own.
@MainActor
final class LocalBackend {
    static let shared = LocalBackend()

    private var startTask: Task<Void, Never>?

    private init() {}

    var isBundled: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    /// Spawn the daemon immediately so boot overlaps window setup.
    func kickoff() {
        if isBundled {
            MousConfigFile.ensure()
            Self.installCommandLineTool()
        }
        if startTask == nil {
            startTask = Task.detached(priority: .userInitiated) {
                _ = try? MouLaunch.run(["cur", "--all", "--json"])
            }
        }
    }

    func start() async {
        kickoff()
        await startTask?.value
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        // Drop the shared daemon so the next launch opens the current database_path.
        _ = try? MouLaunch.run(["--shutdown"])
    }

    /// `~/.local/bin/mou` → bundled binary. No admin; PATH must include ~/.local/bin.
    private static func installCommandLineTool() {
        let fm = FileManager.default
        guard let exe = Bundle.main.executableURL else { return }
        let dir = exe.deletingLastPathComponent()
        let binDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true)
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        for name in ["mou", "mousd"] {
            let source = dir.appendingPathComponent(name)
            guard fm.isExecutableFile(atPath: source.path) else { continue }
            let link = binDir.appendingPathComponent(name)
            if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                if existing == source.path { continue }
                try? fm.removeItem(at: link)
            } else if fm.fileExists(atPath: link.path) {
                continue
            }
            try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: source.path)
        }
    }
}
