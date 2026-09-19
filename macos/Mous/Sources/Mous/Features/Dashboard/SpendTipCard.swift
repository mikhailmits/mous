import Observation
import MousCore
import SwiftUI

enum SpendTipEdge: Equatable {
    case above
    case below
}

enum DashboardTipKind: Equatable {
    /// Ledger for the spend hotspot, grouped by day.
    case monthSpend
    /// Largest expenses this month, from the saved hotspot.
    case expensive
}

@Observable
@MainActor
final class SpendTipChrome {
    var maxHeight: CGFloat = 320
    var edge: SpendTipEdge = .above
    var kind: DashboardTipKind = .monthSpend
    var appeared = false
}

struct SpendTipHost: View {
    @Bindable var store: AppStore
    @Bindable var chrome: SpendTipChrome
    @Bindable var commandHints: CommandHintState
    var onHover: (Bool) -> Void
    var onSizeChange: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpendTipCard(
            title: chrome.kind.title,
            emptyText: chrome.kind.emptyText,
            lines: chrome.kind.lines(from: store),
            currencyCode: store.displayCurrencyCode,
            hideAmounts: store.hideBalance,
            showDayTotals: chrome.kind == .monthSpend,
            maxHeight: chrome.maxHeight,
            edge: chrome.edge,
            appeared: chrome.appeared,
            reduceMotion: reduceMotion,
            showExpandHint: commandHints.visible,
            onHover: onHover,
            onSizeChange: onSizeChange
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18),
            value: chrome.appeared
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22),
            value: chrome.kind
        )
    }
}

/// In-place list that replaces the dashboard + entry at the same size.
struct FocusedSpendList: View {
    @Bindable var store: AppStore
    var kind: DashboardTipKind
    var height: CGFloat
    var showCommandHints: Bool
    var reduceMotion: Bool

    var body: some View {
        ScrollView(.vertical) {
            SpendTipList(
                title: kind.title,
                emptyText: kind.emptyText,
                lines: kind.lines(from: store),
                currencyCode: store.displayCurrencyCode,
                hideAmounts: store.hideBalance,
                showDayTotals: kind == .monthSpend,
                appeared: true,
                reduceMotion: reduceMotion,
                compact: false,
                showExpandHint: showCommandHints
            )
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: MousPopup.cardWidth, height: max(height, 44), alignment: .top)
        .mousCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityHint("Command F returns to the dashboard.")
    }
}

struct SpendTipLine: Identifiable, Equatable {
    var id: String
    var signedValue: Double
    var title: String
    var civilDate: CivilDate?
}

extension DashboardTipKind {
    var title: String { self == .expensive ? "Most expensive" : "History" }
    var emptyText: String {
        self == .expensive ? "Nothing spent this month." : "Nothing yet this month."
    }

    @MainActor
    func lines(from store: AppStore) -> [SpendTipLine] {
        switch self {
        case .expensive:
            store.expensiveMonthRows.map {
                SpendTipLine(id: $0.id, signedValue: $0.signedValue, title: $0.title, civilDate: $0.civilDate)
            }
        case .monthSpend:
            store.monthTransactions.compactMap {
                guard let amount = store.displayedAmount($0.signedValue, currencyID: $0.currencyID) else {
                    return nil
                }
                return SpendTipLine(
                    id: String($0.id),
                    signedValue: amount,
                    title: $0.description,
                    civilDate: $0.civilDate
                )
            }
        }
    }
}

/// Month ledger in a compact card. Height hugs content up to `maxHeight`,
/// then scrolls with the indicator hidden.
///
/// History groups by civil day: a day-label row (name + day total) then
/// the day's transactions. Most expensive stays a ranked list.
struct SpendTipCard: View {
    var title: String
    var emptyText: String = "Nothing yet this month."
    var lines: [SpendTipLine]
    var currencyCode: String
    var hideAmounts: Bool = false
    var showDayTotals: Bool = false
    var maxHeight: CGFloat
    var edge: SpendTipEdge
    var appeared: Bool
    var reduceMotion: Bool
    var showExpandHint: Bool
    var onHover: (Bool) -> Void
    var onSizeChange: (CGSize) -> Void

