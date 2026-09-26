import MousCore
import SwiftUI

struct SettingsCard: View {
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mousAccent) private var mousAccent
    @State private var config: MousConfig
    @State private var showAdvanced = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        _config = State(initialValue: MousConfigFile.ensure())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            field("Theme.") {
                ThemeSlider(selection: themeBinding, reduceMotion: reduceMotion)
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
                    toggleRow("Hide balance", isOn: hideBalanceBinding)
                    Text(config.hideBalance
                        ? "Amounts become dots. Hold the eye on Spent today to peek."
                        : "Turn this on to cover amounts. Hold the eye to peek.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
            persist(new)
        }
        .onChange(of: config.theme) { _, new in
            MousAppearance.apply(new)
        }
        .onDisappear {
            persist(config)
        }
        .animation(MousMotion.spring(reduceMotion: reduceMotion), value: showAdvanced)
        .animation(MousMotion.quick(reduceMotion: reduceMotion), value: config.hideBalance)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Escape or Done returns to the dashboard.")
    }

    /// Write the whole struct so `@State` and `onChange(of: config)` always see a replace.
    private func persist(_ value: MousConfig) {
        MousConfigFile.save(value)
    }

    private func writeConfig(_ mutate: (inout MousConfig) -> Void) {
        var next = config
        mutate(&next)
        guard next != config else { return }
        config = next
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer(minLength: 12)
            Button("Done", action: onClose)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(mousAccent)
                .buttonStyle(.plain)
                .help("Close settings")
        }
    }

    private var themeBinding: Binding<MousTheme> {
        Binding(
            get: { MousTheme.parse(config.theme) },
            set: { newValue in
                writeConfig { $0.theme = newValue.rawValue }
            }
        )
    }

    private var currencyBinding: Binding<MousCurrencyPref> {
        Binding(
            get: { MousCurrencyPref.pref(for: config.currency) },
            set: { newValue in
                writeConfig { $0.currency = newValue.rawValue }
            }
        )
    }

    private var hideBalanceBinding: Binding<Bool> {
        Binding(
            get: { config.hideBalance },
            set: { newValue in
                writeConfig { $0.hideBalance = newValue }
            }
        )
    }

    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { config.dev },
            set: { newValue in
                writeConfig { $0.dev = newValue }
            }
        )
    }

    private var hostBinding: Binding<String> {
        Binding(
            get: { config.host },
            set: { newValue in
                writeConfig { $0.host = newValue }
            }
        )
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { config.port },
            set: { newValue in
                writeConfig { $0.port = newValue }
            }
        )
    }

    private var databasePathBinding: Binding<String> {
        Binding(
            get: { config.databasePath },
            set: { newValue in
                writeConfig { $0.databasePath = newValue }
            }
        )
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
                            TextField("127.0.0.1", text: hostBinding)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(trackFill)
                                .autocorrectionDisabled()
                        }
                        field("Port.") {
                            TextField("8000", value: portBinding, format: .number.grouping(.never))
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
                        TextField("Path", text: databasePathBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(trackFill)
                            .autocorrectionDisabled()
                    }
                    toggleRow("Developer mode", isOn: developerModeBinding)
                    Text("Host, port, and database apply the next time mous starts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var trackFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.06))
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
            ? "Covers spent, left, history, and most-expensive amounts. Hold the eye to peek."
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
}

/// Drag across the row like a slider, or tap a swatch. Selected tile keeps a thin ring.
private struct ThemeSlider: View {
    @Binding var selection: MousTheme
    var reduceMotion: Bool
    @Environment(\.mousAccent) private var mousAccent

    private static let swatchGap: CGFloat = 4
    private static let swatchHeight: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let themes = Array(MousTheme.allCases)
                let width = proxy.size.width
                HStack(spacing: Self.swatchGap) {
                    ForEach(themes) { theme in
                        swatch(theme, selected: theme == selection)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.swatchHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard let next = Self.theme(
                                at: value.location.x,
                                width: width,
                                themes: themes
                            ), next != selection else { return }
                            selection = next
                        }
                )
            }
            .frame(height: Self.swatchHeight)
            // Nudge the row a touch wider than the field labels above.
            .padding(.horizontal, -4)
            Text(selection.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(mousAccent)
                .contentTransition(.interpolate)
        }
        .animation(MousMotion.spring(reduceMotion: reduceMotion), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
        .accessibilityValue(selection.label)
        .accessibilityAdjustableAction { direction in
            let themes = Array(MousTheme.allCases)
            guard let index = themes.firstIndex(of: selection) else { return }
            switch direction {
            case .increment:
                selection = themes[min(index + 1, themes.count - 1)]
            case .decrement:
                selection = themes[max(index - 1, 0)]
            @unknown default:
                break
            }
        }
    }

    /// Map drag x onto swatch cells, accounting for the fixed gaps between them.
    static func theme(at x: CGFloat, width: CGFloat, themes: [MousTheme]) -> MousTheme? {
        let count = themes.count
        guard count > 0, width > 0 else { return nil }
        let gaps = Self.swatchGap * CGFloat(count - 1)
        let cellWidth = (width - gaps) / CGFloat(count)
        guard cellWidth > 0 else { return nil }
        let slot = cellWidth + Self.swatchGap
        let clamped = min(max(x, 0), width - 0.001)
        let index = min(count - 1, max(0, Int(clamped / slot)))
        return themes[index]
    }

    private func swatch(_ theme: MousTheme, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            shape.fill(theme.canvas)
            if let image = MousIcons.previewImage(for: theme) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Match AppIcon optical nudge (~1% of the tile).
                    .offset(x: -1)
                    .padding(selected ? 4 : 6)
            }
        }
        .overlay {
            shape.strokeBorder(
                selected ? theme.mark : Color.clear,
                lineWidth: selected ? 2 : 0
            )
        }
        .scaleEffect(selected ? 1 : 0.97)
        .contentShape(shape)
        .onTapGesture { selection = theme }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityLabel(theme.label)
        .accessibilityIdentifier(theme.label)
    }
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
                    HStack(spacing: 4) {
                        Text(label)
                        if let glyph, !glyph.isEmpty {
                            Text(glyph)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .opacity(selected ? 0.85 : 0.5)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .matchedGeometryEffect(id: "pill", in: pill)
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
                .fill(Color.white.opacity(0.06))
        }
        .animation(MousMotion.quick(reduceMotion: reduceMotion), value: selection)
    }
}

private struct SettingsChoiceChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
