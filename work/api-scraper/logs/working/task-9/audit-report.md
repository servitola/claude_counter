# Task 9 — Test Audit (api-scraper)

**Auditor:** test-auditor · **Date:** 2026-06-17 · **Branch:** feature/api-scraper
**Scope:** analysis only — no code/test modified.
**Baseline:** `cd App && swift test` → **97 tests in 14 suites, all pass** (green).

## Verdict

**PASSED (clean).** The feature test suite covers every behavior in the
tech-spec Testing Strategy with exact-value, litmus-resistant assertions. No
critical or high findings. A small number of LOW improvements are noted; none
block. Pyramid balance is appropriate for size M.

- Feature-added `@Test` functions: **47** (models 5, mapper 7, OrgIDStore 3,
  CookieBridge 7, UsageAPIClient core 8, classification 5, orchestration 7,
  backoff 5).
- Pre-API tests intact and green: `QuotaParserTests` (8), `JSQuotaParserTests`
  (18), `ClaudeUsageTests` (4), `QuotaPayloadTests` (5), `QuotaTitleFormatterTests`
  (9), `ScrapeDebugLogTests` (3), `ScrapeDebugFormatTests` (3) — the DOM-scrape
  fallback path remains fully covered (Decision 4 / AC).

---

## Coverage Matrix (behavior → test → status)

### Unit — decode / models

| Behavior (tech-spec) | Test | Status |
|---|---|---|
| `UsageResponse` decodes `usage.json` → 3 limits (session/weekly_all/weekly_scoped) with exact Dates | `UsageAPIModelsTests.decodesUsageFixtureLimits` | Covered — exact percent/group/isActive/resetsAt asserted |
| Flat windows (`five_hour`/`seven_day`) decode with exact reset Dates | `UsageAPIModelsTests.decodesUsageFixtureFlatWindows` | Covered |
| ISO-8601 two-formatter: with AND without fractional seconds → exact Date | `UsageAPIModelsTests.decodesIsoDateWithAndWithoutFractionalSeconds` | Covered — both branches, exact Dates |
| Malformed `resets_at` throws (negative path) | `UsageAPIModelsTests.throwsOnMalformedResetsAt` | Covered — asserts `throws: DecodingError.self` |
| `organizations.json` → first uuid | `UsageAPIModelsTests.decodesOrganizationsFixtureUuid` | Covered |

### Unit — mapping (`limits[]` → ClaudeUsage)

| Behavior | Test | Status |
|---|---|---|
| session→current, weekly_all→weekly (NOT weekly_scoped), `updatedAt = now` | `UsageMapperTests.maps_session_to_current_and_weekly_all_to_weekly` | Covered |
| `resets_at` → exact current/weekly Dates; weekly_all chosen over weekly_scoped | `UsageMapperTests.maps_resets_at_to_exact_dates` | Covered — weekly==51 + weekly reset `…900484` proves weekly_all selection |
| Missing weekly_all → flat `seven_day` fallback | `UsageMapperTests.missing_weekly_all_falls_back_to_seven_day` | Covered |
| Missing session → flat `five_hour` fallback | `UsageMapperTests.missing_session_falls_back_to_five_hour` | Covered |
| `nil resets_at` passes through (no map failure) | `UsageMapperTests.nil_resets_at_passes_through_without_failing_map` | Covered |
| `percent` Double→Int truncation (2.9→2) | `UsageMapperTests.percent_double_truncates_to_int` | Covered |
| Empty `limits[]` + no flat → `nil` (→ `.decodeFailed`) | `UsageMapperTests.empty_limits_no_flat_fields_returns_nil` | Covered |

### Unit — OrgIDStore (isolated UserDefaults)

| Behavior | Test | Status |
|---|---|---|
| write→read round-trips uuid | `OrgIDStoreTests.writeThenReadReturnsUUID` | Covered |
| invalidate clears uuid | `OrgIDStoreTests.invalidateClearsUUID` | Covered |
| Uses injected `suiteName`, never `.standard` (no bleed) | `OrgIDStoreTests.usesInjectedSuiteNotStandard` | Covered — asserts `.standard` stays nil; teardown via `removePersistentDomain` |

### Unit — HTTP classification

