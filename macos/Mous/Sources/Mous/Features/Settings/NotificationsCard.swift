import MousCore
import Observation
import SwiftUI

@Observable
@MainActor
final class ReportNoticeChrome {
    var items: [ReportInboxItem]
    var selectedID: String?

    init(items: [ReportInboxItem] = ReportInboxFile.load()) {
        self.items = items
    }

    var unreadCount: Int { items.filter { !$0.read }.count }

    var selectedItem: ReportInboxItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    func ingest(_ file: SummaryReportFile, unread: Bool) {
        let next = ReportInboxFile.ingesting(file, unread: unread, into: items)
        guard next != items else { return }
        items = next
        ReportInboxFile.save(items)
    }

    func seedIfEmpty(_ file: SummaryReportFile) {
        guard items.isEmpty else { return }
        ingest(file, unread: false)
    }

    func open(_ item: ReportInboxItem) {
        markRead(item.id)
        selectedID = item.id
    }

    func selectLatestUnread() {
        let target = items.first { !$0.read } ?? items.first
        guard let target else { return }
        open(target)
    }

    func selectFromAlert(capturedAt: TimeInterval?) {
        if let capturedAt {
            let target = items.first {
                abs($0.capturedAt.timeIntervalSince1970 - capturedAt) < 0.05
            }
            if let target {
                open(target)
                return
            }
        }
        selectLatestUnread()
    }

    @discardableResult
    func popSelection() -> Bool {
        guard selectedID != nil else { return false }
        selectedID = nil
        return true
    }

    func closeInbox() {
        selectedID = nil
    }

    private func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].read else { return }
        items[index].read = true
        ReportInboxFile.save(items)
    }
}

