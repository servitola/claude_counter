# Backlog

What is left, most pressing first. State as of 2026-10-01; delete a line when it is done.

## Features
- A macOS widget (WidgetKit) with the same numbers as the Usage window: Claude and Codex, the
  5-hour and weekly windows, percent used and time to reset. Small and medium sizes. A widget is a
  separate extension target with its own sandbox, so it cannot read the WebKit cookie store: the
  app has to hand it the snapshot (an App Group container, the same JSON `StatusExport` produces)
  and reload its timeline after each fetch. SwiftPM alone does not build an app extension; this
  likely needs an Xcode project or a hand-assembled `.appex` in `build-app.sh`.
- The Usage window should open where the user last left it, not in the middle of the screen.
  `UsageOverviewWindow` calls `center()` and then `setFrameAutosaveName`, and the frame is set
  again when the hosting controller sizes the window to its content; find which of these wins,
  with evidence, before changing anything.

## UI
- Never looked at: the light theme, and the macOS 15 fallback (material instead of Liquid Glass).
- The settings window's scroll fade is untested with the glass cards under the mask.
- README has no screenshot yet. The windows are see-through, so a capture shows whatever is behind
  them: shoot on an otherwise empty desktop (another Space) with a neutral backdrop.
- Title format: the token buttons append at the end of the template instead of inserting at the
  cursor (SwiftUI's TextField exposes no cursor position; needs an NSTextView bridge).
