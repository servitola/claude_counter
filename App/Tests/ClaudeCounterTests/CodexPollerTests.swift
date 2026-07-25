import Foundation
import Testing
@testable import ClaudeCounter

@MainActor
struct CodexPollerTests {
    private let stamp = Date(timeIntervalSince1970: 1)

    @Test func successPopulatesCodexUsageAndStatus() async {
        let usage = ProviderUsage(
            currentPercent: 5, weeklyPercent: 10, updatedAt: stamp
        )
        let poller = CodexPoller { .success(usage) }
        let state = AppState()
        poller.attach(appState: state)

        poller.forceRefresh()
        await poller.awaitInFlight()

        #expect(state.codex == usage)
        #expect(state.codexStatus == .ok)
    }

    @Test func needsReauthClearsStaleDataAndFlagsAuth() async {
        let poller = CodexPoller { .needsReauth }
        let state = AppState()
        state.codex = ProviderUsage(currentPercent: 50, weeklyPercent: 60, updatedAt: stamp)
        poller.attach(appState: state)

        poller.forceRefresh()
        await poller.awaitInFlight()

        #expect(state.codex == .empty)
        #expect(state.codexStatus == .needsAuth)
    }

    @Test func transportErrorLeavesLastSnapshotButFlagsError() async {
        let last = ProviderUsage(currentPercent: 20, weeklyPercent: 30, updatedAt: stamp)
        let poller = CodexPoller { .transport(URLError(.timedOut)) }
        let state = AppState()
        state.codex = last
        poller.attach(appState: state)

        poller.forceRefresh()
        await poller.awaitInFlight()

        #expect(state.codex == last)
        #expect(state.codexStatus == .error)
    }
}
