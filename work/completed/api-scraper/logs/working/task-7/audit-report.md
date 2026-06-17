# Task 7 — Cross-Component Code Audit (api-scraper)

**Scope:** Holistic, cross-component audit of the JSON-API-scraper rewrite
(Tasks 1–6). Analysis only — no source files modified. Per-file reviews already
happened in each task; this audit looks only at issues that surface when the
pieces are seen together.

**Files audited (final state):**
`UsageAPIModels.swift`, `UsageMapper.swift`, `OrgIDStore.swift`,
`CookieBridge.swift`, `UsageAPIClient.swift`, `UsageResponseClassifier.swift`,
`OffHostRedirectGuard.swift`, `QuotaScraper.swift`,
`QuotaScraper+Orchestrator.swift`, `QuotaScraper+Lifecycle.swift`,
`QuotaScraper+Navigation.swift`, `QuotaScraper+Extract.swift`,
`QuotaScraper+JS.swift`, `WebViewFactory.swift`, plus integration points
`StatusBarController+Menu.swift`, `ClaudeCounterApp.swift`, `AppState.swift`,
`AppLog.swift`, `ClaudeUsage.swift`.

## Overall verdict

**Issues found — but none critical and none blocking.** The feature is
well-built and matches the tech-spec design closely. Cookie single-source-of-
truth (Decision 2), host scoping, Decision-7 backoff, and Swift 6 concurrency
are all sound. The findings are one HIGH consistency gap in Cloudflare-challenge
routing on the discovery call, plus several MEDIUM/LOW items around fallback
routing nuance, over-broad login detection, and minor duplication. The HIGH item
is a routing inconsistency (wrong-but-recoverable fallback path), not a
correctness or security defect.

---

## Findings

### F1 — HIGH — Cloudflare challenge during org discovery routes to `.decodeFailed`, not `.needsCookieRefresh`

- **Issue:** Decision 4/3 intends a 403 Cloudflare challenge ("Just a moment…")
  to map to `.needsCookieRefresh`, so the WebView fallback refreshes
  `cf_clearance` and the next tick resumes the API. The `/usage` call does this
  (`classifyUsage` runs `isChallenge` first). But the **org-discovery** call
  (`resolveOrgUUID`) does **not** run the challenge check: it calls
  `authResult(for:response:)` (which has no 403-challenge branch), then
  `guard response.statusCode == 200 else { return .failed(.decodeFailed) }`. So a
  403 challenge on `GET /api/organizations` (e.g. cold start with an empty
  `OrgIDStore` and an expired `cf_clearance`) resolves to `.decodeFailed`.
  Both `.decodeFailed` and `.needsCookieRefresh` ultimately spin the WebView
  fallback, so the user still recovers — but the path is wrong: the log says
  `decodeFailed` (misleading for the unversioned-shape-change signal that
  `.decodeFailed` is meant to mean), and it muddies the Decision-4 vs Decision-3
  distinction. Worse, on a *fresh install* (no cached uuid) the very first fetch
  after a cookie expiry always hits discovery first, so this is the common cold
  path, not an edge.
- **Location:** `UsageAPIClient.swift:resolveOrgUUID()` (the
  `guard response.statusCode == 200 else { return .failed(.decodeFailed) }`
  branch) — missing the `isChallenge` pre-check that
  `UsageResponseClassifier.swift:classifyUsage(data:response:)` already performs.
- **Fix:** In `resolveOrgUUID`, before the `statusCode == 200` guard, add the
  same challenge check used in `classifyUsage`:
  `if response.statusCode == 403, isChallenge(data: data, response: response) { log(...); return .failed(.needsCookieRefresh) }` (cache stays valid — only
  cookies are stale, matching the `/usage` comment). Best done by extracting the
  shared "challenge → needsCookieRefresh / auth → notLoggedIn / non-200 →
  decodeFailed" preamble into one helper that both the discovery and usage calls
  invoke, removing the divergence permanently.

### F2 — MEDIUM — `isLoginPage` substring `"/login"` can misclassify a non-login HTML 200 as `.notLoggedIn`

- **Issue:** `isLoginPage(data:)` returns true if the body contains the bare
  substring `"/login"` (third OR-branch). This is gated behind
  `isHTML(response)`, so a JSON usage response is safe. But any HTML 200 that is
  *not* the login page yet mentions a `/login` link anywhere (a generic error
  page, a marketing shell, a maintenance page) would be classified
  `.notLoggedIn` and arm the Decision-7 backoff — suppressing the WebView
  fallback and going quiet when the right move might be a cookie refresh or a
  DOM scrape. The first two markers (`"log in to claude"`,
  `action="/login"`) are specific; the third is the loose one.
