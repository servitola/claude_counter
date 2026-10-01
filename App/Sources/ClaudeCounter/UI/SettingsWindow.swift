import AppKit

/// The Settings window: `SettingsView` on glass, resizable, scrolls its content.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private let slot = GlassWindowSlot(.init(
        title: "Settings",
        size: NSSize(width: 460, height: 700),
        styleMask: [.titled, .closable, .resizable],
        // v2: 1.1.0 saved screen-tall frames while the window sized to its content.
        autosaveName: "ClaudeCounter.SettingsWindow.v2",
        sizesToContent: false
    ))

    private init() {}

    func show(appState: AppState, store: SettingsStore) {
        slot.show { SettingsView(appState: appState, store: store) }
    }
}
