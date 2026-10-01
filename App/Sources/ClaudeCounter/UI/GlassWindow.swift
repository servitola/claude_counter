import AppKit
import SwiftUI

extension NSWindow {
    /// Clear chrome so `WindowGlass` can show the desktop behind the window
    /// instead of an opaque window background.
    /// `sizesToContent: false` for scrolling content: its ideal size is the
    /// whole scroll height, which would grow the window past the screen.
    func applyGlassChrome(content: some View, sizesToContent: Bool = true) {
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        // An empty unified toolbar only makes the titlebar taller, which drops
        // the traffic lights from the top card's edge into its interior.
        toolbar = NSToolbar()
        toolbarStyle = .unified
        titlebarSeparatorStyle = .none
        let hosting = NSHostingController(rootView: content)
        // The top card runs under the titlebar; left on, the titlebar inset is
        // still counted in the window height and leaves an empty strip below.
        hosting.safeAreaRegions = []
        if !sizesToContent {
            hosting.sizingOptions = .minSize
        }
        contentViewController = hosting
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
