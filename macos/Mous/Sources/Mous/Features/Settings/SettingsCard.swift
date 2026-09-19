import MousCore
import SwiftUI

struct SettingsCard: View {
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var config: MousConfig
    @State private var cadence: ReportCadence
    @State private var customPeriod: String
    @State private var showAdvanced = false
    @State private var customInvalid = false
    @State private var scramblePreview = BalanceMask.make()
    @State private var showNotifyGhost = false
    @State private var didShowNotifyGhost = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let loaded = MousConfigFile.ensure()
        _config = State(initialValue: loaded)
        _cadence = State(initialValue: ReportCadence.classify(loaded.reportPeriod))
        _customPeriod = State(initialValue: loaded.reportPeriod)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            field("Theme.") {
                SettingsChoiceBar(
                    items: Array(MousTheme.allCases),
                    title: \.label,
                    selection: themeBinding,
                    reduceMotion: reduceMotion
                )
            }
            field("Currency.") {
                SettingsChoiceBar(
                    items: Array(MousCurrencyPref.allCases),
                    title: \.label,
                    mark: \.glyph,
                    selection: currencyBinding,
                    reduceMotion: reduceMotion
                )
            }
            field("Balance.") {
                VStack(alignment: .leading, spacing: 8) {
                    toggleRow("Hide balance", isOn: $config.hideBalance)
                    hideBalancePreview
                    if config.hideBalance {
                        SettingsChoiceBar(
                            items: Array(HideBalanceStyle.allCases),
                            title: \.label,
                            selection: hideStyleBinding,
                            reduceMotion: reduceMotion
                        )
                        .transition(.opacity)
                    }
                }
            }
            field("Show reports every.") {
                SettingsChoiceBar(
                    items: Array(ReportCadence.allCases),
                    title: \.label,
                    selection: $cadence,
                    reduceMotion: reduceMotion
                )
                if let caption = nextReportCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .accessibilityLabel(caption)
                }
                if cadence == .custom {
                    customPeriodField
                        .transition(.opacity)
                }
            }
            field("Notifications.") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        toggleRow("In-app inbox", isOn: $config.notifyInApp)
                        toggleRow("Mac banners", isOn: $config.notifyMacOS)
                    }
                    if showNotifyGhost {
                        notifyGhost
                            .transition(.opacity)
                    }
                }
            }
            field("Updates.") {
                UpdatesSettingsField()
            }
            advancedSection
        }
        .padding(20)
        .frame(width: MousPopup.cardWidth, alignment: .topLeading)
        .mousCard()
        .onChange(of: config) { _, new in
            MousConfigFile.save(new)
        }
        .onChange(of: config.theme) { _, new in
            MousAppearance.apply(new)
        }
        .onChange(of: cadence) { _, new in
            selectCadence(new)
        }
        .onChange(of: config.notifyInApp) { wasOn, isOn in
            previewNotifyIfNeeded(wasOn: wasOn, isOn: isOn)
        }
        .onChange(of: config.notifyMacOS) { wasOn, isOn in
            previewNotifyIfNeeded(wasOn: wasOn, isOn: isOn)
        }
        .onChange(of: config.hideBalance) { _, on in
            if on { scramblePreview = BalanceMask.make() }
        }
        .onChange(of: config.hideBalanceStyle) { _, _ in
            scramblePreview = BalanceMask.make()
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: cadence)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: showAdvanced)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: config.hideBalance)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18), value: showNotifyGhost)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Escape or Done returns to the dashboard.")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer(minLength: 12)
            Button("Done", action: onClose)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .help("Close settings")
        }
    }

    private var themeBinding: Binding<MousTheme> {
        Binding(
            get: { MousTheme(rawValue: config.theme) ?? .system },
            set: { config.theme = $0.rawValue }
        )
    }

    private var currencyBinding: Binding<MousCurrencyPref> {
        Binding(
            get: { MousCurrencyPref(rawValue: config.currency) ?? .eur },
            set: { config.currency = $0.rawValue }
        )
    }

    private var hideStyleBinding: Binding<HideBalanceStyle> {
        Binding(
            get: { HideBalanceStyle.parse(config.hideBalanceStyle) },
            set: { config.hideBalanceStyle = $0.rawValue }
        )
    }

    private var hideStyle: HideBalanceStyle {
        HideBalanceStyle.parse(config.hideBalanceStyle)
    }

    private var hideBalancePreview: some View {
        let masked: String = {
            if config.hideBalance, hideStyle == .scramble {
                return scramblePreview
            }
            return BalanceMask.veil(length: 4)
        }()
        return Text("\(Self.fakeBalance) → \(masked)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(config.hideBalance ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .accessibilityLabel(config.hideBalance ? "Balance hidden, preview" : "Preview: 12,480 dollars becomes hidden")
    }

    @ViewBuilder
    private var customPeriodField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("3 weeks", text: $customPeriod)
                .textFieldStyle(.plain)
                .font(.callout.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(trackFill)
                .autocorrectionDisabled()
                .onChange(of: customPeriod) { _, new in
                    commitCustomPeriod(new)
                }
            if customInvalid {
                Text("Try 3 weeks, 1 month, or 14 days.")
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))
            }
        }
    }

    private var nextReportCaption: String? {
        if cadence == .custom {
            let trimmed = customPeriod.split { $0.isWhitespace }.joined(separator: " ")
            if trimmed.isEmpty { return nil }
            if customInvalid || !ReportCadence.isValidPeriod(trimmed) {
                return "Fix the period"
            }
        }
        guard let date = ReportCadence.nextReportDate(period: config.reportPeriod) else {
            return nil
        }
        return "Next: \(formatNext(date))"
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showAdvanced.toggle()
            } label: {
                HStack {
                    Text("Advanced")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced")
            .accessibilityIdentifier("Advanced")
            .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows host, port, database, and developer mode.")

            if showAdvanced {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        field("Host.") {
                            TextField("127.0.0.1", text: $config.host)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(trackFill)
                                .autocorrectionDisabled()
                        }
                        field("Port.") {
                            TextField("8000", value: $config.port, format: .number.grouping(.never))
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(trackFill)
                        }
                        .frame(width: 108)
                    }
                    field("Database.") {
                        TextField("Path", text: $config.databasePath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(trackFill)
                            .autocorrectionDisabled()
                    }
                    toggleRow("Developer mode", isOn: $config.dev)
                    Text("Host, port, and database apply the next time mous starts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
    }

    private var notifyGhost: some View {
        HStack(spacing: 6) {
            Text("Mous")
                .fontWeight(.semibold)
            Text("•")
            Text("Report ready")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.opacity(0.94))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var trackFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.055))
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.callout)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(trackFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(title)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        .help(title == "Hide balance"
            ? "Hides spent, left, history, and most-expensive amounts."
            : title)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func selectCadence(_ option: ReportCadence) {
        customInvalid = false
        if let stored = option.storedValue {
            config.reportPeriod = stored
            customPeriod = stored
        } else if ReportCadence.classify(config.reportPeriod) != .custom {
            customPeriod = config.reportPeriod
        }
    }

    private func commitCustomPeriod(_ text: String) {
        guard cadence == .custom else { return }
        let trimmed = text.split { $0.isWhitespace }.joined(separator: " ")
        if trimmed.isEmpty {
            customInvalid = false
            return
        }
        if ReportCadence.isValidPeriod(trimmed) {
            customInvalid = false
            config.reportPeriod = trimmed
        } else {
            customInvalid = true
        }
    }

    private func previewNotifyIfNeeded(wasOn: Bool, isOn: Bool) {
        guard isOn, !wasOn, !didShowNotifyGhost else { return }
        didShowNotifyGhost = true
        showNotifyGhost = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            showNotifyGhost = false
        }
    }

    private func formatNext(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) != calendar.component(.year, from: Date()) {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static let fakeBalance = "$12,480.00"
}

private struct SettingsChoiceBar<Item: Hashable & Identifiable>: View {
    var items: [Item]
    var title: KeyPath<Item, String>
    var mark: KeyPath<Item, String>? = nil
    @Binding var selection: Item
    var reduceMotion: Bool
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item == selection
                let label = item[keyPath: title]
                let glyph = mark.map { item[keyPath: $0] }
                Button {
                    selection = item
                } label: {
                    VStack(spacing: 1) {
                        Text(label)
                        if let glyph, !glyph.isEmpty {
                            Text(glyph)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .opacity(selected ? 0.9 : 0.45)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, glyph == nil ? 7 : 5)
                    .contentShape(Rectangle())
                    .background {
                        if selected {
                            if reduceMotion {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                    }
                }
                .buttonStyle(SettingsChoiceChipStyle())
                .accessibilityLabel(label)
                .accessibilityIdentifier(label)
                .help(label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.22), value: selection)
    }
}

private struct SettingsChoiceChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