struct NotificationsCard: View {
    @Bindable var notice: ReportNoticeChrome
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mousAccent) private var mousAccent
    @State private var listHeight: CGFloat = 0

    var body: some View {
        Group {
            if let item = notice.selectedItem {
                detail(item)
            } else {
                inbox
            }
        }
        .padding(20)
        .frame(width: MousPopup.cardWidth, alignment: .topLeading)
        .mousCard()
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: notice.selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.selectedItem == nil ? "Notifications" : "Report")
        .accessibilityHint("Escape or Done returns to the dashboard.")
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(title: "Notifications", back: nil)
            if notice.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    empty
                    previewRow
                }
            } else {
                ScrollView(.vertical) {
                    rows
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: InboxHeightKey.self, value: proxy.size.height)
                            }
                        }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(listHeight, 44), 360), alignment: .top)
                .onPreferenceChange(InboxHeightKey.self) { listHeight = $0 }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(notice.items) { item in
                row(item)
            }
        }
    }

    private func displayedFigures(for item: ReportInboxItem) -> SummaryReportFigures? {
        let display = MousCurrencyPref.isoCode(for: MousConfigFile.load().currency)
        return SummaryReportFigures.parse(item.stdout)?.displayed(in: display)
    }

    private func detail(_ item: ReportInboxItem) -> some View {
        let figures = displayedFigures(for: item)
        return VStack(alignment: .leading, spacing: 20) {
            header(title: SummaryReportCopy.inboxTitle(period: item.period), back: { notice.popSelection() })
            VStack(alignment: .leading, spacing: 4) {
                Text(SummaryReportCopy.inboxTitle(period: item.period))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detailRange(item, figures: figures))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let figures {
                HStack(alignment: .top, spacing: 8) {
                    stat("Out", figures.formatMoney(figures.expense), emphasize: .primary)
                    stat("In", figures.formatMoney(figures.income), emphasize: .positive)
                    stat(
                        "Saved",
                        figures.formatSavedPercent(),
                        emphasize: figures.savedRatio >= 0 ? .positive : .primary
                    )
                }
                Text(detailCaption(figures))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let runway = figures.runway {
                    quietLine("Runway \(figures.formatRunway(runway))")
                }
                if let next = figures.nextMonth {
                    quietLine("Next month \(figures.formatMoney(next))")
                }
            } else {
                Text("No figures in this report.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(detailAccessibility(item, figures: figures))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No reports yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(emptyCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(trackFill)
    }

    private var previewRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Color.clear
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(SummaryReportCopy.inboxTitle(period: configuredPeriod))
                    .font(.callout.weight(.regular))
                    .foregroundStyle(.primary)
                Text("Out \(ghostMoney(1240))  ·  Saved 25%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Preview")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(trackFill)
        .opacity(0.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(_ item: ReportInboxItem) -> some View {
        let figures = displayedFigures(for: item)
        return Button {
            notice.open(item)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.primary)
                    .frame(width: item.read ? 0 : 8, height: 8)
                    .opacity(item.read ? 0 : 1)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18),
                        value: item.read
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(SummaryReportCopy.inboxTitle(period: item.period))
                        .font(.callout.weight(item.read ? .regular : .semibold))
                        .foregroundStyle(.primary)
                    if let figures {
                        Text(rowCaption(figures))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(capturedLabel(item.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(trackFill)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open this report")
        .accessibilityLabel(rowAccessibility(item, figures: figures))
        .accessibilityHint("Shows the report.")
    }

    private func header(title: String, back: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let back {
                Button("Back", action: back)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .help("Back to notifications")
            } else {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 12)
            Button("Done", action: onClose)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .help("Close notifications")
        }
    }

    private func stat(_ label: String, _ value: String, emphasize: StatTone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(emphasize == .positive ? AnyShapeStyle(mousAccent) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(trackFill)
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var trackFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.055))
    }

    private func rowCaption(_ figures: SummaryReportFigures) -> String {
        "Out \(figures.formatMoney(figures.expense))  ·  Saved \(figures.formatSavedPercent())"
    }

    private func detailCaption(_ figures: SummaryReportFigures) -> String {
        let n = figures.count == 1 ? "1 transaction" : "\(figures.count) transactions"
        if figures.top.isEmpty { return n }
        return "\(n)  ·  \(figures.top.joined(separator: ", "))"
    }

    private func detailRange(_ item: ReportInboxItem, figures: SummaryReportFigures?) -> String {
        if let range = figures?.range, !range.isEmpty { return range }
        return capturedLabel(item.capturedAt)
    }

    private func capturedLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var configuredPeriod: String {
        MousConfigFile.ensure().reportPeriod
    }

    private var emptyCaption: String {
        let period = configuredPeriod.split { $0.isWhitespace }.joined(separator: " ")
        switch ReportCadence.classify(period) {
        case .week:
            return "Your first week report lands when the week closes."
        case .twoWeeks:
            return "Your first 2 week report lands when the period closes."
        case .month:
            return "Your first month report lands when the month closes."
        case .custom:
            guard ReportCadence.isValidPeriod(period) else {
                return "They land here when a period closes."
            }
            return "Your first \(period) report lands when the period closes."
        }
    }

    private func ghostMoney(_ value: Double) -> String {
        let code = MousCurrencyPref.isoCode(for: MousConfigFile.load().currency)
        return value.formatted(
            FloatingPointFormatStyle<Double>.Currency(code: code)
                .precision(.fractionLength(2))
        )
    }

    private func rowAccessibility(_ item: ReportInboxItem, figures: SummaryReportFigures?) -> String {
        var parts = [SummaryReportCopy.inboxTitle(period: item.period)]
        if !item.read { parts.append("unread") }
        parts.append(capturedLabel(item.capturedAt))
        if let figures { parts.append(rowCaption(figures)) }
        return parts.joined(separator: ", ")
    }

    private func detailAccessibility(_ item: ReportInboxItem, figures: SummaryReportFigures?) -> String {
        var parts = [SummaryReportCopy.inboxTitle(period: item.period)]
        if let figures {
            if !figures.range.isEmpty { parts.append(figures.range) }
            parts.append("out \(figures.formatMoney(figures.expense))")
            parts.append("in \(figures.formatMoney(figures.income))")
            parts.append("saved \(figures.formatSavedPercent())")
            parts.append(detailCaption(figures))
        }
        return parts.joined(separator: ", ")
    }

    private enum StatTone {
        case primary
        case positive
    }
}

private struct InboxHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
