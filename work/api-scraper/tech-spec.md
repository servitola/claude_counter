---
created: 2026-06-17
status: draft
branch: feature/api-scraper
size: M
---

# Tech Spec: JSON API scraper (drop per-minute WebView)

## Solution

Replace the per-minute WKWebView DOM scrape with a direct authenticated
HTTP call to claude.ai's internal usage endpoint, made through
`URLSession`. The session reuses the cookies already stored in the
shared `WKWebsiteDataStore.default()` (where the existing login lives),
so no re-auth is needed.

The spike established two load-bearing facts:

1. `GET https://claude.ai/api/organizations/{org_uuid}/usage` returns the
   exact data the app needs as structured JSON, including ISO-8601 reset
   timestamps in a `limits[]` array.
2. **curl is blocked (HTTP 403, Cloudflare challenge); URLSession passes
   (HTTP 200).** Cloudflare gates on the TLS/JA3 fingerprint, and Apple's
   networking stack presents a browser-like fingerprint that the stored
   `cf_clearance` cookie validates against. This is why the rewrite must
   use `URLSession`, not a shelled-out HTTP client.

WebKit is **not** removed from the app. It stays for two jobs: the login
window, and refreshing Cloudflare/session cookies when the API path
starts returning 403. The win is that on the normal path no WKWebView is
instantiated, so the WebContent/GPU/Networking helper processes never
spawn and the idle resident set drops.

The existing DOM-scrape pipeline (`QuotaScraper+JS`, `QuotaParser`,
`QuotaPayload`) is retained as a last-resort fallback (see Decision 4),
not deleted — cheap insurance against the unversioned internal endpoint
changing shape.

## Architecture

### What we're building/modifying

- **`UsageAPIClient` (new)** — owns a `URLSession`, performs org-uuid
  discovery and the `/usage` fetch, decodes JSON into typed models,
  returns a `ClaudeUsage` or a typed failure (`.needsCookieRefresh`,
  `.notLoggedIn`, `.decodeFailed`, `.transport`).
- **`CookieBridge` (new)** — copies claude.ai cookies from
  `WKWebsiteDataStore.default().httpCookieStore` into the API client's
  request just before each fetch.
- **`UsageAPIModels` (new)** — `Decodable` structs for the
  `/organizations` and `/usage` responses (`UsageResponse`, `UsageLimit`).
- **`OrgIDStore` (new)** — caches the discovered org UUID in
  `UserDefaults`; invalidated on auth/not-found failures.
- **`QuotaScraper` (modify)** — becomes the orchestrator: on each tick
  call `UsageAPIClient` first; only on `.needsCookieRefresh` /
  `.notLoggedIn` / `.decodeFailed` fall through to the existing WebView
  path (which refreshes cookies, surfaces login, and DOM-scrapes as the
  ultimate fallback). Timer, watchdog, wake-observer, and AppState wiring
  are preserved.
- **`QuotaParser` / `QuotaPayload` / `QuotaScraper+JS/Extract/Navigation`
  (retain)** — unchanged in logic; demoted to the fallback path only.

### How it works

Normal tick (logged in, fresh cookies):

```
Timer (60s) ─▶ QuotaScraper.scrape()
                 │
                 ├─▶ UsageAPIClient.fetch()
                 │     ├─ CookieBridge: pull claude.ai cookies from WKWebsiteDataStore
                 │     ├─ OrgIDStore: cached uuid? ─no─▶ GET /api/organizations ─▶ cache
                 │     ├─ GET /api/organizations/{uuid}/usage  (URLSession, Safari UA)
                 │     └─ decode limits[] ─▶ ClaudeUsage
                 └─▶ AppState.usage = result      (no WKWebView instantiated)
```

Fallback tick (403 / challenge HTML / not logged in / decode fail):

