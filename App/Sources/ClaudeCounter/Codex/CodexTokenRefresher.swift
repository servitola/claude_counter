import Foundation

// MARK: - CodexTokenRefresher

/// Asks the Codex CLI to renew its own login. Codex owns `auth.json` and the
/// refresh token, which is single-use: renewing it here and writing the file
/// ourselves would race the CLI, and the loser of that race is signed out.
/// `account/read` with `refreshToken: true` makes Codex run its normal
/// refresh and write the file itself.
actor CodexTokenRefresher {
    static let shared = CodexTokenRefresher()

    /// A failed attempt is not retried sooner: without it a missing or broken
    /// `codex` would be spawned on every one-minute tick.
    static let cooldown: TimeInterval = 30 * 60
    static let timeout: TimeInterval = 20
    static let arguments = ["-s", "read-only", "-a", "never", "app-server"]

    private let executable: URL?
    private let now: @Sendable () -> Date
    private var lastFailure: Date?

    init(
        executable: URL? = CodexTokenRefresher.locateCodex(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.executable = executable
        self.now = now
    }

    /// True when Codex reported a successful renewal; the new token is then
    /// in `auth.json`.
    func refresh() async -> Bool {
        if let lastFailure, now().timeIntervalSince(lastFailure) < Self.cooldown {
            return false
        }
        let renewed: Bool = if let executable {
            await Self.run(executable, timeout: Self.timeout)
        } else {
            false
        }
        lastFailure = renewed ? nil : now()
        return renewed
    }

    /// A menu-bar app starts with launchd's PATH, which has none of the places
    /// Homebrew or npm put `codex`.
    static func locateCodex(
        environment: [String: String] = ProcessInfo.processInfo.environment
    )
        -> URL?
    {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fixed = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (fixed + path)
            .map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func run(_ executable: URL, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(executable, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ executable: URL, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // An npm-installed `codex` is a node script found through PATH.
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            environment["PATH"] ?? "/usr/bin:/bin"
        ]
        .joined(separator: ":")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let reply = ReplyWaiter()
        output.fileHandleForReading.readabilityHandler = { handle in
            reply.feed(handle.availableData)
        }
        input.fileHandleForWriting.write(requests)

        // Waiting on a semaphore, not on the pipe: a child of `codex` can keep
        // the pipe open after `codex` itself is gone.
        let renewed = reply.wait(timeout: timeout)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        return renewed
    }

    enum Reply {
        case renewed
        case refused
    }

    /// Nil for anything that is not the reply to request 2.
    static func reply(to line: Data) -> Reply? {
        guard
            let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            message["id"] as? Int == 2
        else {
            return nil
        }
        return message["error"] == nil && message["result"] != nil ? .renewed : .refused
    }

    static var requests: Data {
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","#
                + #""params":{"clientInfo":{"name":"claude-counter","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/read","params":{"refreshToken":true}}"#
        ]
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

// MARK: - ReplyWaiter

/// Collects the app-server's output lines from the pipe's handler queue and
/// wakes the waiting thread on the reply to request 2 or at end of output.
private final class ReplyWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var outcome: CodexTokenRefresher.Reply?

    func feed(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard outcome == nil else { return }
        guard !chunk.isEmpty else {
            finish(.refused)
            return
        }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex ..< newline]
            buffer.removeSubrange(buffer.startIndex ... newline)
            if let reply = CodexTokenRefresher.reply(to: Data(line)) {
                finish(reply)
                return
            }
        }
    }

    func wait(timeout: TimeInterval) -> Bool {
        guard done.wait(timeout: .now() + timeout) == .success else { return false }
        lock.lock()
        defer { lock.unlock() }
        return outcome == .renewed
    }

    private func finish(_ reply: CodexTokenRefresher.Reply) {
        outcome = reply
        done.signal()
    }
}
