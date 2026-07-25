import AppKit
import Foundation

/// 60 s usage poller for Codex. Mirrors `QuotaScraper`'s timer + single-flight +
/// wake-observer shape, but with none of the WebView machinery: `CodexUsageClient`
/// reads the local token and hits the backend directly. Writes into
/// `AppState.codex` / `AppState.codexStatus` on the main actor.
@MainActor
final class CodexPoller {
    static let interval: TimeInterval = 60

    private weak var appState: AppState?
    private var timer: Timer?
    private var isFetching = false
    /// The in-flight pass, exposed only so tests can await it.
    private(set) var inFlightTask: Task<Void, Never>?
    // Wake token — held for the poller's lifetime (it never deallocates).
    // periphery:ignore
    private var wakeObserver: (any NSObjectProtocol)?

    /// The usage probe. Defaults to the production `CodexUsageClient.fetch()`;
    /// tests substitute a scripted `CodexFetchResult` with no network.
    private let fetchUsage: @Sendable () async -> CodexFetchResult

    init(fetchUsage: (@Sendable () async -> CodexFetchResult)? = nil) {
        if let fetchUsage {
            self.fetchUsage = fetchUsage
        } else {
            let client = CodexUsageClient()
            self.fetchUsage = { await client.fetch() }
        }
    }

    // MARK: - Lifecycle

    /// Wire `AppState` without starting the timer (used by `start` and tests).
    func attach(appState: AppState) {
        self.appState = appState
    }

    func start(appState: AppState) {
        attach(appState: appState)
        scrape()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scrape() }
        }
        timer?.tolerance = 10
        observeWake()
    }

    /// Explicit re-probe, wired to system wake and the menu's window-open action.
    func forceRefresh() {
        scrape()
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forceRefresh()
            }
        }
    }

    // MARK: - Fetch

    private func scrape() {
        guard !isFetching else { return }
        isFetching = true
        inFlightTask = Task { [weak self] in
            let result = await self?.fetchUsage()
            await MainActor.run {
                guard let self else { return }
                self.isFetching = false
                if let result {
                    self.apply(result)
                }
            }
        }
    }

    private func apply(_ result: CodexFetchResult) {
        switch result {
        case .success(let usage):
            appState?.codex = usage
            appState?.codexStatus = .ok
            AppLog.codex.debug("result=success")

        case .needsReauth:
            // Clear stale data so the overview shows the "log in via codex CLI"
            // hint rather than a misleading old snapshot.
            appState?.codex = .empty
            appState?.codexStatus = .needsAuth
            AppLog.codex.notice("result=needsReauth")

        case .decodeFailed:
            appState?.codexStatus = .error
            AppLog.codex.notice("result=decodeFailed — leaving state")

        case .transport:
            appState?.codexStatus = .error
            AppLog.codex.notice("result=transport — leaving state")
        }
    }

    /// Test hook: await the in-flight pass (and its MainActor apply).
    func awaitInFlight() async {
        await inFlightTask?.value
    }
}
