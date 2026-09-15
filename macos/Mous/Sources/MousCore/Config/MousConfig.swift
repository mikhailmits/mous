import Foundation

/// Public `config.json` keys. Same file Python reads from Application Support.
public struct MousConfig: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var databasePath: String
    public var dev: Bool
    public var reportPeriod: String
    public var theme: String
    public var currency: String
    public var notifyInApp: Bool
    public var notifyMacOS: Bool

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case databasePath = "database_path"
        case dev
        case reportPeriod = "report_period"
        case theme
        case currency
        case notifyInApp = "notify_in_app"
        case notifyMacOS = "notify_macos"
    }

    public init(
        host: String,
        port: Int,
        databasePath: String,
        dev: Bool,
        reportPeriod: String,
        theme: String,
        currency: String,
        notifyInApp: Bool = true,
        notifyMacOS: Bool = true
    ) {
        self.host = host
        self.port = port
        self.databasePath = databasePath
        self.dev = dev
        self.reportPeriod = reportPeriod
        self.theme = theme
        self.currency = currency
        self.notifyInApp = notifyInApp
        self.notifyMacOS = notifyMacOS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8000
        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath) ?? ""
        dev = try container.decodeIfPresent(Bool.self, forKey: .dev) ?? false
        reportPeriod = try container.decodeIfPresent(String.self, forKey: .reportPeriod) ?? "14 days"
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "eur"
        notifyInApp = try container.decodeIfPresent(Bool.self, forKey: .notifyInApp) ?? true
        notifyMacOS = try container.decodeIfPresent(Bool.self, forKey: .notifyMacOS) ?? true
    }
}

public enum MousTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum MousCurrencyPref: String, CaseIterable, Identifiable, Sendable {
    case eur
    case usd
    case uah

    public var id: String { rawValue }

    public var label: String { rawValue.uppercased() }

    /// ISO 4217 code for formatters. Amounts are not converted.
    public var isoCode: String { rawValue.uppercased() }

    /// Name sent to `POST /currencies` when the row is missing.
    public var englishName: String {
        switch self {
        case .eur: return "Euro"
        case .usd: return "US Dollar"
        case .uah: return "Hryvnia"
        }
    }

    public static func isoCode(for stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (MousCurrencyPref(rawValue: trimmed) ?? .eur).isoCode
    }

    public static func pref(for stored: String) -> MousCurrencyPref {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return MousCurrencyPref(rawValue: trimmed) ?? .eur
    }
}

/// How often / how far back `mous summary` looks. Maps to `report_period`.
public enum ReportCadence: String, CaseIterable, Identifiable, Sendable {
    case week
    case twoWeeks
    case month
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .week: return "Week"
        case .twoWeeks: return "2 weeks"
        case .month: return "Month"
        case .custom: return "Custom"
        }
    }

    /// Value written to `report_period`. `nil` for custom — keep the typed string.
    public var storedValue: String? {
        switch self {
        case .week: return "week"
        case .twoWeeks: return "2 weeks"
        case .month: return "month"
        case .custom: return nil
        }
    }

    public static func classify(_ period: String) -> ReportCadence {
        let folded = period.lowercased().filter { !$0.isWhitespace }
        switch folded {
        case "week", "1week", "1weeks", "7day", "7days", "w", "1w":
            return .week
        case "2weeks", "2week", "14days", "14day", "2w":
            return .twoWeeks
        case "month", "1month", "1months":
            return .month
        default:
            return .custom
        }
    }

    /// Same grammar as Python `parse_period`: `14 days`, `week`, `2 weeks`, `month`.
    public static func isValidPeriod(_ text: String) -> Bool {
        let raw = text.split { $0.isWhitespace }.joined(separator: " ")
        guard !raw.isEmpty else { return false }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = periodRegex.firstMatch(in: raw, range: range),
              match.range.length == (raw as NSString).length
        else { return false }
        let countRange = match.range(at: 1)
        if countRange.location != NSNotFound {
            let countText = (raw as NSString).substring(with: countRange)
            if let count = Int(countText), count < 1 { return false }
        }
        return true
    }

    private static let periodRegex = try! NSRegularExpression(
        pattern: "^(?:(\\d+)\\s*)?(days?|weeks?|months?|years?|[dwy])$",
        options: .caseInsensitive
    )
}

