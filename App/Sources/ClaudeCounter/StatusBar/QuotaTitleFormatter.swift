import AppKit

/// Renders ClaudeUsage as a colored attributed string for the menu bar.
/// Layout examples (gap = two spaces both at the start and between
/// session/weekly):
///   "  12% 2h 15m  76%"     (default color)
///   "  82% 45m  91%"        (82% orange — heads up)
///   "  93% 12m  78%"        (93% red — actually pay attention)
///   "  0% 6d 7h"            (only a weekly window — e.g. idle Codex)
///   "  –% –m  –%"           (no data yet)
enum QuotaTitleFormatter {
    /// Orange ≥ this %, red ≥ the next.
    static let warnThreshold = 80
    static let alertThreshold = 90

    /// Compose the menu-bar strip for the selected provider(s). `.both` renders
    /// the two provider strips (Claude first, Codex second — no letter labels,
    /// the order is fixed) joined by a middle dot, e.g.
    /// "  12% 2h  76%  ·  0% 6d".
    static func render(
        claude: ProviderUsage,
        codex: ProviderUsage,
        mode: ProviderDisplayMode,
        now: Date = Date()
    )
        -> NSAttributedString
    {
        switch mode {
        case .claude:
            return render(claude, now: now)

        case .codex:
            return render(codex, now: now)

        case .both:
            let result = NSMutableAttributedString()
            result.append(render(claude, now: now))
            result.append(NSAttributedString(string: "  ·"))
            result.append(render(codex, now: now))
            return result
        }
    }

    static func render(_ usage: ClaudeUsage, now: Date = Date()) -> NSAttributedString {
        let gap = "  "
        let hasCurrent = usage.currentPercent != nil
        let hasWeekly = usage.weeklyPercent != nil

        // Fully empty (loading / logged out): keep the explicit placeholder so
        // the slot still reads as "no data yet" rather than going blank.
        guard hasCurrent || hasWeekly else {
            return NSAttributedString(string: "\(gap)–% –m\(gap)–%")
        }

        // Otherwise render only the windows the provider actually has — Codex on
        // a Plus plan reports just a weekly window when idle, so a "–% –m" 5-hour
        // placeholder would be noise.
        let str = NSMutableAttributedString(string: gap)
        if hasCurrent {
            let start = str.length
            str.append(NSAttributedString(string: sessionPart(usage, now: now)))
            if let pct = usage.currentPercent, let color = colorFor(pct) {
                str.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: start, length: "\(pct)%".count)
                )
            }
        }
        if hasWeekly {
            if hasCurrent {
                str.append(NSAttributedString(string: gap))
            }
            str.append(NSAttributedString(string: weeklyPart(usage, now: now)))
        }
        return str
    }

    private static func colorFor(_ pct: Int) -> NSColor? {
        switch pct {
        case alertThreshold...: .systemRed
        case warnThreshold...: .systemOrange
        default: nil
        }
    }

    private static func sessionPart(_ usage: ClaudeUsage, now: Date) -> String {
        let pct = usage.currentPercent.map { value in "\(value)%" } ?? "–%"
        return "\(pct) \(formatRemaining(usage.currentResetAt, now: now))"
    }

    private static func weeklyPart(_ usage: ClaudeUsage, now: Date) -> String {
        let pct = usage.weeklyPercent.map { "\($0)%" } ?? "–%"
        guard let resetAt = usage.weeklyResetAt else { return pct }
        return "\(pct) \(formatRemaining(resetAt, now: now))"
    }

    /// "4d 2h" / "1h 23m" / "45m" / "0m" / "–m" depending on the date.
    /// Weekly limits reset days out, so durations ≥ 1 day collapse to
    /// "Nd Hh" rather than an unwieldy hour count ("98h").
    static func formatRemaining(_ resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt else { return "–m" }
        let secs = resetAt.timeIntervalSince(now)
        let mins = max(0, Int(secs / 60))
        let dayMins = 24 * 60
        if mins >= dayMins {
            let days = mins / dayMins
            let h = (mins % dayMins) / 60
            return h > 0 ? "\(days)d \(h)h" : "\(days)d"
        }
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(mins)m"
    }
}