    @State private var contentHeight: CGFloat = 0

    static let compactWidth: CGFloat = 244
    private static let innerPadding: CGFloat = 14
    /// Room for the card's own shadow so it isn't clipped by the panel.
    static let shadowMargin: CGFloat = 20

    var body: some View {
        let innerHeight = min(max(contentHeight, 44), max(maxHeight, 44))
        ScrollView(.vertical) {
            SpendTipList(
                title: title,
                emptyText: emptyText,
                lines: lines,
                currencyCode: currencyCode,
                hideAmounts: hideAmounts,
                showDayTotals: showDayTotals,
                appeared: appeared,
                reduceMotion: reduceMotion,
                compact: true,
                showExpandHint: showExpandHint
            )
            .padding(Self.innerPadding)
            .frame(width: Self.compactWidth, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TipHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.compactWidth, height: innerHeight, alignment: .top)
        .mousCard()
        .padding(Self.shadowMargin)
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : (edge == .above ? -6 : 6))
        .onPreferenceChange(TipHeightKey.self) { contentHeight = $0 }
        .onHover { onHover($0) }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onSizeChange(proxy.size) }
                    .onChange(of: proxy.size) { _, new in onSizeChange(new) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Command F shows the full list.")
    }

    private var accessibilityText: String {
        if lines.isEmpty { return emptyText }
        let heading = "\(title). "
        let rows = lines.enumerated().map { index, line in
            var text = hideAmounts
                ? "hidden \(line.title)"
                : "\(line.signedValue.formatted(SpendTipList.signedMoney(currencyCode))) \(line.title)"
            let isDayStart = index == 0 || lines[index - 1].civilDate != line.civilDate
            if isDayStart, let date = line.civilDate {
                text += " on \(SpendTipList.dayTitle(date))"
                if showDayTotals {
                    let total = lines.lazy.filter { $0.civilDate == date }.reduce(0) { $0 + $1.signedValue }
                    if hideAmounts {
                        text += ", hidden day total"
                    } else {
                        text += ", \(total.formatted(SpendTipList.signedMoney(currencyCode))) that day"
                    }
                }
            }
            return text
        }
        return heading + rows.joined(separator: ", ")
    }
}