```
UsageAPIClient.fetch() ─▶ .needsCookieRefresh
   │
   └─▶ existing ephemeral WKWebView path (load claude.ai/settings/usage)
         ├─ passes Cloudflare → fresh cf_clearance written to shared store
         ├─ if /login → wait for user (existing behavior)
         └─ DOM-scrape succeeds → AppState updated; next tick uses API again
```

Mapping `limits[]` → `ClaudeUsage`:
- `currentPercent` / `currentResetAt` ← entry with `kind == "session"`
  (fallback `group == "session"`).
- `weeklyPercent` / `weeklyResetAt` ← entry with `kind == "weekly_all"`
  (fallback `group == "weekly"`, choosing the unscoped one).
- `resets_at` (ISO-8601) parsed straight to `Date` via
  `ISO8601DateFormatter` (with fractional seconds) — no minutes math.
- `updatedAt` ← now.

### Shared resources

| Resource | Owner (creates) | Consumers | Instance count |
|----------|----------------|-----------|----------------|
| `WKWebsiteDataStore.default()` cookie store | WebKit (system) | CookieBridge (read), WebView fallback (read/write) | 1 (singleton) |
| `URLSession` for API | UsageAPIClient | UsageAPIClient | 1 |
| Org UUID cache | OrgIDStore (UserDefaults) | UsageAPIClient | 1 |

## Decisions

### Decision 1: URLSession, not curl or a custom HTTP client
**Decision:** Use `URLSession` (system networking) for the API calls.
**Rationale:** Spike proved Cloudflare returns 403 to curl but 200 to
URLSession with identical cookies + UA. Cloudflare validates the TLS/JA3
fingerprint against `cf_clearance`; only Apple's stack matches.
**Alternatives considered:** curl/libcurl (blocked by Cloudflare);
bringing a fingerprint-spoofing client (heavy dependency, fragile, defeats
the "no new deps" goal).

### Decision 2: Reuse cookies from WKWebsiteDataStore, don't re-auth
**Decision:** Read claude.ai cookies (`sessionKey`, `cf_clearance`,
`__cf_bm`, …) from `WKWebsiteDataStore.default().httpCookieStore` and
attach them to each request.
**Rationale:** Login already persists there; no separate auth flow or
token storage needed. `__cf_bm`/`sessionKey` auto-refresh via Set-Cookie
on successful responses if we persist them back; `cf_clearance` only needs
the WebView when it fully expires.
**Alternatives considered:** Maintaining an independent cookie jar
(duplicates state, drifts from the login window); Keychain token storage
(claude.ai uses cookie auth, not bearer tokens).

### Decision 3: WebView retained for cookie-refresh + login, not removed
**Decision:** Keep WKWebView, instantiated only on the fallback path.
**Rationale:** `cf_clearance` expires and is IP-bound; refreshing it
requires passing Cloudflare's JS challenge, which only a real browser
engine can do. Login also requires it. Memory win comes from *not
instantiating it every minute*, not from unlinking WebKit.
**Alternatives considered:** Pure-URLSession with no WebView (breaks the
moment cf_clearance expires — app would silently die); headless challenge
solver (out of scope, fragile).

### Decision 4: Keep DOM-scrape pipeline as last-resort fallback
**Decision:** Retain `QuotaParser`/`QuotaPayload`/`extractionJS`; the
WebView fallback still DOM-scrapes when it runs.
**Rationale:** The `/usage` endpoint is an internal, unversioned API; if
Anthropic renames fields the app must degrade to the proven scrape rather
than go blank. The code already exists and is well-tested — keeping it is
near-zero cost.
**Alternatives considered:** Delete it for cleanliness (loses the safety
net; the whole value of the app is showing correct numbers) — rejected by
owner: correctness of the numbers outweighs a smaller code surface.
**Status:** DECIDED — DOM-scrape pipeline is retained as the last-resort
fallback. The regex/JS parser code stays in the tree.

