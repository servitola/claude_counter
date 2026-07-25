import SwiftUI

/// Settings form: pick which provider(s) the menu-bar strip shows and how the
/// title is formatted + colored. Writes through `SettingsStore` (persistence)
/// and updates `AppState` (live re-render of the menu bar).
struct SettingsView: View {
    let appState: AppState
    let store: SettingsStore

    var body: some View {
        Form {
            providerSection
            formatSection
            previewSection
            codexHint
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 320)
    }

    private var providerSection: some View {
        Section("Menu bar shows") {
            Picker("Provider", selection: displayModeBinding) {
                ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    private var formatSection: some View {
        Section("Format") {
            Picker("Preset", selection: presetBinding) {
                ForEach(TitlePreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            if appState.titleFormat.preset != .custom {
                TextField("Separator", text: formatBinding.separator)
            } else {
                CustomFormatEditor(format: formatBinding)
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            Text(previewTitle)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.vertical, 2)
        }
    }

    private var codexHint: some View {
        Text("Codex usage is read from your local Codex CLI login "
            + "(~/.codex/auth.json). Sign in once with `codex` in a terminal.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The rendered title for whatever numbers are on hand — the live snapshot
    /// when a provider has fetched, else a representative sample so the preview
    /// is meaningful before the first fetch.
    private var previewTitle: AttributedString {
        let now = Date()
        let claude = appState.usage.isLoaded
            ? appState.usage
            : ProviderUsage(
                currentPercent: 73, weeklyPercent: 76,
                currentResetAt: now.addingTimeInterval(60 * 135),
                weeklyResetAt: now.addingTimeInterval(60 * 60 * 24 * 4), updatedAt: now
            )
        let codex = appState.codex.isLoaded
            ? appState.codex
            : ProviderUsage(
                currentPercent: 4, weeklyPercent: 30,
                weeklyResetAt: now.addingTimeInterval(60 * 60 * 24 * 3), updatedAt: now
            )
        let rendered = QuotaTitleFormatter.render(
            claude: claude, codex: codex, mode: appState.displayMode,
            format: appState.titleFormat, now: now
        )
        return AttributedString(rendered)
    }
}
