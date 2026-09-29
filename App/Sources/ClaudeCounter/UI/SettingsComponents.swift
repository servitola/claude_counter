import SwiftUI

// MARK: - SettingsCard

/// A titled glass panel grouping one block of settings.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - ProviderPicker

/// Three brand-tinted glass pills; the selected one lights up in its color.
struct ProviderPicker: View {
    @Binding var selection: ProviderDisplayMode

    var body: some View {
        GlassGroup {
            HStack(spacing: 8) {
                ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                    pill(for: mode)
                }
            }
        }
    }

    private func pill(for mode: ProviderDisplayMode) -> some View {
        let isSelected = mode == selection
        return Button {
            withAnimation(.snappy) { selection = mode }
        } label: {
            Label(mode.shortTitle, systemImage: mode.symbol)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(
            in: Capsule(),
            tint: isSelected ? mode.tint.opacity(0.55) : nil,
            interactive: true
        )
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - PresetList

/// Preset rows with a one-line explanation each, instead of a bare popup.
struct PresetList: View {
    @Binding var selection: TitlePreset

    var body: some View {
        VStack(spacing: 2) {
            ForEach(TitlePreset.allCases, id: \.self) { preset in
                row(for: preset)
            }
        }
    }

    private func row(for preset: TitlePreset) -> some View {
        let isSelected = preset == selection
        return Button {
            withAnimation(.snappy) { selection = preset }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension ProviderDisplayMode {
    var shortTitle: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .both: "Both"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "terminal"
        case .both: "square.split.2x1"
        }
    }

    var tint: Color {
        switch self {
        case .claude: .claudeBrand
        case .codex: .codexBrand
        case .both: .indigo
        }
    }
}

private extension TitlePreset {
    var subtitle: String {
        switch self {
        case .full: "Session %, reset countdown and weekly %"
        case .weekly: "Weekly % only"
        case .session: "Session % and its reset"
        case .weeklyAlert: "Weekly %, colored by Claude's session"
        case .custom: "Your own template with tokens"
        }
    }
}
