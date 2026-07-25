import SwiftUI

/// Bindings that dual-write to `AppState` (live re-render) and `SettingsStore`
/// (persistence), mirroring the existing display-mode pattern.
extension SettingsView {
    var displayModeBinding: Binding<ProviderDisplayMode> {
        Binding(
            get: { appState.displayMode },
            set: { newValue in
                appState.displayMode = newValue
                store.setDisplayMode(newValue)
            }
        )
    }

    /// The whole title format, written through on every mutation. Sub-fields
    /// (separator, custom template, color rule) project off this binding.
    var formatBinding: Binding<TitleFormat> {
        Binding(
            get: { appState.titleFormat },
            set: { newValue in
                appState.titleFormat = newValue
                store.setTitleFormat(newValue)
            }
        )
    }

    /// Preset changes seed an empty custom template from the previously shown
    /// preset so "Custom" starts from a real, editable string.
    var presetBinding: Binding<TitlePreset> {
        Binding(
            get: { appState.titleFormat.preset },
            set: { newValue in
                var format = appState.titleFormat
                if newValue == .custom, format.customTemplate.isEmpty {
                    format.customTemplate = seedTemplate(from: format)
                }
                format.preset = newValue
                appState.titleFormat = format
                store.setTitleFormat(format)
            }
        )
    }

    private func seedTemplate(from format: TitleFormat) -> String {
        var seed = format
        seed.preset = format.preset == .custom ? .full : format.preset
        return seed.resolvedTemplate(mode: appState.displayMode)
    }
}