struct SpendTipList: View {
    var title: String
    var emptyText: String
    var lines: [SpendTipLine]
    var currencyCode: String
    var hideAmounts: Bool = false
    var showDayTotals: Bool = false
    var appeared: Bool
    var reduceMotion: Bool
    var compact: Bool
    var showExpandHint: Bool
    @Environment(\.mousAccent) private var mousAccent
    @State private var amountMasks: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                CommandKeycap(letter: "f", visible: showExpandHint, reduceMotion: reduceMotion)
            }
            if lines.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if showDayTotals {
                groupedRows
            } else {
                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    rankedRows
                }
            }
        }
        .onAppear { refreshMasks(force: true) }
        .onChange(of: hideAmounts) { _, on in
            if on { refreshMasks(force: true) }
        }
        .onChange(of: lines.map(\.id)) { _, _ in
            refreshMasks(force: false)
        }
    }

    private var groupedRows: some View {
        let runs = Self.groupedDays(lines)
        return VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            ForEach(Array(runs.enumerated()), id: \.element.id) { runIndex, run in
                let base = runs.prefix(runIndex).reduce(0) { $0 + $1.lines.count }
                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    if let date = run.date {
                        appear(dayHeader(date: date, total: run.total), index: base)
                    }
                    ForEach(Array(run.lines.enumerated()), id: \.element.id) { offset, line in
                        appear(row(line, showDate: false), index: base + offset)
                    }
                }
            }
        }
    }

    private var rankedRows: some View {
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
            let showDate: Bool = {
                guard let date = line.civilDate else { return false }
                if index == 0 { return true }
                return lines[index - 1].civilDate != date
            }()
            appear(row(line, showDate: showDate), index: index)
        }
    }

    private func appear<Content: View>(_ content: Content, index: Int) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 4)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .easeOut(duration: 0.18).delay(Double(min(index, 12)) * 0.022),
                value: appeared
            )
    }

    private func dayHeader(date: CivilDate, total: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.dayTitle(date))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            Text(
                hideAmounts
                    ? mask(for: Self.dayTotalMaskID(date))
                    : dayTotalText(total)
            )
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(
                hideAmounts || total <= 0
                    ? AnyShapeStyle(.tertiary)
                    : AnyShapeStyle(mousAccent)
            )
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func dayTotalText(_ total: Double) -> String {
        if abs(total) < 0.005 {
            return (0.0).formatted(
                FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
                    .precision(.fractionLength(2))
            )
        }
        return total.formatted(Self.signedMoney(currencyCode))
    }

    private func row(_ line: SpendTipLine, showDate: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(hideAmounts ? mask(for: line.id) : line.signedValue.formatted(Self.signedMoney(currencyCode)))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(
                    hideAmounts || line.signedValue <= 0
                        ? AnyShapeStyle(.primary)
                        : AnyShapeStyle(mousAccent)
                )
                .layoutPriority(1)
            if !line.title.isEmpty {
                Text(line.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if showDate, let date = line.civilDate {
                Text(Self.dayTitle(date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func mask(for id: String) -> String {
        amountMasks[id] ?? freshMask()
    }

    private func refreshMasks(force: Bool) {
        guard hideAmounts else { return }
        let style = HideBalanceStyle.parse(MousConfigFile.load().hideBalanceStyle)
        var next = force ? [String: String]() : amountMasks
        for line in lines where next[line.id] == nil {
            next[line.id] = BalanceMask.make(style: style)
        }
        if showDayTotals {
            for run in Self.groupedDays(lines) {
                guard let date = run.date else { continue }
                let id = Self.dayTotalMaskID(date)
                if next[id] == nil {
                    next[id] = BalanceMask.make(style: style)
                }
            }
        }
        amountMasks = next
    }

    private func freshMask() -> String {
        BalanceMask.make(style: HideBalanceStyle.parse(MousConfigFile.load().hideBalanceStyle))
    }

    private static func groupedDays(_ lines: [SpendTipLine]) -> [DayRun] {
        var runs: [DayRun] = []
        for line in lines {
            if let date = line.civilDate, let last = runs.last, last.date == date {
                runs[runs.count - 1].lines.append(line)
                runs[runs.count - 1].total += line.signedValue
            } else {
                let key: String
                if let date = line.civilDate {
                    key = "\(runs.count)-\(date.year)-\(date.month)-\(date.day)"
                } else {
                    key = "\(runs.count)-\(line.id)"
                }
                runs.append(DayRun(id: key, date: line.civilDate, lines: [line], total: line.signedValue))
            }
        }
        return runs
    }

    private struct DayRun: Identifiable {
        var id: String
        var date: CivilDate?
        var lines: [SpendTipLine]
        var total: Double
    }

    private static func dayTotalMaskID(_ date: CivilDate) -> String {
        "day-\(date.year)-\(date.month)-\(date.day)"
    }

    static func dayTitle(_ date: CivilDate) -> String {
        if date == CivilDate.localToday() { return "Today" }
        let calendar = Calendar.current
        guard let day = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) else {
            return "\(date.day).\(date.month)"
        }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func signedMoney(_ code: String) -> FloatingPointFormatStyle<Double>.Currency {
        FloatingPointFormatStyle<Double>.Currency(code: code)
            .precision(.fractionLength(2))
            .sign(strategy: .always(showZero: false))
    }
}

private struct TipHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
