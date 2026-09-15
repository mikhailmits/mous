import Foundation

/// On-disk `summary_report.json` written by the API scheduler.
public struct SummaryReportFile: Equatable, Sendable {
    public var capturedAt: Date
    public var period: String
    public var stdout: String

    public init(capturedAt: Date, period: String, stdout: String = "") {
        self.capturedAt = capturedAt
        self.period = period
        self.stdout = stdout
    }

    public static func load(from url: URL = MousConfigFile.summaryReportURL()) -> SummaryReportFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    public static func decode(_ data: Data) -> SummaryReportFile? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let capturedAt = SummaryReportTime.parse(payload.capturedAt)
        else { return nil }
        let period = payload.period?.split { $0.isWhitespace }.joined(separator: " ") ?? ""
        return SummaryReportFile(
            capturedAt: capturedAt,
            period: period,
            stdout: payload.stdout ?? ""
        )
    }

    private struct Payload: Decodable {
        var capturedAt: String
        var period: String?
        var stdout: String?

        enum CodingKeys: String, CodingKey {
            case capturedAt = "captured_at"
            case period
            case stdout
        }
    }
}

public enum SummaryReportTime {
    public static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = fractional.date(from: text) { return date }
        if let date = plain.date(from: text) { return date }
        let zulu = text.replacingOccurrences(of: "+00:00", with: "Z")
        if zulu != text {
            if let date = fractional.date(from: zulu) { return date }
            if let date = plain.date(from: zulu) { return date }
        }
        return nil
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public enum SummaryReportCopy {
    /// Banner / notification body: "Your 2 week report is ready".
    public static func readyMessage(period: String) -> String {
        let trimmed = period.split { $0.isWhitespace }.joined(separator: " ")
        switch ReportCadence.classify(trimmed) {
        case .week:
            return "Your week report is ready"
        case .twoWeeks:
            return "Your 2 week report is ready"
        case .month:
            return "Your month report is ready"
        case .custom:
            if trimmed.isEmpty { return "Your report is ready" }
            return "Your \(trimmed) report is ready"
        }
    }

    /// Inbox row / detail title: "2 week report".
    public static func inboxTitle(period: String) -> String {
        let trimmed = period.split { $0.isWhitespace }.joined(separator: " ")
        switch ReportCadence.classify(trimmed) {
        case .week:
            return "Week report"
        case .twoWeeks:
            return "2 week report"
        case .month:
            return "Month report"
        case .custom:
            if trimmed.isEmpty { return "Report" }
            return "\(trimmed) report"
        }
    }
}

public enum SummaryReportDecision: Equatable {
    /// Same stamp as last time, or nothing on disk.
    case ignore
    /// First time we see a file — keep the stamp, do not notify (boot capture).
    case remember
    /// `captured_at` moved forward; tell the user.
    case notify(SummaryReportFile)
}

/// Decides whether a loaded report should notify. Persist `lastSeen` yourself.
public struct SummaryReportGate: Equatable, Sendable {
    public var lastSeen: Date?

    public init(lastSeen: Date? = nil) {
        self.lastSeen = lastSeen
    }

    public mutating func consider(_ file: SummaryReportFile?) -> SummaryReportDecision {
        guard let file else { return .ignore }
        guard let lastSeen else {
            self.lastSeen = file.capturedAt
            return .remember
        }
        if file.capturedAt.timeIntervalSince(lastSeen) <= 0.05 {
            return .ignore
        }
        self.lastSeen = file.capturedAt
        return .notify(file)
    }
}

/// Figures parsed from `mous summary` stdout.
public struct SummaryReportFigures: Equatable, Sendable {
    public var range: String
    public var currency: String
    public var count: Int
    public var income: Double
    public var expense: Double
    public var saved: Double
    public var top: [String]
    public var runway: Double?
    public var nextMonth: Double?

    public init(
        range: String,
        currency: String,
        count: Int,
        income: Double,
        expense: Double,
        saved: Double,
        top: [String],
        runway: Double?,
        nextMonth: Double?
    ) {
        self.range = range
        self.currency = currency
        self.count = count
        self.income = income
        self.expense = expense
        self.saved = saved
        self.top = top
        self.runway = runway
        self.nextMonth = nextMonth
    }

