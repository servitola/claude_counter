import CounterShared
import Foundation
import WidgetKit

/// Leaves every fresh snapshot in the App Group container, where the sandboxed
/// widget can read it: the same bytes `ClaudeCounter --json` prints.
@MainActor
final class WidgetBridge {
    private let appState: AppState
    private var lastDigest: Digest?

    /// What the widget shows, minute-resolved. The widget precomputes its
    /// countdown, so a timeline reload is needed only when this changes, and
    /// WidgetKit rations reloads for an app that is never in the foreground.
    struct Digest: Equatable {
        // Read only by the synthesized `==`, which periphery does not trace.
        // periphery:ignore
        let claude: [Int?]
        // periphery:ignore
        let codex: [Int?]

        init(_ claude: ProviderUsage, _ codex: ProviderUsage) {
            self.claude = Self.fields(claude)
            self.codex = Self.fields(codex)
        }

        private static func fields(_ usage: ProviderUsage) -> [Int?] {
            [
                usage.currentPercent,
                usage.weeklyPercent,
                usage.currentResetAt.map { Int($0.timeIntervalSince1970 / 60) },
                usage.weeklyResetAt.map { Int($0.timeIntervalSince1970 / 60) }
            ]
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            publish(appState.usage, codex: appState.codex)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func publish(_ claude: ProviderUsage, codex: ProviderUsage) {
        guard claude.isLoaded || codex.isLoaded else { return }
        guard let url = SharedContainer.snapshotURL else {
            AppLog.widget.error("app group container unavailable")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try StatusExport.encode(claude, codex: codex).write(to: url, options: .atomic)
        } catch {
            AppLog.widget
                .error("snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let digest = Digest(claude, codex)
        guard digest != lastDigest else { return }
        lastDigest = digest
        WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.widgetKind)
    }
}