### Decision 5: Map from `limits[]`, not top-level `five_hour`/`seven_day`
**Decision:** Canonical source is the `limits[]` array (`kind`/`percent`/
`resets_at`), with the flat fields as fallback.
**Rationale:** `limits[]` is self-describing (group/kind/severity/scope)
and already encodes session vs weekly_all vs weekly_scoped; the flat
fields duplicate it and are more likely to be deprecated.
**Alternatives considered:** Use `five_hour`/`seven_day` top-level keys
(works today, but less explicit and harder to extend to scoped limits).

## Data Models

```swift
// Decodable — /api/organizations
struct OrgSummary: Decodable { let uuid: String }

// Decodable — /api/organizations/{uuid}/usage
struct UsageResponse: Decodable {
    let limits: [UsageLimit]
}
struct UsageLimit: Decodable {
    let group: String        // "session" | "weekly"
    let kind: String         // "session" | "weekly_all" | "weekly_scoped"
    let percent: Double
    let resetsAt: Date?      // from "resets_at", ISO-8601
    let isActive: Bool?
    // scope ignored for now (used only by weekly_scoped)
    enum CodingKeys: String, CodingKey {
        case group, kind, percent, isActive = "is_active", resetsAt = "resets_at"
    }
}

// API result envelope returned to QuotaScraper
enum UsageFetchResult {
    case success(ClaudeUsage)
    case needsCookieRefresh   // 403 / Cloudflare challenge HTML
    case notLoggedIn          // 401 / redirect to /login
    case decodeFailed         // 200 but unexpected shape
    case transport(Error)     // network error
}
```

`ClaudeUsage` (existing) is unchanged.

## Dependencies

### New packages
- None.

### Using existing (from project)
- `WebKit` — `WKWebsiteDataStore.default().httpCookieStore` for cookie
  read (CookieBridge); existing WebView path unchanged.
- `Foundation` — `URLSession`, `JSONDecoder`, `ISO8601DateFormatter`,
  `UserDefaults`.
- `AppLog` — existing os.Logger wrapper for the new client's logging.

## Testing Strategy

**Feature size:** M

### Unit tests
- `UsageResponse` decodes the real spike JSON fixture → correct
  `limits[]` (session/weekly_all/weekly_scoped) with parsed dates.
- `limits[]` → `ClaudeUsage` mapping: picks session for current, weekly_all
  for weekly; `resets_at` → `currentResetAt`/`weeklyResetAt`.
- Mapping fallbacks: missing `weekly_all` falls back to flat `seven_day`;
  malformed/empty `limits[]` → `.decodeFailed`.
- HTTP classification: 403 + challenge HTML → `.needsCookieRefresh`;
  401/login redirect → `.notLoggedIn`; 200 + garbage → `.decodeFailed`.
- `OrgIDStore`: caches uuid, invalidates on failure.
- ISO-8601 parsing with and without fractional seconds.
- Existing `QuotaParser`/JS tests remain green (fallback path intact).

### Integration tests
- `UsageAPIClient.fetch()` against a stubbed `URLProtocol` returning
  recorded fixtures for `/organizations` then `/usage` → `ClaudeUsage`.
- Fallback orchestration: API returns `.needsCookieRefresh` → scraper
  invokes the WebView path (verified via a seam/spy, not a live network).

### E2E tests
- None automated (requires a live logged-in claude.ai session). Covered by
  the Agent Verification Plan smoke check instead.

## Agent Verification Plan

**Source:** user-spec "How to verify" section.

### Verification approach
- Smoke: build and run the app logged in; confirm the menu bar shows the
  same current/weekly % and reset times as claude.ai/settings/usage, and
  refreshes each minute.
- Memory: read Activity Monitor — steady-state RSS materially below 82 MB
  and no per-tick WebContent/GPU helper processes.
- Resilience: clear `cf_clearance` from the store; confirm one WebView
  refresh occurs then the API path resumes (via `AppLog` scraper logs).
- Auth: log out → graceful stop + login on window open; log in → resumes.

