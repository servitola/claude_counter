import Foundation
import Testing
@testable import ClaudeCounter

// MARK: - CodexTokenRefresherTests

/// A fake `codex` is a shell script that records what it was sent and answers
/// like the app-server would.
struct CodexTokenRefresherTests {
    private func fakeCodex(_ body: String) throws -> (executable: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("codex")
        try "#!/bin/sh\ncd \"$(dirname \"$0\")\"\n\(body)\n".write(
            to: script,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, dir)
    }

    private static let answersOK = """
    echo "$@" > args
    read one; read two; read three
    printf '%s\\n' "$three" > request
    echo '{"jsonrpc":"2.0","id":1,"result":{}}'
    echo '{"jsonrpc":"2.0","id":2,"result":{"account":{"type":"chatgpt"}}}'
    sleep 30
    """

    @Test func renewal_succeeds_when_codex_answers_account_read() async throws {
        let fake = try fakeCodex(Self.answersOK)
        defer { try? FileManager.default.removeItem(at: fake.dir) }

        let started = Date()
        #expect(await CodexTokenRefresher.run(fake.executable, timeout: 10))
        #expect(Date().timeIntervalSince(started) < 5)

        let request = try String(
            contentsOf: fake.dir.appendingPathComponent("request"),
            encoding: .utf8
        )
        #expect(request.contains(#""method":"account/read""#))
        #expect(request.contains(#""refreshToken":true"#))
        let args = try String(contentsOf: fake.dir.appendingPathComponent("args"), encoding: .utf8)
        #expect(args.trimmingCharacters(in: .newlines) == "-s read-only -a never app-server")
    }

    @Test func renewal_fails_when_codex_answers_with_an_error() async throws {
        let fake = try fakeCodex("""
        read one; read two; read three
        echo '{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"refresh token expired"}}'
        sleep 30
        """)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        #expect(await !CodexTokenRefresher.run(fake.executable, timeout: 10))
    }

    @Test func renewal_gives_up_when_codex_never_answers() async throws {
        let fake = try fakeCodex("sleep 30")
        defer { try? FileManager.default.removeItem(at: fake.dir) }

        let started = Date()
        #expect(await !CodexTokenRefresher.run(fake.executable, timeout: 0.5))
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func renewal_fails_when_codex_exits_without_answering() async throws {
        let fake = try fakeCodex("exit 1")
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        #expect(await !CodexTokenRefresher.run(fake.executable, timeout: 10))
    }

    @Test func a_failed_renewal_is_not_retried_within_the_cooldown() async throws {
        let fake = try fakeCodex("echo run >> runs\nexit 1")
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let clock = Clock()
        let refresher = CodexTokenRefresher(executable: fake.executable) { clock.now }

        #expect(await !refresher.refresh())
        #expect(await !refresher.refresh())
        clock.now += CodexTokenRefresher.cooldown + 1
        #expect(await !refresher.refresh())

        let runs = try String(contentsOf: fake.dir.appendingPathComponent("runs"), encoding: .utf8)
        #expect(runs.split(separator: "\n").count == 2)
    }

    @Test func without_codex_installed_renewal_fails_quietly() async {
        #expect(await !CodexTokenRefresher(executable: nil).refresh())
    }

    @Test func codex_is_found_on_the_path() throws {
        let fake = try fakeCodex("exit 0")
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let found = CodexTokenRefresher.locateCodex(environment: ["PATH": fake.dir.path])
        // A real codex in /opt/homebrew/bin wins over PATH, as in the app.
        #expect(found != nil)
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Date(timeIntervalSince1970: 1_800_000_000)

        var now: Date {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }
}
