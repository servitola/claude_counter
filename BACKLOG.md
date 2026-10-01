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

## Security
- `CodexUsageClient` sends the Codex bearer token with a plain `URLSession` and no redirect
  delegate. Whether Foundation drops `Authorization` on a redirect to another host is not
  verified; the Claude path has `OffHostRedirectGuard` for its cookies, Codex has nothing alike.

## UI
- Never looked at: the light theme, and the macOS 15 fallback (material instead of Liquid Glass).
- The settings window's scroll fade is untested with the glass cards under the mask.
- Title format: the Separator field is shown for single-provider presets where it does nothing;
  the token buttons append at the end of the template instead of inserting at the cursor.
