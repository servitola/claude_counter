import CounterShared
import SwiftUI
import WidgetKit

// MARK: - UsageEntry

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?

    /// The app refreshes every minute while it runs; older than this means
    /// it is not running or cannot reach the providers.
    var isStale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince(snapshot.updatedAt) > 10 * 60
    }

    static let sample = Self(
        date: .now,
        snapshot: UsageSnapshot(
            claude: .init(
                currentPercent: 34, weeklyPercent: 61,
                currentResetAt: .now.addingTimeInterval(2 * 3600 + 28 * 60),
                weeklyResetAt: .now.addingTimeInterval(3 * 86400)
            ),
            codex: .init(
                currentPercent: 12, weeklyPercent: 48,
                currentResetAt: .now.addingTimeInterval(4 * 3600),
                weeklyResetAt: .now.addingTimeInterval(5 * 86400)
            ),
            updatedAt: .now
        )
    )
}

// MARK: - UsageTimeline

struct UsageTimeline: TimelineProvider {
    func placeholder(in _: Context) -> UsageEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = Self.load()
        completion(snapshot == nil && context.isPreview
            ? .sample
            : UsageEntry(date: .now, snapshot: snapshot))
    }

    /// One entry a minute for an hour, so the reset countdown ticks without
    /// spending WidgetKit's reload budget; the app reloads when numbers change.
    func getTimeline(in _: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = Self.load()
        let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0 ..< 60).map { minute in
            UsageEntry(date: start.addingTimeInterval(Double(minute) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func load() -> UsageSnapshot? {
        guard let url = SharedContainer.snapshotURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? UsageSnapshot.decode(data)
    }
}

// MARK: - UsageWidget

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.widgetKind, provider: UsageTimeline()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Counter")
        .description("Claude and Codex usage: the 5-hour and weekly windows, and when they reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - ClaudeCounterWidgets

@main
struct ClaudeCounterWidgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}
