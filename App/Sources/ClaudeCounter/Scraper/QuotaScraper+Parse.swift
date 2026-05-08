import Foundation

extension QuotaScraper {
    func parse(_ dict: [String: Any]) -> ClaudeUsage? {
        guard (dict["found"] as? Bool) == true else { return nil }
        let textPcts = dict["percentages"] as? [Double] ?? []
        let barPcts = dict["barPercents"] as? [Double] ?? []
        let current = textPcts.first ?? barPcts.first
        let weekly = textPcts.count > 1
            ? textPcts[1]
            : (barPcts.count > 1 ? barPcts[1] : nil)
        let mins = (dict["resetMinutes"] as? Double).map { Int($0) }
            ?? (dict["resetMinutes"] as? Int)
        let resetAt = mins.map {
            Date().addingTimeInterval(TimeInterval($0 * 60))
        }
        return ClaudeUsage(
            currentPercent: current.map { Int($0) },
            weeklyPercent: weekly.map { Int($0) },
            currentResetAt: resetAt,
            updatedAt: Date()
        )
    }
}