| Behavior | Test | Status |
|---|---|---|
| 403 + Cloudflare challenge HTML → `.needsCookieRefresh` | `…ClassificationTests.challengeHTMLReturnsNeedsCookieRefresh` | Covered |
| **200 login-HTML body → `.notLoggedIn`** (not `.decodeFailed`) | `…ClassificationTests.loginPageBodyReturnsNotLoggedIn` | Covered — the load-bearing precedence case |
| 401 → `.notLoggedIn` | `…ClassificationTests.status401ReturnsNotLoggedIn` | Covered |
| Redirect to `/login` → `.notLoggedIn` | `…ClassificationTests.loginRedirectReturnsNotLoggedIn` | Covered |
| 200 + unmappable JSON → `.decodeFailed` | `…ClassificationTests.garbageJSONReturnsDecodeFailed` | Covered |

Degenerate bodies pinned as inline fixtures (`challengeHTML`, `loginHTML`,
`{"unexpected":true}`) in `UsageAPIClientTestSupport` — deterministic.

### Integration — UsageAPIClient (URLProtocol-stubbed)

| Behavior | Test | Status |
|---|---|---|
| Full path: `/organizations` then `/usage` → populated `ClaudeUsage` (exact %/Dates) | `UsageAPIClientTests.successReturnsPopulatedUsage` | Covered |
| Cookie write-back: `Set-Cookie` reaches injected WebView store via real `CookieBridge`; Secure/HttpOnly preserved | `successWritesRotatingCookieBackToStore` | Covered — litmus: removing `writeBackCookies` breaks it |
| uuid cached; second fetch skips `/organizations` (HitCounter==1) | `discoveryCachesUUID` | Covered |
| Multi-org `/organizations` → first picked & cached | `multiOrgPicksFirst` | Covered |
| Non-UUID org id → `.decodeFailed` + cache invalidated | `nonUUIDOrgFailsDiscovery` | Covered (path-traversal guard) |
| Transport error → `.transport` | `transportErrorReturnsTransport` | Covered |
| Off-host redirect strips `Cookie` header | `offHostRedirectStripsCookie` | Covered — asserts recorded off-host request carries no Cookie |
| Secret-log guard: sentinel cookie absent from every log line | `noCookieValueInLogs` (client) + `noCookieValueAppearsInCapturedLogSink` (CookieBridge: header AND body) | Covered |

### Integration — Orchestration (asserts AppState end-state, NOT spies)

| Behavior | Test | Status |
|---|---|---|
| `.success` → `AppState.usage` populated, webView stays nil, fallback counter 0 | `…OrchestrationTests.apiSuccessLeavesWebViewNilAndPopulatesState` | Covered |
| `.needsCookieRefresh` → fallback runs → `AppState.usage` = DOM result | `needsCookieRefreshFallbackPopulatesStateViaDomScrape` | Covered — end-state asserted |
| `.decodeFailed` → fallback runs → `AppState.usage` = DOM result | `decodeFailedFallbackPopulatesStateViaDomScrape` | Covered |
| `.notLoggedIn` repeated → webView nil, counter 0, state `.empty` across 4 ticks | `repeatedNotLoggedInKeepsWebViewNilAcrossTicks` | Covered |
| wake re-probe after logged-out → `.success` populates state | `wakeAfterNotLoggedInReprobesAndPopulatesState` | Covered |
| window-open re-probe → populates state | `windowOpenAfterNotLoggedInReprobesAndPopulatesState` | Covered |
| `.transport` → state unchanged (preset preserved), webView nil | `transportErrorLeavesStateUnchangedAndWebViewNil` | Covered — asserts preset survives |

### Integration — Decision-7 backoff (observable)

| Behavior | Test | Status |
|---|---|---|
| Backoff suppresses fallback (next-tick `.needsCookieRefresh` not entered) | `…BackoffTests.loggedOutBackoffSuppressesNeedsCookieRefreshFallback` | Covered — litmus: removing `guard !loggedOut` flips counter to 1 |
| Backoff persists across N automatic ticks (the real bug fixed in round 2) | `loggedOutBackoffPersistsAcrossManyAutomaticTicks` | Covered |
| `forceRefresh()` clears backoff → fallback re-enabled (counter==1) | `forceRefreshClearsBackoffAndReenablesFallback` | Covered — via real method, not flag poke |
| `/login` navigation hook arms backoff (real `WKNavigationDelegate` callback) | `loginNavigationDetectionArmsBackoff` | Covered — drives real `webView(_:didFinish:)`, asserts `loggedOut` + webView torn down |
| Single-flight: overlapping triggers don't stack a second pass | `overlappingTriggersDoNotStackASecondPass` | Covered — two `scrape()` → counter==1 |

