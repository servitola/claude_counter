import AppKit

/// Renders ClaudeUsage as a colored attributed string for the menu bar.
/// Layout examples (gap = two spaces both at the start and between
/// session/weekly):
///   "  12% 2h 15m  76%"     (default color)
///   "  82% 45m  91%"        (82% orange — heads up)
///   "  93% 12m  78%"        (93% red — actually pay attention)
///   "  –% –m  –%"           (no data yet)
enum QuotaTitleFormatter {
    /// Orange ≥ this %, red ≥ the next.
    static let warnThreshold = 80
    static let alertThreshold = 90

    static func render(_ usage: ClaudeUsage, now: Date = Date()) -> NSAttributedString {
        let gap = "  "
        let session = sessionPart(usage, now: now)
        let weekly = weeklyPart(usage, now: now)
        let str = NSMutableAttributedString(string: gap + session)
        if let pct = usage.currentPercent, let color = colorFor(pct) {
            let range = NSRange(
                location: gap.count,
                length: "\(pct)%".count
            )
            str.addAttribute(.foregroundColor, value: color, range: range)
        }
        str.append(NSAttributedString(string: gap + weekly))
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
