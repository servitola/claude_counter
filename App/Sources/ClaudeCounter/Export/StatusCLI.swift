import Foundation

/// Headless one-shot mode: `ClaudeCounter --json` prints the current usage
/// snapshot as JSON to stdout and exits — no menu bar, no timer, no window,
/// no network, no disk.
///
/// It is a pure IPC *client*: it asks the running menu-bar app for the
/// snapshot the app already holds (over the `CFMessagePort` `StatusServer`
/// hosts) and relays the reply. It deliberately does NOT fetch or touch the
/// WebKit cookie store itself — a headless process blocks on
/// `WKWebsiteDataStore.default()`, so the running app is the only reliable
/// reader.
///
/// Contract: exit `0` with a JSON object on stdout means valid data; any
/// non-zero exit writes a one-line JSON error to stderr and nothing to stdout
/// (so a caller can pipe stdout straight into a parser). Exit `6` specifically
/// means the app is not running.
enum StatusCLI {
    /// The flag that selects headless mode. Checked in `Main.main()` before any
    /// AppKit UI is created.
    static let flag = "--json"

    /// Round-trip timeout for the local IPC call. Generous — the reply is a
    /// synchronous main-run-loop hop, so it normally returns in single-digit ms.
    private static let timeout: CFTimeInterval = 2

    /// Query the running app and print its reply, then terminate.
    static func run() -> Never {
        guard let remote = CFMessagePortCreateRemote(nil, kStatusPortName as CFString) else {
            fail("app_not_running", code: 6)
        }
        defer { CFMessagePortInvalidate(remote) }

        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remote, 0, nil, timeout, timeout,
            CFRunLoopMode.defaultMode.rawValue, &reply
        )
        guard status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() else {
            fail("ipc_error_\(status)", code: 7)
        }

        FileHandle.standardOutput.write(data as Data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }

    /// Write a `{"error":"…"}` line to stderr and exit non-zero. stdout stays
    /// empty so a consumer can safely pipe stdout straight into a JSON parser.
    private static func fail(_ reason: String, code: Int32) -> Never {
        let line = "{\"schemaVersion\":\(StatusExport.schemaVersion),\"error\":\"\(reason)\"}\n"
        FileHandle.standardError.write(Data(line.utf8))
        exit(code)
    }
}