### E2E
None automated — correctly deferred to AVP smoke (Cloudflare-gated, non-deterministic). Matches tech-spec.

**Result: every Testing-Strategy bullet (unit + integration) is mapped to a passing test. Zero missing items.**

---

## Assertion-Quality Findings

Overall quality is **high**. The suite consistently asserts exact values, not
`!= nil`; reset Dates are reconstructed with an independent formatter (not the
decoder under test) so a broken decoder can't mask a broken expectation. Spot
checks against the litmus test ("delete the code → test still passes"):

- **Mapper / decode:** PASS. Exact percents + exact Dates; deleting the
  session/weekly_all selection logic flips `currentPercent`/`weeklyPercent`.
- **Classification precedence:** PASS. `loginPageBodyReturnsNotLoggedIn` would
  flip to `.decodeFailed` if the auth-before-decode ordering were removed —
  this is the highest-value guard in the suite and it is real.
- **Orchestration:** PASS. Tests assert `AppState.usage` end-state and the
  WebView reference, never "method called" — exactly what the task and
  Decision 4/7 demand. The fallback counter (`FallbackCounter`) doubles as the
  production "WebView instantiation count" observable, not a spy on an injected
  closure's return value.
- **Backoff:** PASS. Counter-based observable + litmus comments documenting the
  exact line whose removal fails the test.
- **Write-back:** PASS. End-to-end through the real `CookieBridge` into a real
  (non-persistent) `WKHTTPCookieStore`; asserts value AND Secure/HttpOnly
  survival — not a closure echo.

No vacuous (`expect(true)`), no `!= nil`-only where an exact value is known, no
mock-return-echo, no over-mocking (the seams are fakes/stubs returning canned
data, not interaction mocks). The two log-sink tests guard against vacuity by
first asserting `!lines.isEmpty` before scanning for the sentinel — a nice touch
that prevents a passing-because-nothing-was-logged false green.

**LOW-1 — `garbageJSONReturnsDecodeFailed` is decode-success-but-unmappable,
not malformed JSON.** `{"unexpected":true}` decodes cleanly (empty `limits`, no
flat windows) and reaches `.decodeFailed` via `UsageMapper.map → nil`. That is a
valid and important path, but the test name/comment imply syntactically broken
JSON. The truly malformed-JSON branch (e.g. `not json at all` → `decoder.decode`
throws → `.decodeFailed`) is exercised only indirectly. *Suggested fix:* rename
to `unmappableJSONReturnsDecodeFailed`, and optionally add one route with
genuinely invalid JSON bytes to pin the `try?`-throws arm of `classifyUsage`.
Severity LOW (both arms return the same case; behavior is correct).

**LOW-2 — `isLoginPage` matches the substring `/login` anywhere in the body.**
`UsageResponseClassifier.isLoginPage` returns true if the HTML body contains
`/login` (in addition to the title/form markers). A legitimate JSON `/usage`
response is `application/json`, so `isHTML` gates this and it can't misfire in
practice — but there is no test pinning that a *non-login* `text/html` 200 body
(if one ever appeared) is NOT swallowed as `.notLoggedIn`. *Suggested fix
(optional):* add a classification test with a `text/html` 200 body that is
neither challenge nor login (e.g. an error page) and assert `.decodeFailed`, to
lock the negative side of the HTML branch. Severity LOW (defensive; current
contract is JSON-only on success).