- **Location:** `UsageResponseClassifier.swift:isLoginPage(data:)` — the
  `|| body.contains("/login")` clause.
- **Fix:** Drop the bare `"/login"` substring branch (rely on the two specific
  markers plus the redirect-path check `response.url?.path.contains("/login")`
  already in `authResult`), or tighten it to a form/link attribute
  (`href="/login"` / `action="/login"`). The redirect case is independently
  covered by the `response.url?.path` check, so removing the loose body match
  loses no real coverage.

### F3 — MEDIUM — WebView-fallback navigation failure retries the API path, not the WebView

- **Issue:** On the fallback (DOM-scrape) path, a navigation failure
  (`didFail` / `didFailProvisional` / WebContent termination) calls
  `handleFailure()`, which tears down and — if `retryCount < maxRetries` —
  re-invokes `scrape()`. Post-Task-6, `scrape()` is the **API-first** orchestrator,
  not the old WebView body. So a WebView fallback that fails to load does not
  retry the WebView; it re-probes the API. If the API result that sent us into
  the fallback was `.needsCookieRefresh`/`.decodeFailed` and is sticky, the retry
  loops back through `apply()` and re-enters the fallback anyway, so behavior is
  *eventually* equivalent — but the `retryCount`/`maxRetries` mechanism no longer
  means "retry this WebView load once"; it now means "re-run the whole API
  orchestration once after a 5 s delay." This is a semantic drift worth making
  explicit, and it interacts with the single-flight guard (the delayed
  `scrape()` may be a no-op if a timer tick is already in flight).
- **Location:** `QuotaScraper+Lifecycle.swift:handleFailure()` →
  `Task { @MainActor in self?.scrape() }`.
- **Fix:** Either (a) document that fallback retry intentionally re-probes the
  full API path (rename/recomment `retryCount` accordingly), or (b) have
  `handleFailure()` retry `runWebViewFallback()` directly so the counter retains
  its original "retry the WebView load" meaning. (a) is the lower-risk choice and
  matches the API-first intent; pick one so the mechanism isn't ambiguous.

### F4 — MEDIUM — `.transport` never surfaces staleness; `AppState.usage` can silently age indefinitely

- **Issue:** Per Decision/spec, `.transport` must not blank `AppState` — and it
  correctly does not (good). But there is no upper bound on how stale the
  displayed numbers may get: a persistent transport failure (Wi-Fi captive
  portal, DNS outage) leaves the last-good `ClaudeUsage` shown indefinitely with
  no "stale" affordance. `ClaudeUsage.updatedAt` exists and would support a
  staleness indicator, but nothing in the menu/status path reads it for that
  purpose. This is consistent with the spec ("does not silently blank") and the
  pre-existing app behavior, so it is not a regression — flagging as a holistic
  gap, not a Task-6 defect.
- **Location:** `QuotaScraper+Orchestrator.swift:apply()` `.transport` case;
  consumer `StatusBarController+Menu.swift` / status rendering (does not use
  `updatedAt` for staleness).
- **Fix:** Out of scope for this feature if the product accepts "show last good
  silently." If staleness UX is wanted, gate a subtle indicator on
  `now - usage.updatedAt > N·interval`. Recommend filing as a follow-up rather
  than fixing here.

### F5 — LOW — `start()` calls `scrape()` (API path) immediately, but the Decision-7 backoff is only clearable via `forceRefresh()`; first-tick logged-out is fine, but cold start cannot DOM-fallback until a real trigger

- **Issue:** At launch, `start()` calls plain `scrape()` (not `forceRefresh()`).
  That is correct for the backoff invariant (the timer path must not clear
  `loggedOut`). But it means: if the very first API probe returns
  `.needsCookieRefresh`/`.decodeFailed`, the fallback runs (good); if it returns
  `.notLoggedIn`, `loggedOut` is set and stays set until wake / window-open /
  Refresh-Now. That is the intended quiet-when-logged-out behavior, so this is
  working as designed — noting only that there is no "first launch always tries
  the WebView once" path. No change needed; documented for completeness.
- **Location:** `QuotaScraper.swift:start()` → `scrape()`.
- **Fix:** None required. (If product wants a guaranteed first-launch login
  surface, call `forceRefresh()` once in `start()` — but that slightly weakens
  the no-spam guarantee on a logged-out cold boot, so leave as-is unless asked.)

