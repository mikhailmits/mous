import Foundation

/// Public `config.json` keys. Same file Python reads from Application Support.
public struct MousConfig: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var databasePath: String
    public var dev: Bool
    public var theme: String
    public var currency: String
    public var hideBalance: Bool
    public var hideBalanceStyle: String

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case databasePath = "database_path"
        case dev
        case theme
        case currency
        case hideBalance = "hide_balance"
        case hideBalanceStyle = "hide_balance_style"
    }

    public init(
        host: String,
        port: Int,
        databasePath: String,
        dev: Bool,
        theme: String,
        currency: String,
        hideBalance: Bool = false,
        hideBalanceStyle: String = "scramble"
    ) {
        self.host = host
        self.port = port
        self.databasePath = databasePath
        self.dev = dev
        self.theme = theme
        self.currency = currency
        self.hideBalance = hideBalance
        self.hideBalanceStyle = hideBalanceStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8000
        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath) ?? ""
        dev = try container.decodeIfPresent(Bool.self, forKey: .dev) ?? false
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? MousTheme.lime.rawValue
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "eur"
        hideBalance = try container.decodeIfPresent(Bool.self, forKey: .hideBalance) ?? false
        hideBalanceStyle = try container.decodeIfPresent(String.self, forKey: .hideBalanceStyle) ?? "scramble"
    }
}

/// One mark per theme in `macos/Mous/Icon`. White is the light card;
/// the others are dark, and quieter than Leaf.
public enum MousTheme: String, CaseIterable, Identifiable, Sendable {
    case leaf
    case pale
    case lime
    case mint
    case sea
    case clay
    case white

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .leaf: return "Leaf"
        case .pale: return "Pale"
        case .lime: return "Lime"
        case .mint: return "Mint"
        case .sea: return "Sea"
        case .clay: return "Clay"
        case .white: return "White"
        }
    }

    /// Raw transparent mark in slider order, matching the icon files.
    public var iconFile: String {
        switch self {
        case .leaf: return "logo-variant"
        case .pale: return "logo-variant-1"
        case .lime: return "logo-variant-2"
        case .mint: return "logo-variant-3"
        case .sea: return "logo-variant-4"
        case .clay: return "logo-variant-5"
        case .white: return "logo-variant-6"
        }
    }

    /// Sampled from the mark PNG. Leaf is the loudest dark accent;
    /// the others stay softer against near-black cards.
    public var markRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .leaf: return (118.0 / 255, 178.0 / 255, 72.0 / 255)
        case .pale: return (156.0 / 255, 160.0 / 255, 148.0 / 255)
        case .lime: return (112.0 / 255, 168.0 / 255, 78.0 / 255)
        case .mint: return (128.0 / 255, 168.0 / 255, 156.0 / 255)
        case .sea: return (112.0 / 255, 156.0 / 255, 164.0 / 255)
        case .clay: return (176.0 / 255, 140.0 / 255, 128.0 / 255)
        case .white: return (72.0 / 255, 74.0 / 255, 78.0 / 255)
        }
    }

    /// Quiet near-black card fills (screenshot charcoal ~32), each with a
    /// faint theme hue. White stays warm paper.
    public var canvasRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .leaf: return (30.0 / 255, 34.0 / 255, 28.0 / 255)
        case .pale: return (34.0 / 255, 34.0 / 255, 32.0 / 255)
        case .lime: return (32.0 / 255, 32.0 / 255, 30.0 / 255)
        case .mint: return (30.0 / 255, 34.0 / 255, 33.0 / 255)
        case .sea: return (28.0 / 255, 32.0 / 255, 34.0 / 255)
        case .clay: return (34.0 / 255, 30.0 / 255, 28.0 / 255)
        case .white: return (247.0 / 255, 245.0 / 255, 241.0 / 255)
        }
    }

    public static func parse(_ stored: String) -> MousTheme {
        switch stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "leaf", "logo-variant": return .leaf
        case "pale", "logo-variant-1": return .pale
        case "lime", "logo-variant-2", "system", "light", "dark": return .lime
        case "mint", "logo-variant-3": return .mint
        case "sea", "logo-variant-4": return .sea
        case "clay", "logo-variant-5": return .clay
        case "white", "logo-variant-6": return .white
        default: return .lime
        }
    }
}

public enum MousCurrencyPref: String, CaseIterable, Identifiable, Sendable {
    case eur
    case usd
    case uah

    public var id: String { rawValue }

    public var label: String { rawValue.uppercased() }

    /// Tiny mark for Settings chips. Not used for FX.
    public var glyph: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .uah: return "₴"
        }
    }

    /// ISO 4217 code for formatters. Amounts convert through `MoneyDisplay`.
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

/// How hidden amounts render. Default scramble keeps existing `?#*!` glyphs.
public enum HideBalanceStyle: String, CaseIterable, Identifiable, Sendable {
    case scramble
    case veil

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .scramble: return "Scramble"
        case .veil: return "Dots"
        }
    }

    public static func parse(_ stored: String) -> HideBalanceStyle {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return HideBalanceStyle(rawValue: trimmed) ?? .scramble
    }
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

    public static func defaults(in directory: URL? = nil) -> MousConfig {
        let dir = directory ?? Self.directory()
        return MousConfig(
            host: "127.0.0.1",
            port: 8000,
            databasePath: dir.appendingPathComponent("data.db").path,
            dev: false,
            theme: MousTheme.lime.rawValue,
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
            "host", "port", "database_path", "dev", "theme", "currency",
            "hide_balance", "hide_balance_style",
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
        cfg.theme = MousTheme.parse(cfg.theme).rawValue
        cfg.currency = cfg.currency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cfg.currency.isEmpty { cfg.currency = "eur" }
        cfg.hideBalanceStyle = HideBalanceStyle.parse(cfg.hideBalanceStyle).rawValue
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
        cfg.theme = MousTheme.parse(cfg.theme).rawValue
        let currency = cfg.currency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cfg.currency = currency.isEmpty ? "eur" : currency
        cfg.hideBalanceStyle = HideBalanceStyle.parse(cfg.hideBalanceStyle).rawValue
        let path = cfg.databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { cfg.databasePath = path }
        return cfg
    }
}
