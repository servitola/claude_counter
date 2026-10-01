# Changelog

What changed for someone who uses the app. `scripts/release.sh bump` turns `Unreleased` into a
version, so keep that heading as it is.

## Unreleased

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
