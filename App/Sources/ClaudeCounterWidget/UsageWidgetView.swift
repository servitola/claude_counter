import CounterShared
import SwiftUI
import WidgetKit

// MARK: - UsageWidgetView

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
                .opacity(entry.isStale ? 0.55 : 1)
                .overlay(alignment: .topTrailing) {
                    if entry.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Not updated recently")
                    }
                }
        } else {
            Label("Open Claude Counter to start", systemImage: "gauge.with.dots.needle.33percent")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: UsageSnapshot) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 10) {
                CompactProvider(
                    name: "Claude",
                    tint: .claudeBrand,
                    usage: snapshot.claude,
                    now: entry.date
                )
                CompactProvider(
                    name: "Codex",
                    tint: .codexBrand,
                    usage: snapshot.codex,
                    now: entry.date
                )
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                DetailedProvider(
                    name: "Claude",
                    symbol: "sparkle",
                    tint: .claudeBrand,
                    usage: snapshot.claude,
                    now: entry.date
                )
                DetailedProvider(
                    name: "Codex",
                    symbol: "terminal",
                    tint: .codexBrand,
                    usage: snapshot.codex,
                    now: entry.date
                )
            }
        }
    }
}

// MARK: - CompactProvider

/// Small widget: the session percentage large, the weekly one beside it.
private struct CompactProvider: View {
    let name: String
    let tint: Color
    let usage: UsageSnapshot.Provider
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text("wk \(percent(usage.weeklyPercent))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(UsageStyle.color(for: usage.weeklyPercent, normal: .secondary))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(percent(usage.currentPercent))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageStyle.color(for: usage.currentPercent, normal: .primary))
                Spacer()
                Text(UsageStyle.remaining(
                    until: usage.currentResetAt ?? usage.weeklyResetAt,
                    now: now
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            UsageMeter(percent: usage.currentPercent ?? usage.weeklyPercent, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - DetailedProvider

/// Medium widget: a column per provider with both windows.
private struct DetailedProvider: View {
    let name: String
    let symbol: String
    let tint: Color
    let usage: UsageSnapshot.Provider
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            window("5-hour", usage.currentPercent, resetAt: usage.currentResetAt)
            window("Weekly", usage.weeklyPercent, resetAt: usage.weeklyResetAt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func window(_ label: String, _ value: Int?, resetAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percent(value))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageStyle.color(for: value, normal: .primary))
            }
            UsageMeter(percent: value, tint: tint)
            Text("resets in \(UsageStyle.remaining(until: resetAt, now: now))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UsageMeter

private struct UsageMeter: View {
    let percent: Int?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule()
                    .fill(UsageStyle.color(for: percent, normal: tint))
                    .frame(width: max(
                        4,
                        geo.size.width * Double(min(100, max(0, percent ?? 0))) / 100
                    ))
            }
        }
        .frame(height: 5)
        .widgetAccentable()
    }
}

private func percent(_ value: Int?) -> String {
    value.map { "\($0)%" } ?? "–%"
}
