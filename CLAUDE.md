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

The scraper uses an **ephemeral WKWebView** — created at the start of
each scrape, torn down when extraction completes. Keeping the webview
alive between scrapes would pin a WebContent process holding the
entire claude.ai SPA in memory (~700 MB on idle machines).

1. `QuotaScraper.start()` schedules a 60s `Timer`.
2. Each tick: build a fresh hidden 1×1 WKWebView, load
   `claude.ai/settings/usage`, attach a 30s watchdog.
3. After `didFinish` (page loaded, not redirected to `/login`), wait 3s
   for the React tree to render.
4. Run `QuotaScraper.extractionJS` — walks all `aria-label` attributes
   and direct text nodes (claude.ai is shadow-DOM-heavy; `body.innerText`
   is empty). Collects `\d+% used` text matches and
   `[role=progressbar]` aria-valuenow fallbacks.
5. Index 0 → current 5h %, index 1 → weekly %. Reset minutes parsed
   from "Resets in Xh Ym" text.
6. Update `AppState.usage`. Call `tearDown()` — webview, navigation
   delegate, and watchdog dropped. The WebContent / Networking / GPU
   XPC services have no remaining references and exit on their own
   within ~5-10 seconds.
7. Status bar title re-renders via `withObservationTracking`.

If `claude.ai/login` is detected, the scrape is aborted — the user
must log in via the visible window first. Login state lives in the
shared `WKWebsiteDataStore.default()` cookies, so the scraper picks
it up on the next tick automatically.

### Memory Profile (M-series Mac, macOS 15)

| State                          | Total RSS |
|--------------------------------|-----------|
| Idle (between scrapes, ~58s/min) | ~76 MB    |
| Peak (during scrape, ~1s/min)    | ~150 MB   |

Original design (persistent WebView) used ~863 MB continuously.

### Content Blocking

`ContentBlocker` (compiled at startup) attaches a `WKContentRuleList`
to every scraper WebView. Blocked: `image`, `font`, `media`, `popup`,
`ping` resources, plus known analytics/RUM domains
(google-analytics, googletagmanager, doubleclick, segment, mixpanel,
intercom, hotjar, fullstory, heap, amplitude, logrocket, datadog,
sentry, newrelic).

Allowed: `document`, `script`, `style-sheet`, `raw`, `fetch`, `xhr`,
`websocket`. The page is a React SPA — JS is mandatory, the DOM tree
we read only exists after it executes.

The visible Usage window opts OUT of blocking (`blockHeavy: false`)
so login flows, brand assets, and CAPTCHAs render normally.

## Code Rules

- Atomic commits, never `git add -A`.
- AppKit is the source of truth (no SwiftUI scenes — pure NSStatusItem +
  NSWindow). SwiftUI's `MenuBarExtra` is too restrictive for arbitrary
  attributed titles.
- All reads from claude.ai are passive — no API calls, no writes.
