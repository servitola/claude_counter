import CounterShared
import Foundation
import Testing
@testable import ClaudeCounter

struct WidgetSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func widget_reads_back_what_the_app_exports() throws {
        let claude = ProviderUsage(
            currentPercent: 9, weeklyPercent: 26,
            currentResetAt: now.addingTimeInterval(3600),
            weeklyResetAt: now.addingTimeInterval(86400), updatedAt: now
        )
        let codex = ProviderUsage(
            weeklyPercent: 51,
            weeklyResetAt: now.addingTimeInterval(7200),
            updatedAt: now
        )

        let snapshot = try UsageSnapshot.decode(StatusExport.encode(claude, codex: codex, now: now))

        #expect(snapshot.claude == UsageSnapshot.Provider(
            currentPercent: 9, weeklyPercent: 26,
            currentResetAt: claude.currentResetAt, weeklyResetAt: claude.weeklyResetAt
        ))
        #expect(snapshot.codex == UsageSnapshot.Provider(
            weeklyPercent: 51,
            weeklyResetAt: codex.weeklyResetAt
        ))
        #expect(snapshot.updatedAt == now)
    }

    @Test func missing_codex_object_reads_as_unknown() throws {
        let json = Data(
            #"{"schemaVersion":1,"currentPercent":5,"updatedAt":"2026-07-14T13:02:00Z"}"#
                .utf8
        )

        let snapshot = try UsageSnapshot.decode(json)

        #expect(snapshot.claude.currentPercent == 5)
        #expect(!snapshot.codex.isLoaded)
    }

    @Test func digest_ignores_seconds_and_update_time() {
        let reset = Date(timeIntervalSince1970: 1_700_000_040)
        let first = ProviderUsage(currentPercent: 9, currentResetAt: reset, updatedAt: now)
        let jittered = ProviderUsage(
            currentPercent: 9, currentResetAt: reset.addingTimeInterval(10),
            updatedAt: now.addingTimeInterval(60)
        )

        #expect(WidgetBridge.Digest(first, .empty) == WidgetBridge.Digest(jittered, .empty))
    }

    @Test func digest_changes_with_a_percentage() {
        let before = ProviderUsage(currentPercent: 9)
        let after = ProviderUsage(currentPercent: 10)

        #expect(WidgetBridge.Digest(before, .empty) != WidgetBridge.Digest(after, .empty))
    }

    @Test func remaining_time_formats_days_hours_minutes() {
        #expect(UsageStyle
            .remaining(until: now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now) == "3d 4h")
        #expect(UsageStyle
            .remaining(until: now.addingTimeInterval(2 * 3600 + 28 * 60), now: now) == "2h 28m")
        #expect(UsageStyle.remaining(until: now.addingTimeInterval(45 * 60), now: now) == "45m")
        #expect(UsageStyle.remaining(until: nil, now: now) == "–m")
    }
}