### Tools required
- bash (build via `make`, run app, `log stream`/Console for AppLog),
  Activity Monitor (manual/user). No Playwright/Telegram MCP needed.

## Risks

| Risk | Mitigation |
|------|-----------|
| `cf_clearance` expires / IP change → API 403 | WebView fallback refreshes it automatically (Decision 3); next tick resumes API. |
| Internal `/usage` endpoint changes shape (unversioned) | `.decodeFailed` → DOM-scrape fallback (Decision 4); unit test pinned to fixture flags drift early. |
| Cookie read race (WKHTTPCookieStore is async/MainActor) | CookieBridge fetches cookies on MainActor before building the request; fetch proceeds off-main. |
| Multiple orgs on account → wrong uuid | Pick active/first org; re-discover on not-found; cache invalidation on failure. |
| URLSession persists cookies separately from WebView and they drift | Use the WebView store as the single source of truth each fetch; write refreshed Set-Cookie back to it, or disable URLSession's own cookie storage and always bridge. |
| Memory win smaller than hoped (WebKit still linked) | Expectation set in user-spec: ~25–35 MB, not 10×; primary saving is no per-tick helper processes. |

## User-Spec Deviations

None.

## Acceptance Criteria

- [ ] Logged-in app shows current %, weekly %, and both reset times
      matching claude.ai/settings/usage, refreshed every 60 s, via the API
      path (no WKWebView instantiated on a normal tick).
- [ ] Org uuid is discovered once and cached; cleared on auth failure.
- [ ] `resets_at` ISO-8601 timestamps map correctly to
      `currentResetAt`/`weeklyResetAt`.
- [ ] 403/challenge → automatic WebView cookie refresh → API resumes;
      logged-out → graceful wait + login; both verified.
- [ ] Decode failure falls back to DOM scrape rather than blanking.
- [ ] Idle memory in Activity Monitor is measurably below current ~82 MB
      with no per-tick helper processes.
- [ ] All existing tests pass; new unit/integration tests green.
- [ ] No new external dependencies; lint/format/dead-code (`make ci`) clean.

## Implementation Tasks

### Wave 1 (независимые)

#### Task 1: API models + JSON decoding
- **Description:** Add `UsageAPIModels` (`OrgSummary`, `UsageResponse`,
  `UsageLimit`) and an ISO-8601 date decoding strategy. Decodes the
  recorded spike fixtures for `/organizations` and `/usage`. Pure
  Foundation, no networking.
- **Skill:** code-writing
- **Reviewers:** code-reviewer, test-reviewer
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/UsageAPIModels.swift` (new)
- **Files to read:** `App/Sources/ClaudeCounter/Models/ClaudeUsage.swift`, `work/api-scraper/fixtures/usage.json`

#### Task 2: limits[] → ClaudeUsage mapper
- **Description:** Pure function mapping `UsageResponse.limits[]` to
  `ClaudeUsage` (session→current, weekly_all→weekly, `resets_at`→dates),
  with fallback to flat fields and `.decodeFailed` on empty/garbage.
  Deterministic, testable without network.
- **Skill:** code-writing
- **Reviewers:** code-reviewer, test-reviewer
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/UsageMapper.swift` (new)
- **Files to read:** `App/Sources/ClaudeCounter/Models/ClaudeUsage.swift`, `App/Sources/ClaudeCounter/Scraper/QuotaParser.swift`

#### Task 3: OrgIDStore (uuid cache)
- **Description:** Small UserDefaults-backed cache for the org UUID with
  read/write/invalidate. Used to skip `/organizations` discovery on every
  tick.