    public static func parse(_ stdout: String) -> SummaryReportFigures? {
        let lines = stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.first == "summary" else { return nil }
        var range = ""
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { fields[key] = value }
            } else if range.isEmpty {
                range = line
            }
        }
        guard let currency = fields["currency"], !currency.isEmpty else { return nil }
        guard let count = intValue(fields["n"]) else { return nil }
        guard let income = moneyValue(fields["in"]) else { return nil }
        guard let expense = moneyValue(fields["out"]) else { return nil }
        guard let saved = moneyValue(fields["saved"]) else { return nil }
        return SummaryReportFigures(
            range: range,
            currency: currency,
            count: count,
            income: income,
            expense: expense,
            saved: saved,
            top: listValue(fields["top"]),
            runway: optionalMoney(fields["runway"]),
            nextMonth: moneyValue(fields["next_month_spent_predictions"])
        )
    }

    public func formatMoney(_ value: Double) -> String {
        if let code = Self.isoCurrencyCode(currency) {
            return value.formatted(
                FloatingPointFormatStyle<Double>.Currency(code: code)
                    .precision(.fractionLength(2))
            )
        }
        let amount = value.formatted(.number.precision(.fractionLength(2)))
        return currency.isEmpty ? amount : "\(amount) \(currency)"
    }

    private static func isoCurrencyCode(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "eur", "€", "euro": return "EUR"
        case "usd", "$", "dollar": return "USD"
        case "uah", "₴", "hryvnia": return "UAH"
        case "gbp", "£", "pound": return "GBP"
        default:
            let letters = raw.filter(\.isLetter)
            if letters.count == 3 { return letters.uppercased() }
            return nil
        }
    }

    private static func intValue(_ raw: String?) -> Int? {
        guard let token = raw?.split(whereSeparator: \.isWhitespace).first else { return nil }
        return Int(token)
    }

    private static func moneyValue(_ raw: String?) -> Double? {
        guard let token = raw?.split(whereSeparator: \.isWhitespace).first else { return nil }
        return Double(token)
    }

    private static func optionalMoney(_ raw: String?) -> Double? {
        guard let raw, raw != "..." else { return nil }
        return moneyValue(raw)
    }

    private static func listValue(_ raw: String?) -> [String] {
        guard var text = raw else { return [] }
        if text.hasPrefix("[") { text.removeFirst() }
        if text.hasSuffix("]") { text.removeLast() }
        return text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// One row in Options → Notifications. Newest first on disk.
public struct ReportInboxItem: Identifiable, Equatable, Codable, Sendable {
    public var capturedAt: Date
    public var period: String
    public var stdout: String
    public var read: Bool

    public var id: String {
        String(format: "%.3f", capturedAt.timeIntervalSince1970)
    }

    public init(capturedAt: Date, period: String, stdout: String, read: Bool) {
        self.capturedAt = capturedAt
        self.period = period
        self.stdout = stdout
        self.read = read
    }

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case period
        case stdout
        case read
    }
}

public enum ReportInboxFile {
    public static let maxItems = 24

    public static func load(from url: URL = MousConfigFile.reportInboxURL()) -> [ReportInboxItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    public static func decode(_ data: Data) -> [ReportInboxItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let payload = try? decoder.decode(Payload.self, from: data) {
            return payload.items
        }
        return []
    }

    public static func save(_ items: [ReportInboxItem], to url: URL = MousConfigFile.reportInboxURL()) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard var data = try? encoder.encode(Payload(items: items)) else { return }
        data.append(contentsOf: [0x0A])
        try? data.write(to: url, options: .atomic)
    }

    /// Newest first. Duplicate `captured_at` is ignored. Caps at `maxItems`.
    public static func ingesting(
        _ file: SummaryReportFile,
        unread: Bool,
        into items: [ReportInboxItem]
    ) -> [ReportInboxItem] {
        if items.contains(where: { abs($0.capturedAt.timeIntervalSince(file.capturedAt)) < 0.05 }) {
            return items
        }
        var next = items
        next.insert(
            ReportInboxItem(
                capturedAt: file.capturedAt,
                period: file.period,
                stdout: file.stdout,
                read: !unread
            ),
            at: 0
        )
        if next.count > maxItems {
            next = Array(next.prefix(maxItems))
        }
        return next
    }

    private struct Payload: Codable {
        var items: [ReportInboxItem]
    }
}