### F6 — LOW — `setCookieFields` passes the comma-folded `Set-Cookie` as a single string; relies on `CookieBridge` per-field parsing it can't actually unfold

- **Issue:** `UsageAPIClient.setCookieFields(from:)` reads
  `response.value(forHTTPHeaderField: "Set-Cookie")`, which Foundation returns as
  a **single comma-joined** string when the server sends multiple `Set-Cookie`
  headers, and hands it to `CookieBridge.writeBack` as a one-element array.
  `CookieBridge.writeBack` then re-splits per *array element* (one element) and
  feeds it to `HTTPCookie.cookies(withResponseHeaderFields:)`. The Task-4 comment
  in `CookieBridge` warns that comma-joining is unsafe because `Expires` contains
  commas — yet the client hands it exactly that comma-joined blob. The net effect
  is the RFC-6265 comma hazard the per-field design tried to avoid is reintroduced
  at the API-client boundary: `HTTPCookie.cookies(withResponseHeaderFields:)` is
  reasonably good at splitting Set-Cookie, but a rotating `__cf_bm`/`sessionKey`
  alongside an `Expires=Wed, 09 Jun ...` can still mis-split, silently dropping a
  rotated cookie and forcing an earlier-than-necessary WebView refresh. This is a
  freshness/efficiency risk, not a correctness or security one (a dropped
  write-back just means the shared store stays slightly staler).
- **Location:** `UsageAPIClient.swift:setCookieFields(from:)` (returns
  `[raw]` — single folded value) vs the per-field intent documented in
  `CookieBridge.swift:writeBack(setCookieHeaders:responseURL:)`.
- **Fix:** Prefer the unfolded headers when available:
  `(response as? HTTPURLResponse)` does not expose them, but
  `HTTPURLResponse` on the macOS 13+ SDK supports
  `value(forHTTPHeaderField:)` only folded — so the robust path is to use the
  `URLSession` delegate or `allHeaderFields` carefully, or accept the current
  behavior and document that `HTTPCookie.cookies(withResponseHeaderFields:)` is
  trusted to split. Given Apple's parser is the same one `CookieBridge` already
  relies on, lowest-risk action is to **document** that the per-field guarantee
  is best-effort at this boundary. No functional change strictly required.

### F7 — LOW — `OffHostRedirectGuard` strips the `Cookie` header but the redirected request may still carry it if set by URLSession from a jar

- **Issue:** The guard correctly nils the `Cookie` header on an off-host
  redirect. Because the session runs with no cookie jar
  (`httpCookieStorage = nil`, `.never`, `httpShouldSetCookies = false`), the only
  `Cookie` header is the one the client set manually, and stripping it is
  sufficient — so this is **correct as built**. Flagging only the implicit
  coupling: the guard's safety depends entirely on `productionConfiguration()`
  keeping the jar disabled. If a future change re-enables the cookie jar, the
  guard would still strip the manual header but URLSession could re-add jar
  cookies after the delegate returns. The invariant is undocumented at the guard.
- **Location:** `OffHostRedirectGuard.swift:urlSession(_:task:willPerform…)` ↔
  `UsageAPIClient.swift:productionConfiguration()`.
- **Fix:** Add a one-line comment in `OffHostRedirectGuard` noting it is correct
  only because the session owns no cookie jar (cross-reference
  `productionConfiguration()`), so the coupling can't be silently broken later.

### F8 — LOW — Duplicated host-scoping logic across three types

- **Issue:** "Is this claude.ai?" is implemented three times with three slightly
  different rules: `CookieBridge.isClaudeScoped` (bare host or leading-dot,
  case-insensitive, exact only — no subdomains), `OffHostRedirectGuard.isClaudeHost`
  (exact OR `.claude.ai` suffix — subdomains allowed), and the literal
  `UsageAPIClient.host` / `CookieBridge.host` constants. The cookie scoping is
  deliberately stricter than the redirect scoping (cookies: exact host only;
  redirect: allow subdomains), so this is defensible — but it is undocumented why
  they differ, and a reader could "fix" one to match the other and introduce a
  scoping regression.
- **Location:** `CookieBridge.swift:isClaudeScoped(_:)`,
  `OffHostRedirectGuard.swift:isClaudeHost(_:)`,
  `UsageAPIClient.host` / `CookieBridge.host`.
- **Fix:** Leave the two rules separate (they are intentionally different) but
  add a comment on each explaining the asymmetry (cookies must be exact-host to
  avoid sending the session cookie to a subdomain; redirects allow subdomains so
  an on-host SPA redirect is followed). Optionally centralize the `"claude.ai"`
  literal into one constant referenced by both (currently two `static let host`).

