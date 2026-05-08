import Foundation
import Observation

/// Single source of truth for usage data shared across status bar + window.
@MainActor
@Observable
final class AppState {
    var usage: ClaudeUsage = .empty
}
