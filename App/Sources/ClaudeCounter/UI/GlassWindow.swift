import AppKit
import SwiftUI

extension NSWindow {
    /// Clear, borderless-looking chrome so `WindowGlass` can show the desktop
    /// behind the window instead of an opaque window background.
    func applyGlassChrome() {
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
    }
}

// MARK: - WindowGlass

/// Full-window glass pane. SwiftUI's `.clear` glass samples the desktop behind
/// a non-opaque window; an `NSVisualEffectView` blur and `NSGlassEffectView`
/// both rendered near-opaque there, hiding the see-through look.
struct WindowGlass: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear, in: Rectangle())
        } else {
            BehindWindowBlur()
        }
    }
}

// MARK: - BehindWindowBlur

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
