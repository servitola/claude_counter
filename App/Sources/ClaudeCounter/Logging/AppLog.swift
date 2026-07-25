import Foundation
internal import os

/// Single facade over `os.Logger`. Reasons:
/// 1. NSLog from a non-Apple-signed bundle is filtered out of unified
///    logging in macOS 14+. `Logger` works because we declare a stable
///    subsystem and the messages get tagged with our bundle id.
/// 2. Centralising lets us swap to `OSLogStore` queries or file output
///    without touching call sites.
/// 3. SwiftLint's `no_nslog` rule fails the build if anyone reaches for
///    NSLog again.
enum AppLog {
    private static let subsystem = "com.servitola.claudecounter"

    static let scraper = Logger(subsystem: subsystem, category: "scraper")
    static let codex = Logger(subsystem: subsystem, category: "codex")
    static let blocker = Logger(subsystem: subsystem, category: "blocker")
    static let loginItem = Logger(subsystem: subsystem, category: "login")
    static let cli = Logger(subsystem: subsystem, category: "cli")
}
