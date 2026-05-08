# Claude Counter — macOS Menu Bar Quota Tracker

Native macOS menu bar app (Swift 6 / AppKit, macOS 15+) that scrapes
`claude.ai/settings/usage` in a hidden WKWebView every 60 seconds and
displays the current 5h-window % and weekly % directly in the menu bar.

## Quick Start

```bash
make build         # debug build
make run           # release build, install to /Applications, launch
make kill          # kill running instance
```

First launch: open the menu bar item → **Open Usage Page**, log into
`claude.ai`. Cookies persist in `~/Library/WebKit/com.servitola.claudecounter/`
so login survives restarts.

## Architecture

```
NSStatusItem (menu bar)
    │  attributedTitle = "12% 45m   76%"
    │  click → NSMenu (Open / Launch at Login / Refresh / Quit)
    ▼
StatusBarController — observes AppState.usage (Observation)
    │
AppState (@Observable) ◄──── QuotaScraper (60s timer, hidden WKWebView)
    │                          loads claude.ai/settings/usage,
    │                          runs JS regex, parses %s
    ▼
UsageWindow (visible NSWindow, traffic-light buttons)
    └─ WKWebView shares WKWebsiteDataStore.default() with scraper
```

## Directory Layout

```
claude_counter/
├── Makefile
├── scripts/build-app.sh
└── App/
    ├── Package.swift
    └── Sources/ClaudeCounter/
        ├── ClaudeCounterApp.swift          # @main + AppDelegate
        ├── AppState.swift
        ├── Models/ClaudeUsage.swift
        ├── Scraper/
        │   ├── QuotaScraper.swift          # main type
        │   ├── QuotaScraper+Navigation.swift
        │   ├── QuotaScraper+JS.swift       # extraction script
        │   ├── QuotaScraper+Extract.swift
        │   ├── QuotaScraper+Parse.swift
        │   └── WebViewFactory.swift        # shared persistent data store
        ├── StatusBar/
        │   ├── StatusBarController.swift
        │   ├── StatusBarController+Menu.swift
        │   └── QuotaTitleFormatter.swift
        ├── UI/
        │   ├── UsageWindow.swift           # NSWindow with WebView
        │   └── WebViewCoordinator.swift    # OAuth popup handling
        └── LoginItem/LoginItemManager.swift  # SMAppService wrapper
```

## Auth & Persistence

`WKWebsiteDataStore.default()` is shared between the hidden scraper
WebView and the visible window WebView. Logging in via the visible
window also authenticates the scraper — same cookies, same origin.

Login Items are managed via `SMAppService.mainApp` (macOS 13+). The
toggle in the status menu shows in System Settings → General → Login
Items as "Claude Counter".

## How Scraping Works

1. `QuotaScraper.start()` schedules a 60s timer.
2. On each tick, a hidden 1×1 WKWebView loads `claude.ai/settings/usage`.
3. After page finishes loading, wait 3s for the SPA to render.
4. Run `QuotaScraper.extractionJS` — collects all `\d+% used` text matches
   and `[role=progressbar]` aria-valuenow values.
5. Index 0 → current 5h %, index 1 → weekly %. Reset minutes parsed
   from "Resets in Xh Ym" text.
6. Update `AppState.usage`. The status bar title re-renders via
   `withObservationTracking`.

If `claude.ai/login` is detected, the scraper skips silently — the user
must log in via the visible window first.

## Code Rules

- Atomic commits, never `git add -A`.
- AppKit is the source of truth (no SwiftUI scenes — pure NSStatusItem +
  NSWindow). SwiftUI's `MenuBarExtra` is too restrictive for arbitrary
  attributed titles.
- All reads from claude.ai are passive — no API calls, no writes.
