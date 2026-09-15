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
                    selection: currencyBinding,
                    reduceMotion: reduceMotion
                )
            }
            field("Show reports every.") {
                SettingsChoiceBar(
                    items: Array(ReportCadence.allCases),
                    title: \.label,
                    selection: $cadence,
                    reduceMotion: reduceMotion
                )
                if cadence == .custom {
                    customPeriodField
                        .transition(.opacity)
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
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: cadence)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: showAdvanced)
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
                    HStack {
                        Text("Developer mode")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Toggle("Developer mode", isOn: $config.dev)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(trackFill)
                    Text("Host, port, and database apply the next time mous starts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
    }

    private var trackFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.055))
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
}

private struct SettingsChoiceBar<Item: Hashable & Identifiable>: View {
    var items: [Item]
    var title: KeyPath<Item, String>
    @Binding var selection: Item
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(item[keyPath: title])
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: selection)
    }
}
