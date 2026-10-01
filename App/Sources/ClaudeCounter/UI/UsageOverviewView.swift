import CounterShared
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
        VStack(alignment: .leading, spacing: GlassLayout.rim) {
            ProviderCard(
                title: "Claude",
                topInset: GlassLayout.titlebarClearance,
                symbol: "sparkle",
                tint: .claudeBrand,
                usage: appState.usage,
                status: appState.usage.isLoaded ? .ok : .loading,
                authHint: nil
            )
            ProviderCard(
                title: "Codex",
                symbol: "terminal",
                tint: .codexBrand,
                usage: appState.codex,
                status: appState.codexStatus,
                authHint: "Log in with the Codex CLI: run `codex` and sign in."
            )
        }
        .padding(GlassLayout.rim)
        .frame(width: 340)
        .ignoresSafeArea(edges: .top)
        .background(GlassBackdrop())
    }
}

// MARK: - ProviderCard

/// One provider's glass card: branded title, then a row per window.
private struct ProviderCard: View {
    let title: String
    var topInset: CGFloat = 0
    let symbol: String
    let tint: Color
    let usage: ProviderUsage
    let status: ProviderStatus
    /// Shown under the title when `status == .needsAuth`.
    let authHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .glassSurface(in: Circle(), tint: tint.opacity(0.2))
                Text(title)
                    .font(.title3.weight(.semibold))
            }

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
                    resetAt: usage.currentResetAt,
                    tint: tint
                )
                WindowRow(
                    label: "Weekly",
                    percent: usage.weeklyPercent,
                    resetAt: usage.weeklyResetAt,
                    tint: tint
                )
            }
        }
        .padding(16)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: GlassLayout.cardRadius, style: .continuous)
        )
    }
}

// MARK: - WindowRow

/// A single window row: label, a used/remaining bar, and a reset countdown.
private struct WindowRow: View {
    let label: String
    let percent: Int?
    let resetAt: Date?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            UsageBar(fraction: Double(percent ?? 0) / 100, color: color)
            HStack {
                Text(remainingText)
                Spacer()
                Text(resetText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: percent)
    }

    private var percentText: String {
        percent.map { "\($0)%" } ?? "–%"
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
        default: tint
        }
    }
}

// MARK: - UsageBar

/// A capsule meter with a soft glow on the filled part.
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.65), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * min(1, max(0, fraction))))
                    .shadow(color: color.opacity(0.45), radius: 6)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) percent used")
    }
}
