import AppKit
import SwiftUI

/// Owns one glass window: builds it on first `show`, then only brings it back.
/// Closing hides it (`isReleasedWhenClosed = false`), so its state and place
/// survive until the app quits; the autosave name carries the place across launches.
@MainActor
final class GlassWindowSlot {
    struct Spec {
        let title: String
        let size: NSSize
        let styleMask: NSWindow.StyleMask
        let autosaveName: String
        var sizesToContent = true
    }

    private let spec: Spec
    private var window: NSWindow?

    init(_ spec: Spec) {
        self.spec = spec
    }

    func show(_ content: () -> some View) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: spec.size),
            styleMask: spec.styleMask.union(.fullSizeContentView),
            backing: .buffered,
            defer: false
        )
        win.title = spec.title
        win.isReleasedWhenClosed = false
        win.applyGlassChrome(content: content(), sizesToContent: spec.sizesToContent)
        // After the chrome: the toolbar and the hosting controller resize the
        // frame, which shifted a frame restored before them 33 pt up per launch.
        win.center()
        win.setFrameAutosaveName(spec.autosaveName)
        window = win
        win.makeKeyAndOrderFront(nil)
    }
}
