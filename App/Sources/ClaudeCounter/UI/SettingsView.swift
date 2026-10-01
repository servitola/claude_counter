import CounterShared
import SwiftUI

/// Settings form: pick which provider(s) the menu-bar strip shows and how the
/// title is formatted + colored. Writes through `SettingsStore` (persistence)
/// and updates `AppState` (live re-render of the menu bar).
struct SettingsView: View {
    let appState: AppState
    let store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassLayout.rim) {
                heroCard
                providerCard
                formatCard
            }
            .padding(GlassLayout.rim)
        }
        .scrollIndicators(.never)
        .scrollEdgeFade()
        .ignoresSafeArea(edges: .top)
        .background(GlassBackdrop())
        .frame(minWidth: 440, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.claudeBrand, .codexBrand],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .glassSurface(in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Counter")
                    .font(.title2.weight(.semibold))
                Text("Menu-bar title and colors")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroCard: some View {
        SettingsCard(
            title: "Live preview",
            symbol: "menubar.rectangle",
            topInset: GlassLayout.titlebarClearance
        ) {
            header
                .padding(.bottom, 4)
            Text(previewTitle)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .glassSurface(in: Capsule())
        }
    }

    private var providerCard: some View {
        SettingsCard(title: "Menu bar shows", symbol: "square.stack.3d.up") {
            // A custom template names its providers in its own tokens, so the
            // pills would change nothing.
            let isCustom = appState.titleFormat.preset == .custom
            ProviderPicker(selection: displayModeBinding)
                .disabled(isCustom)
                .opacity(isCustom ? 0.4 : 1)
            if isCustom {
                Label(
                    "The custom template picks providers with its tokens.",
                    systemImage: "curlybraces"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            codexHint
        }
    }

    private var formatCard: some View {
        SettingsCard(title: "Format", symbol: "textformat") {
            PresetList(selection: presetBinding)
            if appState.titleFormat.preset == .custom {
                CustomFormatEditor(format: formatBinding)
            } else if appState.displayMode == .both {
                HStack {
                    Text("Separator")
                    Spacer()
                    TextField("Separator", text: formatBinding.separator)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                .padding(.horizontal, 10)
            }
        }
        .animation(.snappy, value: appState.titleFormat.preset)
        .animation(.snappy, value: appState.displayMode)
    }

    private var codexHint: some View {
        Label {
            Text("Codex usage is read from your local Codex CLI login "
                + "(~/.codex/auth.json). Sign in once with `codex` in a terminal.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
