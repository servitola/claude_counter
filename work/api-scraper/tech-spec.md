---
created: 2026-06-17
status: approved
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
token storage needed.
**Mechanics (pinned to avoid cookie drift):**
- The `URLSession` runs with **no cookie jar of its own**:
  `httpCookieAcceptPolicy = .never`, `httpShouldSetCookies = false`,
  `httpCookieStorage = nil`. The WebView store is the single source of
  truth, re-read each fetch.
- **Host scoping:** only cookies whose domain matches `claude.ai` are
  attached, and a redirect delegate strips the `Cookie` header if a
  redirect leaves `claude.ai`. Cookies are never sent off-host.
- **Write-back:** `Set-Cookie` headers from successful responses
  (rotating `__cf_bm`, refreshed `sessionKey`) are written **back into
  `WKWebsiteDataStore.default().httpCookieStore`** so the shared store
  stays fresh and the WebView fallback fires less often. Owner: CookieBridge
  (Task 4) for read + write-back; UsageAPIClient (Task 5) wires it in.
**Alternatives considered:** Maintaining an independent cookie jar
(duplicates state, drifts from the login window); Keychain token storage
(claude.ai uses cookie auth, not bearer tokens); never writing cookies
back (store goes stale, forces a WebView refresh every ~30 min when
`__cf_bm` rotates — wasteful).

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

### Decision 6: Secrets never touch the logs
**Decision:** Cookie values (`sessionKey`, `cf_clearance`, `__cf_bm`) and
request headers are never logged. The new client logs only value-free
events (status code, result case, org-discovery outcome); any token-
adjacent field uses `privacy: .private`. The existing `ScrapeDebugLog`
keeps dumping DOM text only; a `.decodeFailed` repro dump, if added, is
**response-body-only** — never the request or its `Cookie` header.
**Rationale:** The existing `AppLog` calls use `privacy: .public`; copying
that pattern onto a cookie/header log would leak the session into unified
logging in cleartext. Must be forbidden up front, not caught in review.
**Alternatives considered:** Rely on the security audit to catch it later
(too late — the leak ships first).