- **Skill:** code-writing
- **Reviewers:** code-reviewer, test-reviewer
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/OrgIDStore.swift` (new)
- **Files to read:** `App/Sources/ClaudeCounter/AppState.swift`

### Wave 2 (зависит от Wave 1)

#### Task 4: CookieBridge
- **Description:** Read claude.ai cookies from
  `WKWebsiteDataStore.default().httpCookieStore` on MainActor and produce
  the `Cookie` header / `[HTTPCookie]` for an outgoing request. Single
  source of truth = the WebView store.
- **Skill:** code-writing
- **Reviewers:** code-reviewer, security-auditor, test-reviewer
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/CookieBridge.swift` (new)
- **Files to read:** `App/Sources/ClaudeCounter/Scraper/WebViewFactory.swift`

#### Task 5: UsageAPIClient (URLSession fetch + discovery + classification)
- **Description:** Owns a `URLSession`, performs org discovery (cached via
  OrgIDStore), fetches `/usage` with the Safari UA and bridged cookies,
  decodes via Wave-1 models/mapper, and classifies outcomes into
  `UsageFetchResult` (success / needsCookieRefresh / notLoggedIn /
  decodeFailed / transport).
- **Skill:** code-writing
- **Reviewers:** code-reviewer, security-auditor, test-reviewer
- **Verify-smoke:** with a logged-in store, a one-off Swift harness calling
  `UsageAPIClient.fetch()` prints a populated `ClaudeUsage` (current %,
  weekly %, reset dates) — mirrors the spike's 200 response.
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/UsageAPIClient.swift` (new)
- **Files to read:** `App/Sources/ClaudeCounter/Scraper/WebViewFactory.swift`, `App/Sources/ClaudeCounter/Logging/AppLog.swift`

### Wave 3 (зависит от Wave 2)

#### Task 6: QuotaScraper orchestration (API-first, WebView fallback)
- **Description:** Rewire `QuotaScraper.scrape()` to call `UsageAPIClient`
  first and update AppState on success; on `.needsCookieRefresh` /
  `.notLoggedIn` / `.decodeFailed` fall through to the existing ephemeral
  WebView path (cookie refresh + login + DOM-scrape fallback). Preserve
  timer, watchdog, wake-observer, retry semantics.
- **Skill:** code-writing
- **Reviewers:** code-reviewer, test-reviewer
- **Verify-user:** run logged in → menu bar matches claude.ai usage page,
  refreshes each minute; Activity Monitor shows no per-tick WebContent
  process and lower idle RSS.
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/QuotaScraper.swift`, `App/Sources/ClaudeCounter/Scraper/QuotaScraper+Lifecycle.swift`
- **Files to read:** `App/Sources/ClaudeCounter/Scraper/QuotaScraper+Extract.swift`, `App/Sources/ClaudeCounter/Scraper/QuotaScraper+Navigation.swift`, `App/Sources/ClaudeCounter/ClaudeCounterApp.swift`

### Audit Wave

#### Task 7: Code Audit
- **Description:** Full-feature code quality audit. Read all source files
  created/modified in this feature. Review holistically for cross-component
  issues: cookie-store ownership, single source of truth, fallback
  correctness, concurrency (MainActor/Sendable). Write audit report.
- **Skill:** code-reviewing
- **Reviewers:** none

#### Task 8: Security Audit
- **Description:** Full-feature security audit. Focus on handling of
  session cookies (`sessionKey`, `cf_clearance`): no logging of secrets,
  no leakage to disk/debug dumps, correct host scoping of cookies on
  requests. OWASP Top 10 across the new client. Write audit report.
- **Skill:** security-auditor
- **Reviewers:** none

#### Task 9: Test Audit
- **Description:** Full-feature test quality audit. Verify coverage of
  decode, mapping, HTTP classification, fallback orchestration; meaningful
  assertions; URLProtocol stubbing correctness. Write audit report.
- **Skill:** test-master
- **Reviewers:** none

### Final Wave

#### Task 10: Pre-deploy QA
- **Description:** Acceptance testing: run `make ci` (build, unit +
  integration tests, lint, format, dead-code), verify all acceptance
  criteria from user-spec and tech-spec.
- **Skill:** pre-deploy-qa
- **Reviewers:** none
</content>
