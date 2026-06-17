# Decisions Log — api-scraper

Execution-time decisions and per-task completion reports. Populated as tasks
are implemented (one short entry per task: summary, review links, any
deviation from spec). Empty until implementation starts.

## Tasks

<!-- Append per-task entries here during execution. Template:
### Task N: <name>
- **Summary:** 1-3 sentences on what was implemented.
- **Reviews:** code-reviewer / security-auditor / test-reviewer → logs/working/task-N/*.json
- **Deviations:** none | <what and why>
-->

## Task 1: API models + JSON decoding + test fixtures

**Status:** Done
**Commit:** 2436bd8
**Agent:** models-coder
**Summary:** Added `App/Sources/ClaudeCounter/Scraper/UsageAPIModels.swift` with the
`Decodable` types `OrgSummary`, `UsageLimit`, `FlatWindow`, and `UsageResponse`
(snake_case `CodingKeys`; `percent`/`utilization` as `Double`), plus a
`UsageAPIModels.decoder` whose custom `dateDecodingStrategy` tries an ISO-8601
parse with fractional seconds and falls back to one without. Copied the committed
`usage.json`/`organizations.json` fixtures into the test target and wired them via
`Package.swift` `resources:` so they load through `Bundle.module`.
**Deviations:** Deviated from spec on two minor points to satisfy the repo's
pre-commit hooks (SwiftFormat + strict SwiftLint, warnings-as-errors): (1) the
shared decoder is a computed `static var` returning a fresh `JSONDecoder` per call
rather than a `static let` — `ISO8601DateFormatter`/`JSONDecoder` are not `Sendable`,
and a stored static is rejected under Swift 6 strict concurrency; formatters are
built locally inside the decode closure. (2) Added a one-line
`swiftlint:disable:next discouraged_optional_boolean` for the spec-mandated
`isActive: Bool?`. Behavior matches the spec exactly.

**Reviews:**

*Round 1:*
- code-reviewer: approved (2 low nits) → logs/working/task-1/code-reviewer-round1.json
- test-reviewer: changes_requested (1 high: untested malformed-date branch) → logs/working/task-1/test-reviewer-round1.json

*Round 2 (after fix af86bb9):*
- Added negative test `throwsOnMalformedResetsAt()`; finding resolved.

**Verification:**
- `cd App && swift test` → 54 tests pass (50 pre-existing + 4 new), 8 suites
- `cd App && swift build` → clean (strict concurrency, warnings-as-errors)
- SwiftFormat (lint) + SwiftLint (strict) pre-commit hooks → pass

---

## Task 3: OrgIDStore (org uuid cache)

**Status:** Done
**Commit:** d119c0a
**Agent:** orgstore-coder
**Summary:** Added `App/Sources/ClaudeCounter/Scraper/OrgIDStore.swift` — a small
pure-Foundation `struct` wrapping an injected `UserDefaults` (default `.standard`)
with `read`/`write`/`invalidate` of a cached org UUID under one well-known key
(`"org.uuid"`, exposed as `static let key`). Tests inject an isolated
`UserDefaults(suiteName:)` (unique per test, torn down via
`removePersistentDomain`) and assert no bleed into `.standard`.
**Deviations:** Marked the type `@unchecked Sendable` rather than plain `Sendable`:
`UserDefaults` is thread-safe but not `Sendable` in Foundation, so a plain
conformance fails under strict concurrency. Behavior matches the spec.

**Reviews:**

*Round 1:*
- code-reviewer: approved (1 low nit) → logs/working/task-3/code-reviewer-round1.json
- test-reviewer: approved (4 minor edge-case suggestions) → logs/working/task-3/test-reviewer-round1.json

**Verification:**
- `cd App && swift test` → 58 tests pass (55 pre-existing + 3 new), 9 suites
- `make ci` → clean (build, SwiftFormat lint, SwiftLint strict, periphery dead-code), exit 0

---

## Task 4: CookieBridge (read + write-back, host-scoped)

**Status:** Done
**Commit:** 1f330bd
**Agent:** cookie-coder
**Summary:** Added `App/Sources/ClaudeCounter/Scraper/CookieBridge.swift` — a
`@MainActor struct` over an injectable `WKWebsiteDataStore` (default
`.default()`). `read()` awaits `httpCookieStore.allCookies()` on MainActor and
returns a plain `[HTTPCookie]` filtered to `claude.ai`-scoped cookies (bare host
and leading-dot form, case-insensitive; lookalikes like `notclaude.ai` /
`claude.ai.evil.com` rejected); `cookieHeader()` builds the `name=value; …`
request header. `writeBack(setCookieHeaders:responseURL:)` parses via
`HTTPCookie.cookies(withResponseHeaderFields:for:)` and inserts only
`claude.ai`-scoped cookies via `setCookie`, skipping foreign/unparseable
entries. Per Decision 6, logging goes through an injectable `@MainActor (String)
-> Void` seam (default → `AppLog.scraper.debug` with `privacy: .public`) and
emits counts/host only — never a cookie name or value.
**Deviations:** none. (Logging seam implemented as an injectable closure, one of
the explicitly-allowed mechanisms in the task.)

**Reviews:**

*Round 1:*
- code-reviewer: approved (2 minor: comma-join Set-Cookie, redundant re-read) → logs/working/task-4/code-reviewer-round1.json
- security-auditor: approved (Decision 6 + exact host-scoping verified; 2 minor) → logs/working/task-4/security-auditor-round1.json
- test-reviewer: approved (2 low test gaps) → logs/working/task-4/test-reviewer-round1.json

*Round 2 (after fix 90b9426):*
- Per-field Set-Cookie parsing (deterministic, no Expires-comma mis-split); strengthened non-claude write-back test (foreign Domain on claude.ai URL); added unparseable-but-keep-valid test. 65 tests, make ci clean.

**Verification:**
- `cd App && swift test` → 65 tests pass, `make ci` → clean, exit 0

---

## Task 2: limits[] → ClaudeUsage mapper

**Status:** Done
**Commit:** c0dfd0b
**Agent:** mapper-coder
**Summary:** Added `App/Sources/ClaudeCounter/Scraper/UsageMapper.swift` — a pure,
Sendable `enum` with `static func map(_ response: UsageResponse, now: Date = Date())
-> ClaudeUsage?` mirroring `QuotaParser`'s shape. Current ← `limits[]` entry with
`kind == "session"` (else flat `fiveHour`); weekly ← entry with `kind == "weekly_all"`,
never `weekly_scoped` (else flat `sevenDay`). `percent`/`utilization` `Double`→`Int`
by truncation (`Int(2.9) == 2`); `resetsAt` passed straight through as the
already-parsed `Date`; `updatedAt = now`. Returns `nil` only when neither `limits[]`
nor a flat fallback yields any current or weekly value. Reuses Task 1's
`UsageResponse`/`UsageLimit`/`FlatWindow` unchanged.
**Deviations:** Test method names lost their `test_` prefix (anchors became
`maps_session_to_current_and_weekly_all_to_weekly`, etc.) — SwiftFormat's
`swiftTestingTestCaseNames` rule (enforced by `make ci`) strips the redundant
`test` prefix from `@Test` functions; the rest of each anchor name is preserved
verbatim. Behavior matches the spec exactly.

**Reviews:**

*Round 1:*
- code-reviewer: approved (2 minor) → logs/working/task-2/code-reviewer-round1.json
- test-reviewer: changes_requested (HIGH fiveHour fallback untested; MED resetsAt nil) → logs/working/task-2/test-reviewer-round1.json

*Round 2 (after fix 4f12351):*
- Added fiveHour-fallback + resetsAt-nil-passthrough tests (TDD litmus confirmed both). 72 tests, make ci clean.

**Verification:**
- `cd App && swift test` → 72 tests pass · `make ci` → clean, exit 0

---

## Task 5: UsageAPIClient (URLSession fetch + discovery + classification)

**Status:** Done
**Commit:** e114b94
**Agent:** client-coder
**Summary:** Added `App/Sources/ClaudeCounter/Scraper/UsageAPIClient.swift` — the
networking core. Owns one `URLSession` with no cookie jar (`httpCookieStorage =
nil`, `httpCookieAcceptPolicy = .never`, `httpShouldSetCookies = false`; config
injectable for URLProtocol stubbing). `fetch()` discovers the org uuid
(`GET /api/organizations`, first uuid, cached/invalidated via `OrgIDStore`),
fetches `GET /api/organizations/{uuid}/usage` with the shared Safari UA
(`WebViewFactory.safariUserAgent`, now exposed) + bridged cookies, and returns a
typed `UsageFetchResult` (success / needsCookieRefresh / notLoggedIn /
decodeFailed / transport — Task 5 owns the enum). Classification runs the 403
Cloudflare-challenge check and all auth checks (401, `/login` redirect, 200
login-page HTML) BEFORE any JSON decode; cookies are read via `CookieSource`
(a `Sendable` two-closure seam over `CookieBridge`) and `Set-Cookie`s written
back on success. Off-host redirects strip the `Cookie` header via
`OffHostRedirectGuard` (`URLSessionTaskDelegate`). Decision 6: only value-free
events are logged (status, result case, discovery outcome) — never cookies or
headers.

**Deviations:**
- Split the source across two files to satisfy SwiftLint `file_length` (≤300):
  `OffHostRedirectGuard.swift` holds the redirect delegate; `UsageAPIClient.swift`
  holds the client + `UsageFetchResult` + `CookieSource`. Task brief named only
  `UsageAPIClient.swift`; the delegate extraction is a length-driven structural
  split, committed alongside.
- Tests split into three files (one serialized `UsageAPIClientTests` suite via
  extensions: core + classification, plus `UsageAPIClientTestSupport` helpers and
  a `StubURLProtocol` URLProtocol stub) — again to stay under `file_length`. A
  single suite is mandatory: `StubURLProtocol`'s route table is process-global,
  so `.serialized` across one suite is the only way to prevent cross-test route
  stomping.
- Two-org fixture is inline (`twoOrgJSON`) per the brief; no new JSON file added —
  reused the committed `usage.json` / `organizations.json` test resources.
- `CookieSource.bridged` (the Task-6 production seam) carries `// periphery:ignore`
  (matching the codebase pattern) — unreferenced until Task 6 wires the loop.

**Reviews:**

*Round 1:*
- code-reviewer: approved (1 medium lossy write-back, 2 low) → logs/working/task-5/code-reviewer-round1.json
- security-auditor: approved (Decision 6 + SSRF/redirect verified; 3 minor) → logs/working/task-5/security-auditor-round1.json
- test-reviewer: changes_requested (HIGH: write-back untested, reset Dates only !=nil) → logs/working/task-5/test-reviewer-round1.json

*Round 2 (after fix 2d5d0f3):*
- Lossless cookie write-back (raw Set-Cookie → CookieBridge, no reconstruction; litmus-verified end-to-end test); exact reset-Date assertions; UUID guard on discovered org id (rejects non-UUID → re-discover); factored UsageResponseClassifier.swift for file_length. 85 tests, make ci clean.

**Verification:**
- `cd App && swift test --filter UsageAPIClient` → pass; full suite → 85 tests pass
- `make ci` (format-check, lint --strict, test, dead-code) → clean, exit 0
- Live smoke (lead, real URLSession + logged-in WKWebsiteDataStore cookies, Safari UA): GET /api/organizations → 200 (uuid 8f859b21…); GET /organizations/{uuid}/usage → 200, limits[] = session/weekly_all/weekly_scoped with ISO-8601 resets_at — exact shape UsageAPIClient+UsageMapper consume. curl→403, URLSession→200 confirmed.

---

## Task 6: QuotaScraper orchestration (API-first, WebView fallback, backoff)

**Status:** Done
**Commit:** 625e150
**Agent:** orchestration-coder
**Summary:** Rewired `QuotaScraper.scrape()` into an API-first orchestrator
(new `QuotaScraper+Orchestrator.swift`): each tick clears the Decision-7
backoff, probes `UsageAPIClient.fetch()` off-main, and applies the classified
`UsageFetchResult` on MainActor. `.success` → `AppState.usage`, NO WebView;
`.needsCookieRefresh`/`.decodeFailed` → the retained ephemeral-WebView
DOM-scrape fallback (`runWebViewFallback()` → `buildEphemeralWebView()`, the
old `scrape()` body verbatim); `.notLoggedIn` → set `loggedOut` (suppresses
the fallback) value-free; `.transport` → leave state, retry next tick, no
WebView. The 60 s timer (+10 s tolerance), watchdog, wake observer, retry
semantics, and the whole DOM pipeline are intact. `/login` detection in
`QuotaScraper+Navigation.swift` now also sets `loggedOut`. `openWindow()` calls
`scraper.scrape()` after `show()` (Decision-7 window-open re-probe); wake and
"Refresh Now" re-probe for free via the clear-at-top.
**Injectability:** two closure seams on `QuotaScraper.init` — `fetchUsage`
(default → production `UsageAPIClient` via `makeProductionFetch()`, wiring
`OrgIDStore` + `CookieSource.bridged(CookieBridge())`) and `runFallback`
(default → real WebView pipeline). Tests script `UsageFetchResult`s and a
counting/AppState-populating fallback stub, asserting observable end state
(`AppState.usage`, `scraper.webView`, fallback counter) — never spy calls.
An `awaitInFlight()` test hook awaits the single-flight orchestrator Task.
**Deviations:**
- Added `QuotaScraper+Orchestrator.swift` (not in the named file list) to keep
  `QuotaScraper.swift` under SwiftLint `file_length` (≤300). The orchestrator,
  fallback, production-seam factory, and `awaitInFlight()` live there.
- Used closure seams (not a protocol) for injection — `UsageAPIClient` is a
  value-type struct with a free `fetch()`, so a closure is the lightest seam
  and keeps the scraper free of WebKit/`@MainActor` leakage into the API path.
- `scrape()` stays synchronous (launches an internal `Task`) so all existing
  callers (timer, wake, `refresh()`, new window-open) compile unchanged; an
  `isFetchingNow` single-flight guard prevents stacking.
- Removed the now-superfluous `// periphery:ignore` on `CookieSource.bridged`
  (Task 5 placeholder) since Task 6 references it — required for periphery
  `--strict` to pass; touched UsageAPIClient.swift for that one-line change.

**Reviews:**

*Round 1:*
- code-reviewer: approved (low/info only) → logs/working/task-6/code-reviewer-round1.json
- test-reviewer: changes_requested (3 HIGH: single-flight, suppression guard never reached, /login backoff untested) → logs/working/task-6/test-reviewer-round1.json

*Round 2 (after fix bddbd76):*
- Fixed real backoff logic bug: `scrape()` cleared `loggedOut` every tick (incl. 60s timer), making Decision-7 suppression dead. Now flag persists across automatic ticks; cleared only by explicit `forceRefresh()` (wired to wake/Refresh-Now/window-open) and auto-cleared on `.success`. Added 5 tests (suppression fires, persists across N ticks, forceRefresh re-enables, /login arms backoff, single-flight) — litmus-verified. 97 tests, make ci clean.

**Verification:**
- `cd App && swift test` → 97 tests pass, 14 suites
- `make ci` (format-check, lint --strict, test, periphery dead-code) → clean, exit 0
- User verify-app run (logged-in menu-bar parity + Activity Monitor: no per-tick WebContent/GPU helper, idle RSS below ~82 MB) deferred to lead/Phase 4.

---

## Task 7: Code Audit

**Status:** Done
**Agent:** code-auditor
**Summary:** Holistic cross-component audit of the Tasks 1–6 source files (no
code changes). Verdict: clean overall, no critical/blocking findings. Cookie
single-source-of-truth (Decision 2), host scoping, Decision-7 backoff
persistence, the 200-login-page-before-decode classification, and Swift 6 strict
concurrency all verified sound. One HIGH consistency gap reported: a Cloudflare
403 challenge on the **org-discovery** call (`resolveOrgUUID`) routes to
`.decodeFailed` instead of `.needsCookieRefresh` because it skips the
`isChallenge` pre-check the `/usage` call runs — recoverable (both spin the
WebView fallback) but mislabels the cold-start refresh path. Plus MEDIUM/LOW
items (over-broad `/login` body marker in `isLoginPage`, fallback retry routing
through the API path, comma-folded `Set-Cookie` write-back nuance, duplicated
host-scoping logic).
**Report:** logs/working/task-7/audit-report.md
**Deviations:** none (analysis-only task; no source modified).

---

## Task 8: Security Audit

**Status:** Done
**Agent:** security-auditor
**Summary:** OWASP-Top-10 pass over the new authenticated HTTP client + cookie
handling. Result is CLEAN — zero critical/high/medium findings; two
informational notes only. Decision 6 (no secret ever logged/dumped/persisted)
and Decision 2 (cookies attached only to claude.ai, stripped on off-host
redirect, URLSession with no cookie jar of its own, UUID-validated org-id URL
interpolation) are honored on every audited path. No ATS exception, no
TLS/cert-validation bypass, no auth-challenge delegate; org UUID is the only
UserDefaults value (non-secret); the on-disk ScrapeDebugLog can only capture DOM
text (HttpOnly cookies are unreadable from the extraction JS) and the API
`.decodeFailed` path dumps nothing. Feature is not security-blocked for Task 10.
**Report:** logs/working/task-8/audit-report.md
**Deviations:** none (analysis-only task; no source modified).

---

## Task 9: Test Audit

**Status:** Done
**Agent:** test-auditor
**Summary:** Holistic test-quality audit of the feature suite against the
tech-spec Testing Strategy. Verdict: PASSED (clean) — all 47 feature `@Test`s
(plus the pre-API DOM-scrape fallback tests) map to the spec's unit +
integration bullets with exact-value, litmus-resistant assertions; orchestration
asserts AppState end-state (not spies), URLProtocol stubbing is
DI'd/serialized/leak-free, and isolation uses throwaway UserDefaults +
non-persistent cookie stores. Baseline green (97 tests, 14 suites). 0
critical/high/medium, 3 LOW polish items only; no fix cycle required.
**Report:** logs/working/task-9/audit-report.md
**Deviations:** none (analysis-only task; no code/test modified).

---

## Task 10: Pre-deploy QA

**Status:** Done
**Agent:** qa-runner
**Summary:** Acceptance gate passed. `make ci` fully green (format-check, lint
--strict, test, dead-code --strict), exit 0; **100 tests in 14 suites, 0
failures** (confirmed identical via standalone `cd App && swift test`).
`make build` / `swift build` → clean (runnable product). `App/Package.swift`
has **zero** external `.package(...)` deps (only Fixtures resources). Both
secret-log guard tests present and green (`UsageAPIClientTests/noCookieValueInLogs`,
`CookieBridgeTests/noCookieValueAppearsInCapturedLogSink`). Every automatable
acceptance criterion (US-1…US-6, tech-spec AC-1…AC-9) is PASS with a
behavior-asserting test cited; **zero findings, zero blockers**.
**Verdict:** READY for user (post-deploy) verification.
**Deferred to post-deploy:** the live-environment checks (logged-in menu-bar
parity with claude.ai, Activity Monitor RSS < ~82 MB with no per-tick
WebContent/GPU helpers, real 403→WebView-refresh→API-resume, logout
backoff/login resume) are Cloudflare-gated / Activity-Monitor-only and
non-deterministic in CI — DEFERRED with exact manual steps in the report.
**Deviations:** none (QA task; nothing modified).

**Verification:**
- Full report: [logs/working/task-10/qa-report.md](logs/working/task-10/qa-report.md)
