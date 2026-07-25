import SwiftUI

// MARK: - UsageOverviewView

/// Native overview of both providers' usage, bound to the shared `@Observable`
/// `AppState`. Each card shows the current (5h) and weekly windows as
/// percent-used / remaining plus a reset countdown. Reading `AppState`
/// properties in `body` sets up Observation tracking, so the view re-renders on
/// every poll.
struct UsageOverviewView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderCard(
                title: "Claude",
                usage: appState.usage,
                status: appState.usage.isLoaded ? .ok : .loading,
                authHint: nil
            )
            Divider()
            ProviderCard(
                title: "Codex",
                usage: appState.codex,
                status: appState.codexStatus,
                authHint: "Log in with the Codex CLI: run `codex` and sign in."
            )
        }
        .padding(20)
        .frame(width: 340)
    }
}

// MARK: - ProviderCard

/// One provider's card: title, then a row per window (current / weekly).
private struct ProviderCard: View {
    let title: String
    let usage: ProviderUsage
    let status: ProviderStatus
    /// Shown under the title when `status == .needsAuth`.
    let authHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if status == .needsAuth {
                Text(authHint ?? "Not signed in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !usage.isLoaded {
                Text(status == .error ? "Couldn't load usage." : "Loading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                WindowRow(
                    label: "5-hour",
                    percent: usage.currentPercent,
                    resetAt: usage.currentResetAt
                )
                WindowRow(
                    label: "Weekly",
                    percent: usage.weeklyPercent,
                    resetAt: usage.weeklyResetAt
                )
            }
        }
    }
}

// MARK: - WindowRow

/// A single window row: label, a used/remaining bar, and a reset countdown.
private struct WindowRow: View {
    let label: String
    let percent: Int?
    let resetAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: Double(percent ?? 0), total: 100)
                .tint(color)
            HStack {
                Text(remainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentText: String {
        percent.map { "\($0)% used" } ?? "–%"
    }

    private var remainingText: String {
        percent.map { "\(max(0, 100 - $0))% left" } ?? ""
    }

    private var resetText: String {
        guard let resetAt else { return "" }
        return "resets in \(QuotaTitleFormatter.formatRemaining(resetAt))"
    }

    private var color: Color {
        switch percent ?? 0 {
        case QuotaTitleFormatter.alertThreshold...: .red
        case QuotaTitleFormatter.warnThreshold...: .orange
        default: .primary
        }
    }
}
