import Foundation

/// The port name both sides agree on. Scoped to the bundle id so it never
/// collides with another app's Mach ports. `String` (not `CFString`) so it is
/// `Sendable`; cast to `CFString` at the two `CFMessagePort` call sites.
let kStatusPortName = "com.servitola.claudecounter.status"

// MARK: - StatusServer

/// Local IPC responder hosted by the running menu-bar app. Answers each
/// request with the current usage snapshot as JSON — the exact bytes
/// `StatusExport` produces — over a Mach `CFMessagePort`.
///
/// Why this and not a file or a TCP port: the snapshot the app already holds
/// in memory (refreshed on the 60 s tick) is the freshest data available, and
/// only the running app can read the WebKit cookie store reliably (a headless
/// second process blocks on `WKWebsiteDataStore.default()`). A `CFMessagePort`
/// is pull-only (nothing happens without a request), opens no network port,
/// and writes nothing to disk. `ClaudeCounter --json` is the client.
@MainActor
final class StatusServer {
    private let appState: AppState
    // Held for the app's lifetime; releasing the port unregisters the name.
    // periphery:ignore
    private var port: CFMessagePort?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Register the local port and wire it to the main run loop. Best-effort:
    /// if the name is already taken (a stale instance) registration fails and
    /// the app simply runs without the export surface rather than crashing.
    func start() {
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(appState).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard
            let port = CFMessagePortCreateLocal(
                nil, kStatusPortName as CFString, statusPortCallback, &context, nil
            )
        else {
            AppLog.cli.error("status port registration failed")
            return
        }
        self.port = port
        if let source = CFMessagePortCreateRunLoopSource(nil, port, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        AppLog.cli.debug("status port registered")
    }
}

/// C-compatible callback: runs on the main run loop (where the port source is
/// installed), so touching the `@MainActor` `AppState` is safe. Returns the
/// encoded snapshot; a `nil` reply signals an internal encode failure to the
/// client. `info` carries the unretained `AppState` from the port context.
private func statusPortCallback(
    _: CFMessagePort?,
    _: Int32,
    _: CFData?,
    _ info: UnsafeMutableRawPointer?
)
    -> Unmanaged<CFData>?
{
    guard let info else { return nil }
    let appState = Unmanaged<AppState>.fromOpaque(info).takeUnretainedValue()
    let (usage, codex) = MainActor.assumeIsolated { (appState.usage, appState.codex) }
    guard let data = try? StatusExport.encode(usage, codex: codex) else { return nil }
    return Unmanaged.passRetained(data as CFData)
}
