# Claude Counter — Agent Guide

A native macOS menu-bar app (Swift 6 / AppKit, macOS 15+) that polls
Claude.ai usage once per minute and renders the result in the menu bar.
Single-binary SPM package, no Xcode project, no external runtime
dependencies beyond system frameworks.

**Primary path is a direct JSON API call over `URLSession`** to
`claude.ai/api/organizations/{uuid}/usage`, reusing the logged-in
cookies. A hidden WebView is only spun up as a *fallback* (Cloudflare
clearance refresh, login, or DOM-scrape if the API shape changes). On a
healthy session no WebView is created, so idle footprint sits at ~14 MB.
(History: the app used to DOM-scrape the SPA via a per-minute ephemeral
WebView — that path is retained as the fallback.)

## Repo layout

```
claude_counter/
├── Makefile                    # all developer commands (build/install/lint/test/ci)
├── .swiftlint.yml              # SwiftLint config — strict, opt-in heavy
├── .swiftformat                # SwiftFormat config — formatting source of truth
├── .periphery.yml              # Periphery config — dead code detection
├── .pre-commit-config.yaml     # pre-commit hook (gitleaks + Swift toolchain)
├── .github/workflows/ci.yml    # GitHub Actions: build · test · lint · format · dead-code
├── scripts/
│   ├── build-app.sh            # bundle assembly + codesign + install
│   └── setup-codesign-cert.sh  # one-time stable cert in login keychain
└── App/
    ├── Package.swift           # swift-tools 6.2, strict concurrency, warnings-as-errors
    ├── Sources/ClaudeCounter/
    │   ├── ClaudeCounterApp.swift     # @main, AppDelegate, accessory mode
    │   ├── AppState.swift             # @Observable, holds ClaudeUsage
    │   ├── Logging/AppLog.swift       # os.Logger facade (no NSLog allowed)
    │   ├── Models/ClaudeUsage.swift
    │   ├── Scraper/
    │   │   ├── QuotaScraper.swift           # 60s timer, state, entry point
    │   │   ├── QuotaScraper+Orchestrator.swift # API-first scrape(), fallback routing, backoff
    │   │   ├── UsageAPIClient.swift         # URLSession: discovery + /usage fetch
    │   │   ├── UsageResponseClassifier.swift # HTTP → UsageFetchResult (challenge/login/decode)
    │   │   ├── UsageAPIModels.swift         # Decodable: OrgSummary, UsageResponse, UsageLimit, FlatWindow
    │   │   ├── UsageMapper.swift            # pure: UsageResponse.limits[] → ClaudeUsage
    │   │   ├── CookieBridge.swift           # host-scoped read/write of WKWebsiteDataStore cookies
    │   │   ├── OffHostRedirectGuard.swift   # strips Cookie header on off-host redirect
    │   │   ├── OrgIDStore.swift             # UserDefaults cache of org uuid
    │   │   ├── QuotaScraper+Lifecycle.swift # tearDown, watchdog, retry (fallback WebView)
    │   │   ├── QuotaScraper+Navigation.swift # fallback WebView nav + /login detection
    │   │   ├── QuotaScraper+Extract.swift   # fallback: JS eval + debug dump
    │   │   ├── QuotaScraper+JS.swift        # fallback: the DOM extraction script
    │   │   ├── QuotaPayload.swift           # fallback: typed view over JS result
    │   │   ├── QuotaParser.swift            # fallback: pure QuotaPayload → ClaudeUsage
    │   │   ├── ScrapeDebugLog.swift         # fallback scrape dump to ~/Library/Logs
    │   │   ├── ContentBlocker.swift         # WKContentRuleList (fallback WebView)
    │   │   └── WebViewFactory.swift         # WKWebView factory + shared Safari UA
    │   ├── StatusBar/
    │   │   ├── StatusBarController.swift
    │   │   ├── StatusBarController+Menu.swift
    │   │   └── QuotaTitleFormatter.swift
    │   ├── UI/
    │   │   ├── UsageWindow.swift            # NSWindow with WebView (login)
    │   │   └── WebViewCoordinator.swift     # OAuth popup handling
    │   └── LoginItem/LoginItemManager.swift # SMAppService wrapper
    └── Tests/ClaudeCounterTests/            # Swift Testing; 100 tests / 14 suites
        ├── UsageAPIModelsTests, UsageMapperTests, OrgIDStoreTests, CookieBridgeTests
        ├── UsageAPIClientTests (+Classification, +TestSupport, StubURLProtocol)
        ├── QuotaScraperOrchestrationTests, QuotaScraperBackoffTests (+TestSupport)
        └── ClaudeUsageTests, QuotaParserTests, JSQuotaParserTests, QuotaPayloadTests, …
```

