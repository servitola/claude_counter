import AppKit

/// The Usage window: both providers' cards on glass, sized to its content.
@MainActor
final class UsageOverviewWindow {
    static let shared = UsageOverviewWindow()

    private let slot = GlassWindowSlot(.init(
        title: "Usage — Claude + Codex",
        size: NSSize(width: 360, height: 420),
        styleMask: [.titled, .closable, .miniaturizable],
        autosaveName: "ClaudeCounter.UsageOverviewWindow"
    ))

    private init() {}

    func show(appState: AppState) {
        slot.show { UsageOverviewView(appState: appState) }
    }
}