**LOW-3 — `multiOrgPicksFirst` fixture comment says "first org inactive" but
`OrgSummary` has no active flag.** The comment in `twoOrgJSON` ("first org
inactive; pick must be deterministic") describes an active/inactive distinction
the model doesn't carry — the pick is purely positional. Harmless but slightly
misleading; the production `pickOrg` is also documented as positional. *Suggested
fix:* trim the comment to "pick is positional (first)". Severity LOW (cosmetic).

---

## URLProtocol Stubbing Review

**Sound.** Matches the task's DI requirement exactly:

- **DI, not global registration:** `makeStubbedClient` builds a fresh
  `URLSessionConfiguration.ephemeral`, sets `config.protocolClasses =
  [StubURLProtocol.self]`, and injects it into `UsageAPIClient(configuration:)`.
  No `URLProtocol.registerClass` — stubs are scoped to the session, not global.
- **Path routing is correct & non-ambiguous:** `.ok(path:)` uses
  `hasSuffix(path)` so `/api/organizations` (org list) never also matches
  `/api/organizations/{uuid}/usage` (usage) — the shared-prefix hazard is
  explicitly handled. Off-host routing uses a `matchHost` variant.
- **Degenerate bodies pinned inline:** `challengeHTML`, `loginHTML`,
  `twoOrgJSON`, malicious `../../etc/passwd` org, garbage JSON — all inline
  string/Data fixtures; real `usage.json`/`organizations.json` loaded via
  `Bundle.module`.
- **No cross-test leakage:** every test installs routes via
  `StubURLProtocol.install` (which clears `recorded`) and `defer {
  StubURLProtocol.reset() }`. The route table + recorded log are
  `nonisolated(unsafe)` statics guarded by a single `NSLock`. Because the table
  is **process-global**, the whole `UsageAPIClientTests` suite is `@Suite(.serialized)`
  — the only safe shape, and correctly justified in the support file. Each
  OrgID store is an isolated `UserDefaults(suiteName:)` torn down in `defer`.
- **Redirect fidelity:** `sendRedirect` carries the original request's headers
  onto the redirected request, so the off-host Cookie-strip delegate actually
  sees the `Cookie` header it must remove — without this the redirect test would
  be vacuous. Good.

No findings.

---

## Isolation / Cleanup Review

- `OrgIDStore` + `IsolatedStore` → throwaway `UserDefaults(suiteName: UUID)`,
  `removePersistentDomain` in `defer`/teardown; explicit assert that `.standard`
  is untouched. No bleed.
- `CookieBridge` tests → `WKWebsiteDataStore.nonPersistent()`; never
  `.default()`. The shared login cookie jar is never touched.
- Concurrency-safe collectors (`LogCollector`, `HitCounter`, `FallbackCounter`,
  `ResultScript`) all use `NSLock` + `@unchecked Sendable` — correct for the
  off-main `URLProtocol` / Task callbacks.
- `@MainActor` correctly applied to CookieBridge, orchestration, and backoff
  suites (WebKit / AppState live on MainActor).

No findings.

---

## Test-Pyramid Balance (size M)

Tech-spec implies ≈9 unit / 4 integration. Actual feature tests:

- **Unit:** decode (5) + mapper (7) + OrgIDStore (3) + classification (5) = **20**
- **Integration:** client (8) + orchestration (7) + backoff (5) = **20**

This is heavier than the ≈9/4 sketch but **not over-coverage** — the extra unit
tests are the spec's own edge cases (two-formatter ±fractional, malformed-date
throw, each fallback arm, percent truncation, multi-org, non-UUID guard), and
the integration tests are split one-assertion-per-concern (DAMP), which is the
right call for a security/correctness-sensitive networking surface. No redundant
duplicate-coverage tests found; each carries a distinct failure it alone
catches. Given this is a **UI/menu-bar app** where the networking core is the
risk, the slightly integration-rich shape is appropriate (test-master: UI apps
favor integration/E2E). No pyramid violation.

---

## Gaps (prioritized)

| # | Severity | Gap | Suggested fix |
|---|---|---|---|
| LOW-1 | Low | `garbageJSONReturnsDecodeFailed` tests unmappable-valid-JSON, not malformed JSON; the `try?`-throws arm of `classifyUsage` is only indirectly hit | Rename to `unmappableJSONReturnsDecodeFailed`; optionally add a genuinely-invalid-JSON route to pin the decode-throw arm |
| LOW-2 | Low | No negative test for a non-login/non-challenge `text/html` 200 body (the HTML branch's "should NOT classify" side) | Add a classification test: `text/html` 200 with a neutral body → `.decodeFailed` |
| LOW-3 | Low | Misleading "first org inactive" comment in `twoOrgJSON` (model has no active flag; pick is positional) | Trim comment to "positional pick (first)" |

No MEDIUM / HIGH / CRITICAL findings.

---

## Decision-Matrix Outcome

0 critical, 0 high, 0 medium, 3 low → **status: passed**; `taskRequired = false`.
The three LOW items are optional polish and can be folded into any future touch
of these files; none require a fix cycle before deploy.
