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
