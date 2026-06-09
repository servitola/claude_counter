import Foundation
import Testing
@testable import ClaudeCounter

struct ScrapeDebugLogTests {
    @Test func defaultDirectoryUsesUserLibraryLogs() {
        let dir = ScrapeDebugLog.defaultDirectory()
        let path = dir.path
        #expect(path.contains("Library/Logs/ClaudeCounter"))
    }

    @Test func writeRoundTripsThroughFileURL() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCounterTests-\(UUID().uuidString)")
        let log = ScrapeDebugLog(directory: temp, filename: "out.txt")
        defer { try? FileManager.default.removeItem(at: temp) }

        log.write("hello debug")
        ScrapeDebugLog.logQueue.sync {} // drain async write before reading

        let read = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(read == "hello debug")
    }

    @Test func writeCreatesMissingDirectory() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCounterTests-\(UUID().uuidString)")
            .appendingPathComponent("nested/deeper")
        let log = ScrapeDebugLog(directory: temp, filename: "out.txt")
        defer {
            try? FileManager.default.removeItem(at: temp.deletingLastPathComponent())
        }

        log.write("created via mkdir -p")
        ScrapeDebugLog.logQueue.sync {} // drain async write before checking

        let exists = FileManager.default.fileExists(atPath: log.fileURL.path)
        #expect(exists == true)
    }
}