### Decision 7: Back off the WebView fallback when logged out
**Decision:** On `.notLoggedIn`, do **not** spin up the WebView fallback
every 60 s tick. Set a "logged-out" flag that suppresses the fallback on
subsequent ticks; clear it on system wake and when the usage window is
opened (both already exist as triggers), and re-probe the API then.
**Rationale:** US-5 requires "no spam" when logged out. A naive
API→WebView fallback would relaunch the login-detecting WebView every
minute. The current app is quiet when logged out; this preserves that.
**Alternatives considered:** Fixed long backoff timer (extra timer state);
always falling back (regresses US-5).

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
    case needsCookieRefresh   // 403 + Cloudflare challenge HTML ("Just a moment...")
    case notLoggedIn          // 401, redirect to /login, OR 200 whose body is the login page
    case decodeFailed         // 200, JSON, but unexpected/unmappable shape
    case transport(Error)     // network error
}
```

Classification order matters: a 200 that is actually the login HTML must
resolve to `.notLoggedIn` (triggers backoff per Decision 7), **not**
`.decodeFailed` (which would trigger the DOM-scrape fallback). Detect by
content-type / a login-page marker before attempting JSON decode.

Date decoding: `resets_at` is ISO-8601 with fractional seconds and a
`+00:00` offset (`2026-06-17T13:49:59.900458+00:00`). Use a custom
`JSONDecoder.dateDecodingStrategy` that tries an `ISO8601DateFormatter`
with `.withFractionalSeconds` first, then falls back to one without —
claude.ai is not guaranteed to always include the fractional part.

`ClaudeUsage` (existing) is unchanged.

## Dependencies

### New packages
- None.

### Using existing (from project)
- `WebKit` — `WKWebsiteDataStore.default().httpCookieStore` for cookie
  read + Set-Cookie write-back (CookieBridge); existing WebView path
  unchanged.
- `Foundation` — `URLSession`, `JSONDecoder`, `ISO8601DateFormatter`,
  `UserDefaults`, `URLProtocol` (test stubbing).
- `AppLog` — existing os.Logger wrapper, subject to Decision 6 (no secrets).

### Build/package changes
- `App/Package.swift` test target gains `resources: [.copy("Fixtures/...")]`
  (or a `Bundle.module` path) so the recorded `usage.json` /
  `organizations.json` fixtures load deterministically in unit tests. The
  fixtures committed under `work/api-scraper/fixtures/` are the source of
  truth; copy them into the test target's resources.

## Testing Strategy

**Feature size:** M

### Unit tests
- `UsageResponse` decodes the committed `usage.json` fixture → correct
  `limits[]` (session/weekly_all/weekly_scoped) with exact parsed `Date`s.
- `limits[]` → `ClaudeUsage` mapping: picks `kind == session` for current,
  `kind == weekly_all` for weekly (NOT `weekly_scoped`); `resets_at` →
  `currentResetAt`/`weeklyResetAt` asserted as exact Dates.
- Mapping fallbacks: missing `weekly_all` falls back to flat `seven_day`;
  empty `limits[]` with no flat fields → `.decodeFailed`.
- HTTP classification: 403 + challenge HTML → `.needsCookieRefresh`;
  401 or redirect to `/login` → `.notLoggedIn`; **200 whose body is the
  login page → `.notLoggedIn`** (not `.decodeFailed`); 200 + JSON garbage
  → `.decodeFailed`. The degenerate bodies (Cloudflare "Just a moment…"
  HTML, login-page HTML, garbage JSON) are pinned as small inline string
  fixtures in the test so classification is deterministic.
- ISO-8601 parsing: with fractional seconds AND without → both yield the
  correct Date (two-formatter strategy from Data Models).
- `OrgIDStore`: caches uuid, invalidates on failure — run against an
  **isolated `UserDefaults(suiteName:)`**, not `.standard`, to avoid
  shared-state bleed between tests.
- Org discovery picks the right uuid when `/organizations` returns
  **multiple** orgs (add a two-org fixture variant; assert the
  active/first is chosen and cached).
- `percent` rounding: `Double` → `Int` for `ClaudeUsage` truncates as
  expected for fractional values (e.g. `2.9` → `2`), matching the existing
  `QuotaParser` behavior.
- Existing `QuotaParser`/JS tests remain green (fallback path intact).

### Integration tests
- `UsageAPIClient.fetch()` against a stubbed `URLProtocol` (injected via a
  DI'd `URLSessionConfiguration`), routing by path: first `/organizations`
  then `/organizations/{uuid}/usage` → asserts a populated `ClaudeUsage`.
- Cookie write-back: a stub response carrying `Set-Cookie` results in the
  cookie reaching the (test-injected) WebView cookie store.
- Secret-log guard (Decision 6): drive a fetch through a captured log sink
  with a sentinel cookie value; assert the sentinel never appears in any
  emitted log line (header or body).
- Fallback orchestration: API stub returns `.needsCookieRefresh`; assert
  the scraper enters the WebView path AND that, given a DOM-scrape success,
  `AppState.usage` ends up populated (assert end state, not just that a
  spy method was called).
- Backoff: repeated `.notLoggedIn` does not re-enter the WebView path on
  every tick (Decision 7) — assert an observable (WebView never
  instantiated / fallback-invocation counter stays 0 across N ticks while
  logged-out), then a wake/window-open event clears the flag and re-probes.

### E2E tests
- None automated (requires a live logged-in claude.ai session; Cloudflare-
  gated and non-deterministic). Covered by the Agent Verification Plan
  smoke check instead.

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
| URLSession persists cookies separately from WebView and they drift | URLSession runs with no cookie jar (`.never`); WebView store is sole source of truth, re-read each fetch; `Set-Cookie` written back to it (Decision 2). |
| Session cookies leak into unified logging | Decision 6: never log cookie values/headers; `.private` for token fields; security audit (Task 8) enforces. |
| Logged-out state re-triggers WebView every tick (US-5 "no spam") | Decision 7: `.notLoggedIn` sets a backoff flag; fallback suppressed until wake/window-open. |
| 200 login page misclassified as decode failure → needless DOM fallback | Classify a 200 login-page body as `.notLoggedIn` before JSON decode (Data Models). |
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
- [ ] Decode failure (unmappable JSON) falls back to DOM scrape rather
      than blanking; a logged-out 200/401 backs off instead of spamming
      the WebView (Decision 7).
- [ ] No cookie value or request header is ever written to logs
      (Decision 6); cookies are attached only to claude.ai requests.
- [ ] Idle memory in Activity Monitor is measurably below current ~82 MB
      with no per-tick helper processes.
- [ ] All existing tests pass; new unit/integration tests green.
- [ ] No new external dependencies; lint/format/dead-code (`make ci`) clean.

## Implementation Tasks

### Wave 1 (независимые)

#### Task 1: API models + JSON decoding + test fixtures
- **Description:** Add `UsageAPIModels` (`OrgSummary`, `UsageResponse`,
  `UsageLimit`) with the two-formatter ISO-8601 date strategy. Copy the
  committed `usage.json` / `organizations.json` fixtures into the test
  target and wire `Package.swift` resources so they load via `Bundle.module`.
  Pure Foundation, no networking.
- **Skill:** code-writing
- **Reviewers:** code-reviewer, test-reviewer
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/UsageAPIModels.swift` (new), `App/Package.swift`, `App/Tests/ClaudeCounterTests/Fixtures/usage.json` (new), `App/Tests/ClaudeCounterTests/Fixtures/organizations.json` (new)
- **Files to read:** `App/Sources/ClaudeCounter/Models/ClaudeUsage.swift`, `work/api-scraper/fixtures/usage.json`, `work/api-scraper/fixtures/organizations.json`, `App/Package.swift`

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

