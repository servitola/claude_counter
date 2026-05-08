import AppKit

/// Renders ClaudeUsage as a colored attributed string for the menu bar.
/// Layout examples:
///   "  12% 2h 15m   76%"
///   "  82% 45m   91%"     (82% colored orange)
///   "  –% –m   –%"        (no data yet)
enum QuotaTitleFormatter {
    static func render(_ usage: ClaudeUsage, now: Date = Date()) -> NSAttributedString {
        let gap = "  "
        let session = sessionPart(usage, now: now)
        let weekly = weeklyPart(usage)
        let str = NSMutableAttributedString(string: gap + session)
        if let pct = usage.currentPercent, pct > 80 {
            let range = NSRange(
                location: gap.count,
                length: "\(pct)%".count
            )
            str.addAttribute(
                .foregroundColor, value: NSColor.systemOrange, range: range
            )
        }
        str.append(NSAttributedString(string: gap + weekly))
        return str
    }

    private static func sessionPart(_ u: ClaudeUsage, now: Date) -> String {
        let pct = u.currentPercent.map { "\($0)%" } ?? "–%"
        return "\(pct) \(formatRemaining(u.currentResetAt, now: now))"
    }

    private static func weeklyPart(_ u: ClaudeUsage) -> String {
        u.weeklyPercent.map { "\($0)%" } ?? "–%"
    }

    /// "1h 23m" / "45m" / "0m" / "–m" depending on the date.
    static func formatRemaining(_ resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt else { return "–m" }
        let secs = resetAt.timeIntervalSince(now)
        let mins = max(0, Int(secs / 60))
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(mins)m"
    }
}
