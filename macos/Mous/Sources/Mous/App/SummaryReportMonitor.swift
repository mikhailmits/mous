import Darwin
import Foundation
import MousCore
@preconcurrency import UserNotifications

/// Watches Application Support `summary_report.json` and fans out to the in-app
/// inbox plus a macOS notification when `captured_at` moves forward.
@MainActor
final class SummaryReportMonitor: NSObject, UNUserNotificationCenterDelegate {
    private static let lastSeenKey = "mous.summary.lastSeenCapturedAt"
    private static let notificationID = "dev.mous.report.ready"

    private let notice: ReportNoticeChrome
    private let onReveal: () -> Void
    private let defaults: UserDefaults
    private var gate: SummaryReportGate
    private var source: DispatchSourceFileSystemObject?
    private var debounceGeneration = 0

    init(
        notice: ReportNoticeChrome,
        defaults: UserDefaults = .standard,
        onReveal: @escaping () -> Void
    ) {
        self.notice = notice
        self.defaults = defaults
        self.onReveal = onReveal
        let lastSeen = defaults.object(forKey: Self.lastSeenKey) as? Date
        self.gate = SummaryReportGate(lastSeen: lastSeen)
        super.init()
    }

    func start() {
        MousConfigFile.ensure()
        UNUserNotificationCenter.current().delegate = self
        applyCurrentFile()
        watchDirectory()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.onReveal()
        }
        completionHandler()
    }

    private func applyCurrentFile() {
        apply(SummaryReportFile.load())
    }

    private func apply(_ file: SummaryReportFile?) {
        let decision = gate.consider(file)
        persistLastSeen()
        if isDemoMode { return }
        switch decision {
        case .ignore:
            if let file { notice.seedIfEmpty(file) }
        case .remember:
            if let file { notice.ingest(file, unread: false) }
        case .notify(let report):
            notice.ingest(report, unread: true)
            postMacOS(
                message: SummaryReportCopy.readyMessage(period: report.period),
                report: report
            )
        }
    }

    private func persistLastSeen() {
        if let lastSeen = gate.lastSeen {
            defaults.set(lastSeen, forKey: Self.lastSeenKey)
        }
    }

    private var isDemoMode: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["MOUS_DEMO_TIP"] != nil || env["MOUS_DEMO_TYPE"] != nil
    }

    private func postMacOS(message: String, report: SummaryReportFile) {
        let content = UNMutableNotificationContent()
        content.title = "Mous"
        content.body = message
        content.sound = .default
        content.userInfo = [
            "captured_at": report.capturedAt.timeIntervalSince1970,
            "period": report.period,
        ]
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                    if ok { center.add(request) }
                }
            default:
                break
            }
        }
    }

    private func watchDirectory() {
        stop()
        let dir = MousConfigFile.directory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.noteDirectoryEvent()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    private func noteDirectoryEvent() {
        debounceGeneration += 1
        let generation = debounceGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, generation == self.debounceGeneration else { return }
            self.applyCurrentFile()
        }
    }
}
