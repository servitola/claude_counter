# Changelog

What changed for someone who uses the app. `scripts/release.sh bump` turns `Unreleased` into a
version, so keep that heading as it is.

## Unreleased

## 1.3.0 — 2026-10-01

### Changed
- Requires macOS 26. The macOS 15 look-alike of Liquid Glass is gone; Homebrew keeps 1.2.1 on
  older systems.

## 1.2.1 — 2026-10-01

### Fixed
- The Usage and Settings windows reopen exactly where they were left; the Usage window used to
  creep 33 pt up on every launch.
- The Codex account ID is no longer sent along if chatgpt.com ever redirects to another host.

### Changed
- Settings hides what would do nothing: the Claude / Codex / Both choice is disabled under the
  Custom preset (the template names its providers), and Separator shows only for both providers.
- Keyboard focus on the preset rows follows their rounded shape, like the provider pills.

## 1.2.0 — 2026-10-01

### Added
- A desktop widget, small and medium: Claude and Codex, the 5-hour and weekly windows, the time to
  reset ticking every minute. It fades and shows a clock when the app has not updated it for ten
  minutes; clicking it opens the Usage window.

## 1.1.1 — 2026-10-01

### Added
- Homebrew links a `claude-counter` command: `claude-counter --json` prints the current numbers.

### Fixed
- The Settings window no longer opens taller than the screen. 1.1.0 sized it to its whole scrolling
  content; a window it saved that way is not restored.

### Changed
- Settings content fades into the window edge when scrolled instead of being cut off under the
  window buttons.
- Keyboard focus on the Claude / Codex / Both pills is a capsule outline instead of the system ring.

## 1.1.0 — 2026-09-30

### Changed
- Settings and Usage windows redone in Liquid Glass: the window is see-through, the content sits on
  frosted cards, the provider switch is a row of tinted pills, presets carry a one-line description,
  usage bars glow in the provider's colour. On macOS 15 a blurred material stands in for the glass.
- Release builds are notarized by Apple, so Gatekeeper opens them without the quarantine workaround.

## 1.0.0 — 2026-09-05

### Added
- Menu-bar title with Claude's 5-hour window, time to reset and weekly percentage, refreshed every
  minute straight from claude.ai with the session you log in with once.
- Codex usage next to Claude's, read with your local Codex CLI login.
- Title presets (full, weekly only, session only, weekly with a session alert) and a custom template
  with tokens and colour thresholds.
- Usage window with both providers, Launch at Login, Refresh Now.
- `ClaudeCounter --json` prints the current snapshot for scripts.
