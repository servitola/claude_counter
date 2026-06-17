# Pre-deploy QA Report — Task 10

**Feature:** JSON API scraper (drop per-minute WebView)
**Branch:** feature/api-scraper
**Date:** 2026-06-17
**Agent:** qa-runner
**Scope:** Static + test gate only. No live network calls, no GUI run (per task brief — live checks are deferred to lead/user).

---

## 1. Quality gate (`make ci`)

Command run from repo root (`/Users/servitola/projects/services/claude_counter`):

```
make ci   →   check   →   format-check · lint · test · dead-code
```

| Step | Tool | Result |
|------|------|--------|
| format-check | `swiftformat --lint` | **PASS** — 0/47 files require formatting |
| lint | `swiftlint lint --strict` | **PASS** — 0 violations, 0 serious in 47 files |
| test | `swift test` | **PASS** — see test count below |
| dead-code | `periphery scan --strict` | **PASS** — no dead code (gate exited 0) |

**`make ci` exit code: 0 (fully green).**

### Test count

- `make ci` test step and standalone `cd App && swift test`: **100 tests in 14 suites, 0 failures, 0 skipped.**
- Confirmed identical via the separate `cd App && swift test` run (`Test run with 100 tests in 14 suites passed`).
- Growth trace through decisions.md is consistent: Task 1 → 54, Task 3 → 58, Task 4 → 65, Task 2 → 72, Task 5 → 85, Task 6 → 97, plus the 3 audit-wave / polish tests → **100**. No regression; all pre-existing QuotaParser/JS DOM-scrape fallback tests remain green (fallback path intact).

### Build

- `make build` / `cd App && swift build` → **Build complete!**, exit 0. Compiles into a runnable product under Swift 6.2 strict concurrency + warnings-as-errors.

### No new external dependencies

- `App/Package.swift` declares **zero** `.package(...)` dependencies. The only additions are test-target `resources: [.copy("Fixtures/usage.json"), .copy("Fixtures/organizations.json")]`. Confirms the user-spec "no new external dependencies" non-goal and the tech-spec "New packages: None" line.

---

## 2. Acceptance Criteria verdicts

Legend: **PASS** = covered by automated tests in CI / static artifact. **DEFERRED** = requires a live logged-in claude.ai session, Cloudflare, or Activity Monitor; Cloudflare-gated and non-deterministic, cannot run in CI — handed to post-deploy QA per the tech-spec Agent Verification Plan.

### user-spec Requirements (US-1 … US-6)