#### Task 4: CookieBridge (read + write-back, host-scoped)
- **Description:** Read claude.ai-scoped cookies from
  `WKWebsiteDataStore.default().httpCookieStore` on MainActor and produce
  the `[HTTPCookie]`/`Cookie` header for an outgoing request (claude.ai
  only). Write `Set-Cookie` from successful responses back into the same
  store so it stays fresh (Decision 2). Single source of truth = WebView
  store. No cookie value is ever logged (Decision 6).
- **Skill:** code-writing
- **Reviewers:** code-reviewer, security-auditor, test-reviewer
- **Files to modify:** `App/Sources/ClaudeCounter/Scraper/CookieBridge.swift` (new)
- **Files to read:** `App/Sources/ClaudeCounter/Scraper/WebViewFactory.swift`, `App/Sources/ClaudeCounter/Logging/AppLog.swift`

#### Task 5: UsageAPIClient (URLSession fetch + discovery + classification)
- **Description:** Owns a `URLSession` configured with no cookie jar
  (`.never`, host-scoped via CookieBridge + off-host redirect stripping),
  performs org discovery (cached via OrgIDStore), fetches `/usage` with the
  Safari UA and bridged cookies, decodes via Wave-1 models/mapper, and
  classifies outcomes into `UsageFetchResult` — including a 200 login-page
  body → `.notLoggedIn` (not `.decodeFailed`). The `URLSessionConfiguration`
  is injectable so tests can stub via `URLProtocol`.
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
  `.decodeFailed` fall through to the existing ephemeral WebView path
  (cookie refresh + DOM-scrape fallback). On `.notLoggedIn` apply the
  Decision 7 backoff (suppress WebView fallback until wake/window-open),
  preserving today's quiet-when-logged-out behavior. Preserve timer,
  watchdog, wake-observer, retry semantics.
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
