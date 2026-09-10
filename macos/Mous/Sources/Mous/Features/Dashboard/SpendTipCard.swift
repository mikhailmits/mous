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
    var onHover: (Bool) -> Void
    var onSizeChange: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpendTipCard(
            title: chrome.kind == .expensive ? "Most expensive" : "History",
            emptyText: chrome.kind == .expensive
                ? "Nothing spent this month."
                : "Nothing yet this month.",
            lines: chrome.kind == .expensive
                ? store.expensiveMonthRows.map {
                    SpendTipLine(id: $0.id, signedValue: $0.signedValue, title: $0.title, civilDate: $0.civilDate)
                }
                : store.monthTransactions.map {
                    SpendTipLine(
                        id: String($0.id),
                        signedValue: $0.signedValue,
                        title: $0.description,
                        civilDate: $0.civilDate
                    )
                },
            maxHeight: chrome.maxHeight,
            edge: chrome.edge,
            appeared: chrome.appeared,
            reduceMotion: reduceMotion,
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

struct SpendTipLine: Identifiable, Equatable {
    var id: String
    var signedValue: Double
    var title: String
    var civilDate: CivilDate?
}

/// Month ledger in a compact card. Height hugs content up to `maxHeight`,
/// then scrolls with the indicator hidden.
///
/// History rows are amount + description with a day label on the first
/// row of each day run. Most expensive uses the same layout, ranked by
/// spend, still labeling Today / Yesterday when the day changes.
struct SpendTipCard: View {
    var title: String
    var emptyText: String = "Nothing yet this month."
    var lines: [SpendTipLine]
    var maxHeight: CGFloat
    var edge: SpendTipEdge
    var appeared: Bool
    var reduceMotion: Bool
    var onHover: (Bool) -> Void
    var onSizeChange: (CGSize) -> Void

    @State private var contentHeight: CGFloat = 0

    private static let width: CGFloat = 244
    private static let innerPadding: CGFloat = 14
    /// Room for the card's own shadow so it isn't clipped by the panel.
    static let shadowMargin: CGFloat = 20

    var body: some View {
        let innerHeight = min(max(contentHeight, 44), max(maxHeight, 44))
        ScrollView(.vertical) {
            list
                .padding(Self.innerPadding)
                .frame(width: Self.width, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TipHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width, height: innerHeight, alignment: .top)
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
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            if lines.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    rows(lines)
                }
            }
        }
    }

    private func rows(_ lines: [SpendTipLine]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
            let showDate: Bool = {
                guard let date = line.civilDate else { return false }
                if index == 0 { return true }
                return lines[index - 1].civilDate != date
            }()
            row(line, showDate: showDate)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 4)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .easeOut(duration: 0.18).delay(Double(min(index, 12)) * 0.022),
                    value: appeared
                )
        }
    }

    private func row(_ line: SpendTipLine, showDate: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.signedValue, format: Self.signedEUR)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(line.signedValue > 0 ? AnyShapeStyle(Color.green.opacity(0.5)) : AnyShapeStyle(.primary))
                .layoutPriority(1)
            if !line.title.isEmpty {
                Text(line.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private static func dayTitle(_ date: CivilDate) -> String {
        if date == CivilDate.localToday() { return "Today" }
        let calendar = Calendar.current
        guard let day = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) else {
            return "\(date.day).\(date.month)"
        }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var accessibilityText: String {
        if lines.isEmpty { return emptyText }
        let heading = "\(title). "
        let rows = lines.map { line in
            var text = "\(line.signedValue.formatted(Self.signedEUR)) \(line.title)"
            if let date = line.civilDate {
                text += " on \(Self.dayTitle(date))"
            }
            return text
        }
        return heading + rows.joined(separator: ", ")
    }

    private static let signedEUR = FloatingPointFormatStyle<Double>.Currency(code: "EUR")
        .precision(.fractionLength(2))
        .sign(strategy: .always(showZero: false))
}

private struct TipHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