| ID | Criterion | Verdict | Evidence |
|----|-----------|---------|----------|
| US-1 | Fetch usage from `/api/organizations/{uuid}/usage` via URLSession on 60 s cadence, reusing WKWebsiteDataStore cookies | PASS (logic) / DEFERRED (live cadence) | `UsageAPIClientTests` (DI'd URLProtocol stub routes `/organizations` then `/usage` → populated `ClaudeUsage`); cookie reuse via `CookieBridgeTests/readReturnsOnlyClaudeAiCookies`. Real 60 s timer firing against live claude.ai is DEFERRED. |
| US-2 | Org UUID discovered via `/api/organizations`, cached, re-discovered on not-found/auth failure | PASS | `OrgIDStoreTests/{writeThenReadReturnsUUID, invalidateClearsUUID, usesInjectedSuiteNotStandard}`; `UsageAPIClientTests/{discoveryCachesUUID, multiOrgPicksFirst, nonUUIDOrgFailsDiscovery, discovery401ReturnsNotLoggedIn}` |
| US-3 | Usage JSON maps to `ClaudeUsage` from `limits[]` (session→current, weekly_all→weekly), reset times from `resets_at` | PASS | `UsageMapperTests/{maps_session_to_current_and_weekly_all_to_weekly, maps_resets_at_to_exact_dates, percent_double_truncates_to_int, missing_session_falls_back_to_five_hour, missing_weekly_all_falls_back_to_seven_day}`; `UsageAPIModelsTests/{decodesUsageFixtureLimits, decodesIsoDateWithAndWithoutFractionalSeconds}` |
| US-4 | On API failure (401/403/challenge HTML) fall back to WKWebView to refresh cookies / surface login, then resume API | PASS (classification + fallback wiring) / DEFERRED (real 403→refresh→resume on live Cloudflare) | Classification: `UsageAPIClientTests/{challengeHTMLReturnsNeedsCookieRefresh, status401ReturnsNotLoggedIn, loginRedirectReturnsNotLoggedIn, loginPageBodyReturnsNotLoggedIn, garbageJSONReturnsDecodeFailed}`. Fallback orchestration end-state: `QuotaScraperOrchestrationTests/{needsCookieRefreshFallbackPopulatesStateViaDomScrape, decodeFailedFallbackPopulatesStateViaDomScrape}`. Real Cloudflare 403→clearance refresh→API resume is DEFERRED. |
| US-5 | When not logged in: quiet wait, no crash, no spam; resume on login | PASS (backoff logic) / DEFERRED (live logout/login) | `QuotaScraperBackoffTests/{loggedOutBackoffPersistsAcrossManyAutomaticTicks, loggedOutBackoffSuppressesNeedsCookieRefreshFallback, loginNavigationDetectionArmsBackoff, forceRefreshClearsBackoffAndReenablesFallback}`; `QuotaScraperOrchestrationTests/{repeatedNotLoggedInKeepsWebViewNilAcrossTicks, wakeAfterNotLoggedInReprobesAndPopulatesState, windowOpenAfterNotLoggedInReprobesAndPopulatesState}`. Live logout→graceful stop→login→resume is DEFERRED. |
| US-6 | Idle footprint drops (no WKWebView instantiated on the normal per-minute path) | PASS (no-WebView invariant) / DEFERRED (memory measurement) | No-WebView-on-success asserted as observable end state: `QuotaScraperOrchestrationTests/apiSuccessLeavesWebViewNilAndPopulatesState` and `transportErrorLeavesStateUnchangedAndWebViewNil`; `repeatedNotLoggedInKeepsWebViewNilAcrossTicks`. Actual Activity Monitor RSS < ~82 MB and absence of per-tick WebContent/GPU helper processes is DEFERRED. |

### user-spec "How to verify"

| Check | Verdict | Evidence |
|-------|---------|----------|
| Logged-in menu bar matches claude.ai usage page, refreshing each minute | DEFERRED | Live logged-in session + Cloudflare. Mapping/format logic covered by US-3 tests; numeric parity with the live page is not reproducible in CI. |
| Activity Monitor steady-state memory materially < 82 MB, no transient WebContent/GPU helpers per tick | DEFERRED | Activity Monitor, live app. (Logic invariant — no WebView on success — covered by US-6 tests.) |
| Expire/clear `cf_clearance` → one WebView refresh, API resumes | DEFERRED | Live Cloudflare clearance manipulation. (Classification + fallback wiring covered by US-4 tests.) |
| Log out → graceful stop + login on window open; log back in → resumes | DEFERRED | Live logout/login. (Backoff + re-probe logic covered by US-5 tests.) |

### tech-spec "Acceptance Criteria"

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| AC-1 | Logged-in app shows current %, weekly %, both reset times matching claude.ai, refreshed every 60 s via API, no WKWebView on a normal tick | PASS (mapping + no-WebView invariant) / DEFERRED (live parity + 60 s cadence) | US-3 mapper/model tests + `QuotaScraperOrchestrationTests/apiSuccessLeavesWebViewNilAndPopulatesState`. Live numeric parity & timer cadence DEFERRED. |
| AC-2 | Org uuid discovered once and cached; cleared on auth failure | PASS | `OrgIDStoreTests/*`, `UsageAPIClientTests/{discoveryCachesUUID, discovery401ReturnsNotLoggedIn, nonUUIDOrgFailsDiscovery}` |
| AC-3 | `resets_at` ISO-8601 timestamps map correctly to `currentResetAt`/`weeklyResetAt` | PASS | `UsageAPIModelsTests/{decodesIsoDateWithAndWithoutFractionalSeconds, throwsOnMalformedResetsAt}`; `UsageMapperTests/{maps_resets_at_to_exact_dates, nil_resets_at_passes_through_without_failing_map}` |
| AC-4 | 403/challenge → automatic WebView cookie refresh → API resumes; logged-out → graceful wait + login; both verified | PASS (classification + fallback + backoff) / DEFERRED (live 403 + logout) | `UsageAPIClientTests/{challengeHTMLReturnsNeedsCookieRefresh, discoveryChallengeHTMLReturnsNeedsCookieRefresh}`; `QuotaScraperOrchestrationTests/needsCookieRefreshFallbackPopulatesStateViaDomScrape`; backoff tests (US-5). Live 403→refresh→resume and live logout DEFERRED. |
| AC-5 | Decode failure → DOM scrape fallback (not blank); logged-out 200/401 backs off instead of spamming WebView (Decision 7) | PASS | `QuotaScraperOrchestrationTests/decodeFailedFallbackPopulatesStateViaDomScrape`; `UsageAPIClientTests/{garbageJSONReturnsDecodeFailed, loginPageBodyReturnsNotLoggedIn}`; `QuotaScraperBackoffTests/{loggedOutBackoffPersistsAcrossManyAutomaticTicks, repeatedNotLoggedInKeepsWebViewNilAcrossTicks}` |
| AC-6 | No cookie value or request header ever written to logs (Decision 6); cookies attached only to claude.ai requests | PASS | Secret-log guard: `UsageAPIClientTests/noCookieValueInLogs` and `CookieBridgeTests/noCookieValueAppearsInCapturedLogSink` (sentinel cookie value never appears in any captured log line). Host scoping: `CookieBridgeTests/{readReturnsOnlyClaudeAiCookies, writeBackSkipsNonClaudeCookies}`; off-host strip: `UsageAPIClientTests/offHostRedirectStripsCookie`. Confirmed by Task 8 security audit (CLEAN). |
| AC-7 | All existing tests pass; new unit/integration tests green | PASS | 100/100 tests green; pre-existing `QuotaParser`/`JSQuotaParser`/`QuotaPayload`/`QuotaTitleFormatter`/`ScrapeDebug` suites all pass (fallback path intact). |
| AC-8 | No new external dependencies; lint/format/dead-code (`make ci`) clean | PASS | `Package.swift` has zero `.package(...)` deps; `make ci` green (format-check, lint --strict, dead-code --strict all pass, exit 0). |
| AC-9 | Idle memory in Activity Monitor measurably below ~82 MB with no per-tick helper processes | DEFERRED | Activity Monitor, live app. (No-WebView-on-normal-tick invariant covered by US-6/AC-1 tests; absolute RSS measurement cannot run in CI.) |

---

## 3. Findings

**None.** Clean audit. `make ci` is fully green, the build is clean, no new external dependencies, both secret-log guard tests present and passing, and every automatable criterion is covered by a behavior-asserting test (not a mock/import check), consistent with the Task 7/8/9 audit verdicts (all clean, no blockers).

No criterion is in an undefined state: every criterion is either PASS (automated) or cleanly DEFERRED with a named live-verification tool.

---

## 4. Deferred to post-deploy QA — manual checklist (lead/user)

These are Cloudflare-gated / require Activity Monitor or a live logged-in claude.ai session, and are non-deterministic in CI. Tools per the tech-spec Agent Verification Plan: bash (`make build` / run app), `log stream` / Console.app for AppLog, Activity Monitor (manual).

- [ ] **Logged-in menu-bar parity (US-1, US-6 visible side, AC-1).**
  Build + run logged in: `make update` (or `make build` then launch the app). Open claude.ai/settings/usage. Confirm the menu bar shows the **same** current %, weekly %, and **both** reset times, and that it refreshes about once per minute. In Console.app filter on the ClaudeCounter AppLog scraper category — confirm the per-minute updates are API-path (no WebView instantiation log) on normal ticks.

- [ ] **Memory / no per-tick helpers (US-6, AC-9).**
  With the app running and idle for a few minutes, open Activity Monitor. Confirm steady-state RSS is materially below ~82 MB (target ~25–35 MB) and that **no** transient `ClaudeCounter (WebContent)` / GPU / Networking helper processes spawn on each minute tick. Compare against the pre-feature ~82 MB baseline.

- [ ] **Resilience: 403 → one WebView refresh → API resumes (US-4, AC-4).**
  Clear/expire `cf_clearance` from the WKWebsiteDataStore (e.g. via the app's stored WebKit data or by waiting for natural expiry). Watch AppLog: confirm exactly **one** WebView refresh fires (cookie refresh), then subsequent ticks resume the API path. No repeated WebView spin-up.

- [ ] **Auth: logout backoff + login resume (US-5, AC-4).**
  Log out of claude.ai. Confirm the app stops updating gracefully (no crash, no per-tick WebView spam — AppLog shows the Decision-7 backoff suppressing the fallback). Open the usage window → it re-probes and surfaces login. Log back in → updates resume on the next tick / window open.

---

## 5. Overall verdict

**READY for user (post-deploy) verification.**

- `make ci` exit code 0; 100/100 tests green; build clean; no new external deps; both secret-log guards present and passing.
- All deterministic acceptance criteria PASS via behavior-asserting automated tests.
- The remaining criteria are cleanly DEFERRED to live verification (menu-bar parity, Activity Monitor memory + no per-tick helpers, real 403→WebView-refresh→resume, logout backoff/login resume) with exact manual steps above.
- Zero findings, zero blockers. Nothing is in an ambiguous "neither pass nor cleanly deferred" state.
