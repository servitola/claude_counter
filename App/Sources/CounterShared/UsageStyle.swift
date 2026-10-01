public import Foundation
public import SwiftUI

// MARK: - UsageStyle

/// Formatting and colours shared by the menu bar, the windows and the widget.
public enum UsageStyle {
    /// Percent used from which a number turns orange.
    public static let warnThreshold = 80
    /// Percent used from which a number turns red.
    public static let alertThreshold = 90

    /// "3d 4h", "2h 28m", "45m"; "–m" when the reset time is unknown.
    public static func remaining(until resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt else { return "–m" }
        let mins = max(0, Int(resetAt.timeIntervalSince(now) / 60))
        let dayMins = 24 * 60
        if mins >= dayMins {
            let days = mins / dayMins
            let hours = (mins % dayMins) / 60
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if mins >= 60 {
            let hours = mins / 60
            let rest = mins % 60
            return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
        }
        return "\(mins)m"
    }

    /// Orange from `warnThreshold`, red from `alertThreshold`, else `normal`.
    public static func color(for percent: Int?, normal: Color) -> Color {
        switch percent ?? 0 {
        case alertThreshold...: .red
        case warnThreshold...: .orange
        default: normal
        }
    }
}

public extension Color {
    /// Claude's terracotta.
    static let claudeBrand = Color(red: 0.85, green: 0.47, blue: 0.34)
    /// Codex's green.
    static let codexBrand = Color(red: 0.06, green: 0.64, blue: 0.50)
}