## Data flow

```
NSStatusItem ──► click ──► NSMenu (Open / Login / Refresh / Quit)
     ▲
     │ withObservationTracking re-renders title on every change
     │
AppState.usage ◄──── QuotaScraper (60s Timer) ──► scrape()  [+Orchestrator]
     │                    │
     │                    ├─ UsageAPIClient.fetch()  (URLSession, no cookie jar)
     │                    │    ├─ CookieBridge: read claude.ai cookies from WKWebsiteDataStore
     │                    │    ├─ OrgIDStore: cached uuid? else GET /api/organizations
     │                    │    ├─ GET /api/organizations/{uuid}/usage  (Safari UA + cookies)
     │                    │    └─ classify → UsageMapper.map(limits[]) → ClaudeUsage
     │                    │
     │                    └─ UsageFetchResult:
     │                         .success         → AppState.usage = …   (NO WebView)
     │                         .needsCookieRefresh / .decodeFailed → fallback WebView path
     │                         .notLoggedIn     → arm backoff (suppress fallback until re-probe)
     │                         .transport       → leave state untouched
     │
QuotaTitleFormatter → "  9% 2h 28m   26%"
```

The **fallback WebView path** is the old pipeline (QuotaScraper
+Navigation/+Extract/+JS → QuotaPayload → QuotaParser): build hidden
WKWebView → load `claude.ai/settings/usage` → poll DOM → parse →
tearDown. It refreshes Cloudflare/session cookies and DOM-scrapes when
the API can't answer.

`UsageWindow` is the visible login window. It owns its own WKWebView
(`blockHeavy: false`, full content) on the **same**
`WKWebsiteDataStore.default()`, so a login there is picked up by both
the API path (via CookieBridge) and the fallback on the next tick.

## Hard rules — do not violate

- **API-first; WebView is fallback only.** The 60s tick must go through
  `UsageAPIClient` (URLSession). Only `.needsCookieRefresh` /
  `.decodeFailed` may spin a WebView. Instantiating a WebView on the
  happy path reintroduces the ~700 MB-class WebContent process the whole
  optimization story removed.
- **URLSession owns no cookie jar.** `httpCookieStorage = nil`,
  `httpCookieAcceptPolicy = .never`, `httpShouldSetCookies = false`.
  Cookies come *only* from `CookieBridge` per request. A jar would drift
  from the WebView store (the single source of truth).
- **Cookies are claude.ai-scoped and never logged.** `CookieBridge`
  filters to exact `claude.ai` host (rejects lookalikes);
  `OffHostRedirectGuard` strips the `Cookie` header on any off-host
  redirect; no log line ever contains a cookie name or value
  (`privacy: .private` / counts-only). Session token handling lives here
  — treat changes as security-sensitive.
- **Logged-out backoff persists across ticks.** `.notLoggedIn` arms the
  `loggedOut` flag; the automatic timer must NOT clear it (else the
  WebView fallback would relaunch every minute). It clears only on an
  explicit re-probe (`forceRefresh()` from wake / Refresh Now / window
  open) or a `.success`.
