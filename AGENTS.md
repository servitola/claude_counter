# Claude Counter — Agent Guide

A native macOS menu-bar app (Swift 6 / AppKit, macOS 15+) that scrapes
`claude.ai/settings/usage` once per minute and renders the result in
the menu bar. Single-binary SPM package, no Xcode project, no external
runtime dependencies beyond system frameworks.

## Repo layout

```
claude_counter/
├── Makefile                    # all developer commands
├── scripts/
│   ├── build-app.sh            # bundle assembly + codesign + install
│   └── setup-codesign-cert.sh  # one-time stable cert in login keychain
└── App/
    ├── Package.swift           # swift-tools 6.0, single executable target
    └── Sources/ClaudeCounter/
        ├── ClaudeCounterApp.swift   # @main, AppDelegate, accessory mode
        ├── AppState.swift           # @Observable, holds ClaudeUsage
        ├── Models/ClaudeUsage.swift
        ├── Scraper/
        │   ├── QuotaScraper.swift          # 60s timer + entry point
        │   ├── QuotaScraper+Lifecycle.swift # tearDown, watchdog, retry
        │   ├── QuotaScraper+Navigation.swift
        │   ├── QuotaScraper+Extract.swift   # JS eval + debug dump
        │   ├── QuotaScraper+Parse.swift
        │   ├── QuotaScraper+JS.swift        # the extraction script
        │   ├── ContentBlocker.swift         # WKContentRuleList
        │   └── WebViewFactory.swift
        ├── StatusBar/
        │   ├── StatusBarController.swift
        │   ├── StatusBarController+Menu.swift
        │   └── QuotaTitleFormatter.swift
        ├── UI/
        │   ├── UsageWindow.swift            # NSWindow with WebView
        │   └── WebViewCoordinator.swift     # OAuth popup handling
        └── LoginItem/LoginItemManager.swift # SMAppService wrapper
```

## Data flow

```
NSStatusItem ──► click ──► NSMenu (Open / Login / Refresh / Quit)
     ▲
     │ withObservationTracking re-renders title on every change
     │
AppState.usage  ◄────  QuotaScraper (60s Timer)
     │                       │  build hidden WKWebView (blockHeavy)
     │                       │  load claude.ai/settings/usage
     │                       │  +3s wait → evaluateJavaScript
     │                       │  parse → AppState.usage
     │                       └─ tearDown → WebContent XPC dies
     │
QuotaTitleFormatter  →  "  9% 2h 28m   26%"
```

`UsageWindow` is the visible window. It owns its own WKWebView with
`blockHeavy: false` (full content) and the **same**
`WKWebsiteDataStore.default()`, so when the user logs in there the
scraper picks up the cookies on the next tick.

## Hard rules — do not violate

- **Ephemeral scraper WebView.** Build → load → extract → tearDown.
  Never cache. Persistent WebView held the entire SPA in memory at
  ~700 MB. The whole optimization story rests on this.
- **AppKit only.** No `MenuBarExtra`, no SwiftUI scenes. SwiftUI's
  status bar API can't render arbitrary `NSAttributedString` titles
  with our color logic.
- **Stable code-signing cert.** TCC permissions and SMAppService
  Login Item registration are tied to the signature's certificate
  chain. Ad-hoc signing produces a fresh cdhash each build → macOS
  resets permissions. `make setup-cert` creates the cert once;
  `build-app.sh` detects and uses it automatically.
- **`WKWebsiteDataStore.default()` is shared.** Both the scraper and
  the visible window must use it. An ephemeral data store kills
  login.
- **Bundle ID stays `com.servitola.claudecounter`.** Changing it
  detaches existing TCC entries and Login Item registration.

## Build & deploy