### F9 — LOW — `cookieHeader()` re-reads (and re-logs) the store; minor duplicate work + duplicate log line per fetch

- **Issue:** `UsageAPIClient.fetch()` and `resolveOrgUUID()` each call
  `cookies.header()`, and `CookieBridge.cookieHeader()` calls `read()` which logs
  `cookie read host=… count=…` every time. A single `fetch()` that performs both
  discovery and the usage call reads the cookie store twice and emits two read
  log lines. Functionally fine (cookies should be re-read each fetch per
  Decision 2), but on the cache-miss path it doubles the MainActor hops and log
  noise.
- **Location:** `UsageAPIClient.swift:fetch()` + `resolveOrgUUID()` both calling
  `cookies.header()`; `CookieBridge.swift:read()` log line.
- **Fix:** Acceptable as-is (each network call legitimately re-reads). If trimmed,
  read once per `fetch()` and pass the header down; weigh against the Decision-2
  "re-read each fetch" intent (two network calls = two legitimate reads, so this
  is arguably correct). No change required.

---

## Dimensions explicitly verified clean

- **Cookie single source of truth (Decision 2):** `productionConfiguration()`
  sets `httpCookieStorage = nil`, `httpCookieAcceptPolicy = .never`,
  `httpShouldSetCookies = false`. No independent jar anywhere. `WKWebsiteDataStore`
  is the only store; cookies re-read each fetch via `CookieBridge.read()`;
  `Set-Cookie` written back via `writeBack`. ✔ (see F6 for a freshness nuance).
- **Host scoping:** cookies attached only for exact `claude.ai`
  (`isClaudeScoped`); `Cookie` header stripped on off-host redirect
  (`OffHostRedirectGuard`). ✔
- **Fallback routing:** every `UsageFetchResult` case is produced
  (`classifyUsage` + `resolveOrgUUID`) and consumed (`apply()`): `.success` →
  AppState + clears `loggedOut` + resets `retryCount`; `.needsCookieRefresh` /
  `.decodeFailed` → `runWebViewFallback()`; `.notLoggedIn` → `loggedOut = true`
  (no WebView); `.transport` → leave state, no WebView. ✔ (F1 is a *production-
  site* gap for the challenge case on discovery, not a missing consumer.)
- **Decision-7 backoff persistence:** `loggedOut` is NOT cleared by the timer
  `scrape()`; cleared only by `forceRefresh()` (wake / Refresh-Now / window-open)
  or a `.success`. `runWebViewFallback()` short-circuits while `loggedOut`. ✔
- **200 login-page classification:** `classifyUsage` runs `authResult` (incl.
  HTML login-page body) BEFORE any JSON decode, so a 200 login page →
  `.notLoggedIn`, never `.decodeFailed`. ✔ (caveat F2 on the loose `/login`
  marker).
- **Concurrency (Swift 6 strict):** `CookieBridge` and `QuotaScraper` are
  `@MainActor`; cookie reads complete on MainActor before the off-main request is
  built; `CookieSource` closures are `@Sendable`; `OffHostRedirectGuard` is a
  stateless `final … Sendable`; `OrgIDStore` is `@unchecked Sendable` (UserDefaults
  is thread-safe); `UsageAPIModels.decoder` returns a fresh non-shared decoder.
  Single-flight via `isFetchingNow`; `inFlightTask` exposed only for test await.
  `MainActor.assumeIsolated` in the wake observer is sound (queue: .main). No data
  races spotted. ✔
- **Architectural consistency:** ephemeral-WebView contract intact (fallback
  builds + tears down; `WKWebsiteDataStore.default()` shared); AppKit-only; all
  logging via `AppLog` (the only `NSLog` token in the tree is the lint-rule
  comment in `AppLog.swift`); file/naming conventions match `Scraper/`. ✔
- **Dead code:** none orphaned by the rewrite; the DOM-scrape pipeline is
  intentionally retained (Decision 4) and reachable via the fallback;
  `periphery:ignore` annotations are the established codebase pattern. ✔

## Secret-handling note (owned by Task 8)

Logging looks Decision-6-compliant from a holistic read (counts/host/status/
result-case only; no cookie names/values/headers in any `log(...)` call across
`CookieBridge`, `UsageAPIClient`, `UsageResponseClassifier`). Full secret-leak
audit (including the `ScrapeDebugLog` DOM dump and any `.decodeFailed` body dump)
is Task 8's scope — not duplicated here.
