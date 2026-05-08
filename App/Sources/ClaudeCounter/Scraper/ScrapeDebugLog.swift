import Foundation

/// Writes the latest scrape result to a fixed file under
/// `~/Library/Logs/ClaudeCounter/scrape-debug.txt`. Unified logging
/// filters non-Apple-signed bundles aggressively, so this file is the
/// only runtime visibility we get on user machines when something goes
/// wrong with claude.ai's markup.
///
/// Pure path resolution lives on the type so it's unit-testable;
/// the actual write is on an instance bound to a directory.
struct ScrapeDebugLog {
    let directory: URL
    let filename: String

    static let `default` = Self(
        directory: defaultDirectory(),
        filename: "scrape-debug.txt"
    )

    var fileURL: URL {
        directory.appendingPathComponent(filename)
    }

    /// `~/Library/Logs/ClaudeCounter/`. Falls back to the temp directory
    /// only if the user's Library isn't reachable for some reason — that
    /// path never fails to resolve, so we always end up with a usable URL.
    static func defaultDirectory() -> URL {
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first
        let target = library?.appendingPathComponent("Logs/ClaudeCounter")
        return target ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    func write(_ contents: String) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