/// Read and write Application Support `mous/config.json` (or `MOUS_CONFIG_DIR`).
public enum MousConfigFile {
    /// Tests replace this. `MOUS_CONFIG_DIR` also wins over Application Support.
    nonisolated(unsafe) public static var directoryOverride: URL?

    public static func directory() -> URL {
        if let directoryOverride { return directoryOverride }
        if let override = ProcessInfo.processInfo.environment["MOUS_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("mous", isDirectory: true)
    }

    public static func configURL() -> URL {
        directory().appendingPathComponent("config.json")
    }

    public static func summaryReportURL() -> URL {
        directory().appendingPathComponent("summary_report.json")
    }

    public static func reportInboxURL() -> URL {
        directory().appendingPathComponent("report_inbox.json")
    }

    public static func defaults(in directory: URL? = nil) -> MousConfig {
        let dir = directory ?? Self.directory()
        return MousConfig(
            host: "127.0.0.1",
            port: 8000,
            databasePath: dir.appendingPathComponent("data.db").path,
            dev: false,
            reportPeriod: "14 days",
            theme: "system",
            currency: "eur"
        )
    }

    public static func load() -> MousConfig {
        let url = configURL()
        guard let data = try? Data(contentsOf: url) else {
            return defaults().normalized()
        }
        let decoder = JSONDecoder()
        guard var cfg = try? decoder.decode(MousConfig.self, from: data) else {
            return defaults().normalized()
        }
        if cfg.databasePath.isEmpty {
            cfg.databasePath = defaults().databasePath
        }
        return cfg.normalized()
    }

    @discardableResult
    public static func ensure() -> MousConfig {
        let url = configURL()
        let fm = FileManager.default
        try? fm.createDirectory(at: directory(), withIntermediateDirectories: true)
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let cfg = defaults()
            save(cfg)
            return cfg
        }
        let cfg = load()
        let required = [
            "host", "port", "database_path", "dev", "report_period", "theme", "currency",
            "notify_in_app", "notify_macos",
        ]
        if required.contains(where: { obj[$0] == nil }) {
            save(cfg)
        }
        return cfg
    }

    public static func save(_ config: MousConfig) {
        let url = configURL()
        try? FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var cfg = config
        cfg.host = cfg.host.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.databasePath = cfg.databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.reportPeriod = cfg.reportPeriod.split { $0.isWhitespace }.joined(separator: " ")
        cfg.theme = cfg.theme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if MousTheme(rawValue: cfg.theme) == nil { cfg.theme = "system" }
        cfg.currency = cfg.currency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cfg.currency.isEmpty { cfg.currency = "eur" }
        if !(1...65535).contains(cfg.port) {
            cfg.port = min(max(cfg.port, 1), 65535)
        }
        guard var data = try? encoder.encode(cfg) else { return }
        data.append(contentsOf: [0x0A])
        try? data.write(to: url, options: .atomic)
    }
}

private extension MousConfig {
    func normalized() -> MousConfig {
        var cfg = self
        let host = cfg.host.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.host = host.isEmpty ? "127.0.0.1" : host
        let period = cfg.reportPeriod.split { $0.isWhitespace }.joined(separator: " ")
        cfg.reportPeriod = period.isEmpty ? "14 days" : period
        let theme = cfg.theme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cfg.theme = MousTheme(rawValue: theme)?.rawValue ?? "system"
        let currency = cfg.currency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cfg.currency = currency.isEmpty ? "eur" : currency
        let path = cfg.databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { cfg.databasePath = path }
        return cfg
    }
}