- **Ephemeral fallback WebView.** When the fallback does run: build →
  load → extract → tearDown. Never cache a persistent WebView.
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
make ship          # update + git clean -dfx (frees ~212 MB build cache)
make reinstall     # nuke /Applications/<app> then install
make uninstall     # remove app (cookies stay)
make purge         # uninstall + delete cookies and preferences
make verify-sign   # show installed signature identity
```

## Quality gates

```bash
make test           # swift test (100 tests / 14 suites, Swift Testing, no live network)
make lint           # SwiftLint --strict (treats warnings as errors)
make lint-fix       # auto-fix what SwiftLint can
make format         # SwiftFormat — rewrite sources in place
make format-check   # CI-safe: error if anything would change
make dead-code      # Periphery scan in --strict mode
make ci             # everything above, in failure-fast order
make hooks-install  # install pre-commit hook (lint + format + build + test + gitleaks)
```

CI in `.github/workflows/ci.yml` runs the same `make ci` on `macos-15`.

Compiler is also strict:
- `swift-tools 6.2`
- `treatAllWarnings(as: .error)`
- `enableExperimentalFeature("StrictConcurrency")`
- Upcoming features: `ExistentialAny`, `InternalImportsByDefault`,
  `InferIsolatedConformances`, `NonisolatedNonsendingByDefault`

`scripts/build-app.sh` writes `Info.plist` inline (LSUIElement=true,
macOS 15 minimum). It picks the stable cert if present, falls back to
ad-hoc with a warning.

## Memory budget — the whole point

Measure `phys_footprint` (what Activity Monitor's "Memory" column shows),
not RSS — RSS includes shared framework pages that don't count against
the app.

| State                                   | phys_footprint |
|-----------------------------------------|----------------|
| Idle, API path (~99% of the time)       | **~14 MB**     |
| Fallback WebView active (brief)         | spikes, then returns |

On the API path no WebContent/GPU helper spawns and WebKit/JSC ideally
stay dormant. If idle footprint climbs back toward the old ~80 MB, or a
WebContent process appears every tick, the API path has regressed (likely
something forcing the WebView). Verify with:

```bash
PID=$(pgrep -x ClaudeCounter)
vmmap --summary $PID | grep "Physical footprint:"
# and confirm no per-tick helper:
ps -axo pid,comm | grep -i "WebKit.WebContent"
```

Note: `CookieBridge` reading `WKWebsiteDataStore` and `purgeResourceCache`
on launch still initialize WebKit in-process today (a known residual ~few
MB + a Networking XPC); eliminating that needs a no-WebKit cookie read and
was deliberately left out (see work/completed/api-scraper for the analysis).

## Fetch internals

### Primary: JSON API (`UsageAPIClient`)

1. **Discovery** — `GET /api/organizations` → first org `uuid`, cached in
   `OrgIDStore` (UserDefaults), re-discovered on auth/not-found failure.
   The uuid is UUID-validated before being interpolated into the path.
2. **Fetch** — `GET /api/organizations/{uuid}/usage` with the shared
   Safari UA (`WebViewFactory.safariUserAgent`) and CookieBridge cookies.
   `URLSession` (system TLS) passes Cloudflare where curl gets 403 — that
   fingerprint difference is *why* this can't be a shelled-out HTTP call.
3. **Classify** (`UsageResponseClassifier`, shared by discovery + usage,
   runs before JSON decode): 403 + "Just a moment…" challenge →
   `.needsCookieRefresh`; 401 / `/login` redirect / 200-login-page body →
   `.notLoggedIn`; other non-200 → `.decodeFailed`.
4. **Map** (`UsageMapper`): `limits[]` entry `kind == "session"` → current,
   `kind == "weekly_all"` (never `weekly_scoped`) → weekly; `resets_at`
   ISO-8601 → `Date` straight through; flat `five_hour`/`seven_day` are
   the fallback fields. `percent` (Double) truncates to Int.

`ClaudeUsage` stores `currentResetAt: Date?` (not minutes) so the
menu-bar title's 60-second refresh ticks down without a fresh fetch.

### Fallback: DOM scrape (only when the API can't answer)

`claude.ai/settings/usage` is a React SPA (`body.innerText` is empty).
`QuotaScraper+JS.swift` walks the DOM, collects every `aria-label` +
text node, joins with `|`, then: `\d+\.?\d*\s*%\s*used` → percentages;
`[role=progressbar][aria-valuenow]` → numeric fallback; six "Resets in
Xh Ym" patterns + an absolute "Resets at 9:30 PM" fallback. This whole
path was the original mechanism — kept as insurance against the
unversioned `/usage` endpoint changing shape.

`~/Library/Logs/ClaudeCounter/scrape-debug.txt` is rewritten **only when
the fallback runs**, with percentages, bar values, matched pattern, and
the first 2000 chars of aggregated text. NSLog from a non-Apple-signed
bundle is filtered out of unified logging — this file is the fallback's
only runtime visibility.

## Content blocking

`ContentBlocker.shared.prewarm()` runs from
`applicationDidFinishLaunching`. It compiles a `WKContentRuleList`
that drops `image`, `font`, `media`, `popup`, `ping` resources plus
~15 analytics/RUM domains. Compilation is async (~50-200 ms) — the
first scrape may run unfiltered, every subsequent one is blocked.

The visible Usage window passes `blockHeavy: false` so login flows,
brand assets, and CAPTCHAs render normally.

## Common pitfalls

- **The `/usage` API is internal and unversioned.** If its JSON shape
  changes, `UsageMapper` yields nil → `.decodeFailed` → the DOM-scrape
  fallback takes over (degrades, doesn't break). The pinned
  `usage.json` fixture in the tests flags shape drift early.
- **Cloudflare `cf_clearance` expiry** is the normal trigger for the
  fallback WebView: it re-passes the challenge, refreshes the cookie,
  and the API path resumes next tick. Only `URLSession` (system TLS)
  clears Cloudflare — curl/libcurl get 403.
- **claude.ai changing markup** breaks only the *fallback* regex (DOM
  scrape). If the fallback also fails, check
  `~/Library/Logs/ClaudeCounter/scrape-debug.txt` and adjust patterns in
  `QuotaScraper+JS.swift`.
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
