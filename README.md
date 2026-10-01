# Claude Counter

[![CI](https://github.com/servitola/claude_counter/actions/workflows/ci.yml/badge.svg)](https://github.com/servitola/claude_counter/actions/workflows/ci.yml) [![release](https://img.shields.io/github/v/release/servitola/claude_counter?color=black)](https://github.com/servitola/claude_counter/releases) [![brew test-bot](https://github.com/servitola/homebrew-tap/actions/workflows/tests.yml/badge.svg)](https://github.com/servitola/homebrew-tap/actions/workflows/tests.yml) ![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black) [![licence](https://img.shields.io/github/license/servitola/claude_counter?color=black)](LICENSE)

<p align="center"><img src="docs/images/hero.png" alt="The Usage window and the Settings window in Liquid Glass over a colourful desktop: Claude and Codex cards with glowing usage bars, and the menu-bar title preview" width="85%"></p>

How much of your Claude and Codex limits is left, in the menu bar.

```
                                  9% 2h 28m  26%  ·  7% 51%   🔋  📶  21:53
                                  ^^^^^^^^^^^^^^^^^^^^^^^^^
                                  Claude: 5-hour %, time to reset, weekly %  ·  Codex
```

Refreshed every minute, straight from claude.ai and chatgpt.com, with the logins you already have.
About 14 MB of memory at rest. No telemetry.

## Why

Claude counts your usage in a 5-hour window and a weekly one, and both live three clicks deep in
Settings → Usage. Codex keeps its own. I kept running into the wall in the middle of work, so the
numbers went where the clock is.

## Install

```sh
brew install --cask servitola/tap/claude-counter
```

Apple silicon, macOS 15 or newer. The build is signed and notarized by Apple. `brew upgrade` brings
new versions.

Then:

1. Click the numbers in the menu bar → **Open Usage Page** and log in to claude.ai once (Google
   sign-in works). Close the window; the session stays across restarts.
2. For Codex, log in once with the Codex CLI: run `codex` in a terminal. The app reads that login
   from `~/.codex/auth.json`.
3. **Launch at Login** in the same menu, if you want it there after a reboot.

## What is in the menu

| | |
| --- | --- |
| **Open Usage Page** | claude.ai's own usage page, in a window that keeps you logged in |
| **Usage (Claude + Codex)** | both providers: 5-hour and weekly bars, what is left, when it resets |
| **Settings…** | which providers the title shows and how it is written |
| **Launch at Login**, **Refresh Now**, **Quit** | |

## The title

Settings chooses Claude, Codex or both, and one of the presets:

| Preset | Shows |
| --- | --- |
| Full | session %, time to reset, weekly % |
| Weekly only | weekly % |
| Session only | session % and its reset |
| Weekly + session alert | weekly %, coloured by how close Claude's session is to the limit |
| Custom | your own template |

A custom template mixes text with tokens: `{claude.session}`, `{claude.weekly}`,
`{claude.session.reset}`, `{claude.weekly.reset}` and the same four for `codex`. You pick what
gets coloured, by which percentage, and where orange and red begin.

## For scripts

`claude-counter --json` asks the running app for the numbers it holds and prints them. Homebrew
links the command; from a source build it is `/Applications/ClaudeCounter.app/Contents/MacOS/ClaudeCounter`.

```sh
claude-counter --json
```

```json
{
  "schemaVersion" : 2,
  "currentPercent" : 9,
  "currentResetAt" : "2026-09-30T23:40:00Z",
  "weeklyPercent" : 26,
  "weeklyResetAt" : "2026-10-03T19:00:00Z",
  "updatedAt" : "2026-09-30T18:51:30Z",
  "codex" : {
    "currentPercent" : 7,
    "weeklyPercent" : 51,
    ...
  }
}
```

The top-level fields are Claude, `codex` holds the same for Codex. A field that is not known yet
is absent; `schemaVersion` and `updatedAt` are always there. Exit `0` means the JSON on stdout is
valid; any other exit prints a one-line JSON error to stderr and nothing to stdout, `6` meaning the
app is not running. It talks to the app over a local Mach port: no network, no file, no open port.

## Privacy

- The app's own requests go to `claude.ai` for Claude and `chatgpt.com` for Codex. The claude.ai
  page in the Usage Page window, and the hidden one that passes a Cloudflare challenge, load what
  that page loads, minus a block list of analytics and trackers.
- The claude.ai session cookies stay in the app's own WebKit store, are sent only to `claude.ai`
  (dropped on any redirect elsewhere) and are never logged. The Codex token is read from the Codex
  CLI's file, sent as a bearer token to `chatgpt.com` and never logged.
- No telemetry, no analytics, no accounts.

## How it works

Every minute the app calls claude.ai's usage API with your session, and the Codex usage endpoint
with your CLI token. When Cloudflare wants a fresh challenge, a hidden web view opens once to pass
it, then the plain API calls resume; logged out, the app waits instead of retrying every minute.
The details, the architecture and the conventions are in [AGENTS.md](AGENTS.md).

## Uninstall

```sh
brew uninstall --cask claude-counter          # the app
brew uninstall --cask --zap claude-counter    # and its login, cookies and preferences
```

## Building from source

Xcode 26 (Swift 6.2, the macOS 26 SDK):

```sh
git clone https://github.com/servitola/claude_counter.git
cd claude_counter
make setup-cert   # once: a stable signing certificate, so macOS keeps the Login Item across rebuilds
make install      # build, sign, copy to /Applications, relaunch
make ci           # format, lint, build, tests, dead code
```

## Licence

[AGPL-3.0](LICENSE) © [servitola](https://github.com/servitola). For a commercial licence, open an issue.