```bash
make build         # debug, no install — fast inner loop
make setup-cert    # one-time per machine, creates self-signed cert
make install       # build + replace /Applications + relaunch if running
make update        # build + replace + always launch
make reinstall     # nuke /Applications/<app> then install
make uninstall     # remove app (cookies stay)
make purge         # uninstall + delete cookies and preferences
make verify-sign   # show installed signature identity
```

`scripts/build-app.sh` writes `Info.plist` inline (LSUIElement=true,
macOS 15 minimum). It picks the stable cert if present, falls back to
ad-hoc with a warning.

## Memory budget — the whole point

| State                          | Total RSS |
|--------------------------------|-----------|
| Idle (~99% of the time)        | **~76 MB** |
| Peak (~200 ms/minute)          | ~150 MB   |

If a change pushes idle above ~100 MB or makes the peak window last
longer than ~1 second, that change has regressed the core promise.
Verify with:

```bash
ps -A -o pid,rss,command | grep -iE '(ClaudeCounter|com\.apple\.WebKit)' \
    | awk '{sum+=$2} END {printf "%.1f MB\n", sum/1024}'
```

## Scraping internals

`claude.ai/settings/usage` is a React SPA. `body.innerText` is empty.
`QuotaScraper+JS.swift` walks the entire DOM, collects every
`aria-label` and direct text node, joins them with `|`, then runs:

1. `\d+\.?\d*\s*%\s*used` → array of percentages (index 0 = current
   5h, index 1 = weekly).
2. `[role="progressbar"][aria-valuenow]` → numeric fallback.
3. Six regex patterns for "Resets in Xh Ym" / "X minutes left".
4. Absolute time fallback "Resets at 9:30 PM" → minutes from now.

Resulting `ClaudeUsage` stores `currentResetAt: Date?` (not minutes)
so the menu-bar title's 60-second refresh ticks down without a fresh
scrape.

`/tmp/claude_counter_debug.txt` is rewritten on every scrape with
percentages, bar values, matched pattern, and the first 2000 chars of
aggregated text. NSLog from a non-Apple-signed bundle is filtered
out of unified logging — this file is the only runtime visibility.

## Content blocking

`ContentBlocker.shared.prewarm()` runs from
`applicationDidFinishLaunching`. It compiles a `WKContentRuleList`
that drops `image`, `font`, `media`, `popup`, `ping` resources plus
~15 analytics/RUM domains. Compilation is async (~50-200 ms) — the
first scrape may run unfiltered, every subsequent one is blocked.

The visible Usage window passes `blockHeavy: false` so login flows,
brand assets, and CAPTCHAs render normally.

## Common pitfalls

- **claude.ai changing markup** breaks regex matching. The block
  fallback (`[role=progressbar]`) covers the percentages but not the
  reset time — if the time disappears, check
  `/tmp/claude_counter_debug.txt` and adjust patterns in
  `QuotaScraper+JS.swift`.
- **First scrape after install runs unblocked.** Acceptable — adds
  ~70 MB for ~2 seconds, then steady-state.
- **`security import` PKCS12 password fails** unless `openssl pkcs12`
  is invoked with `-legacy`. Modern OpenSSL defaults to AES-256-CBC
  which `security` rejects.
- **Watchdog (30 s)** kills hung scrapes. Without it, a stuck
  WebContent process pins memory until next launch.
- **`@MainActor` everywhere in the scraper.** WKWebView and
  `Timer` callbacks must run on main; cross-actor hops are explicit
  via `Task { @MainActor in ... }`.

## Adding features

- **New menu item:** edit `StatusBarController+Menu.swift` only.
  Keep `@objc` methods on the controller, not in extensions in
  separate files (Swift's selector dispatch wants them visible).
- **New persisted setting:** `UserDefaults.standard` directly is
  fine for this app — no settings UI exists, and there's no
  preference panel planned. If preferences are added, route through
  a single `UserSettings` singleton.
- **Changing the scrape interval:** `QuotaScraper.interval`. Don't
  go below 30 s — claude.ai may rate-limit and the cost/benefit
  collapses.
