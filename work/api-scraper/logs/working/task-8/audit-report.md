# Task 8 — Security Audit Report: JSON API Scraper

**Feature:** api-scraper (Tasks 1–6) — direct authenticated `URLSession` call to
claude.ai's internal `/usage` endpoint, reusing `WKWebsiteDataStore` session
cookies.
**Scope:** New authenticated HTTP client + cookie handling, plus the logging
surfaces it writes through. Analysis only — no code modified.
**Auditor:** security-auditor (Task 8, Audit Wave)
**Standard:** OWASP Top 10 (2021), scoped to a local macOS menu-bar app calling
one first-party endpoint.

## Verdict

**CLEAN.** Zero critical/high/medium findings. Decisions 2 (host scoping) and 6
(no-secret-logging) are honored on every audited path. Two informational notes
are recorded for transparency; neither is a leak and neither blocks deploy.

The feature is cleared from a security standpoint to proceed to Task 10 (deploy).

---

## Threat model recap

The three cookies `sessionKey`, `cf_clearance`, `__cf_bm` together authenticate
as the user; any one leaking to a reader-accessible sink (unified logging, the
on-disk debug file, an off-host request) is a session-takeover-grade exposure.
The audit enforces the two load-bearing planning decisions that prevent that.

---

## Files reviewed (final state)

- `App/Sources/ClaudeCounter/Scraper/CookieBridge.swift`
- `App/Sources/ClaudeCounter/Scraper/UsageAPIClient.swift`
- `App/Sources/ClaudeCounter/Scraper/UsageResponseClassifier.swift`
- `App/Sources/ClaudeCounter/Scraper/OffHostRedirectGuard.swift`
- `App/Sources/ClaudeCounter/Scraper/UsageAPIModels.swift`
- `App/Sources/ClaudeCounter/Scraper/OrgIDStore.swift`
- `App/Sources/ClaudeCounter/Scraper/UsageMapper.swift` (reviewed via decisions; pure value transform)
- `App/Sources/ClaudeCounter/Scraper/QuotaScraper.swift`
- `App/Sources/ClaudeCounter/Scraper/QuotaScraper+Orchestrator.swift`
- `App/Sources/ClaudeCounter/Scraper/QuotaScraper+Navigation.swift`
- `App/Sources/ClaudeCounter/Scraper/QuotaScraper+Extract.swift` (debug dump)
- `App/Sources/ClaudeCounter/Scraper/QuotaScraper+JS.swift` (DOM extraction source)
- `App/Sources/ClaudeCounter/Scraper/QuotaPayload.swift`
- `App/Sources/ClaudeCounter/Scraper/WebViewFactory.swift`
- `App/Sources/ClaudeCounter/Logging/AppLog.swift`
- `App/Sources/ClaudeCounter/Scraper/ScrapeDebugLog.swift`
- `App/Package.swift` (ATS / transport config check); no `Info.plist` exists under `App/`.

---

## Controls verified (a clean audit shows its work)

### Decision 6 — secrets never touch the logs

**VERIFIED.** No cookie value, cookie name, request header, or response header
is emitted on any logging path. Every cookie-touching log call is value-free.

| Control | Evidence | Result |
|---|---|---|
| Cookie read logs counts only | `CookieBridge.swift:45` — `log("cookie read host=\(Self.host) count=\(scoped.count)")` | PASS — host + count, no name/value |
| Cookie write-back logs counts only | `CookieBridge.swift:84` — `log("cookie write-back host=\(Self.host) inserted=\(inserted)")` | PASS |
| `cookieHeader()` builds `name=value` but never logs it | `CookieBridge.swift:52-57` (no log call in this function) | PASS |
| Client log sink is value-free | `UsageAPIClient.swift:120,151,156,161,171,176,185,189,193` — all log status codes / result cases / discovery outcomes, never cookies or headers | PASS |
| Classifier logs result case + status only | `UsageResponseClassifier.swift:13,20,25,33,38` | PASS |
| `get()` sets Cookie/UA/Accept headers but logs nothing | `UsageAPIClient.swift:219-233` — no log call touches `request` | PASS |
| Orchestrator logs result-case strings only | `QuotaScraper+Orchestrator.swift:56,59,63,69,74` | PASS |
| `privacy: .public` used only on value-free strings | `CookieBridge.swift:30`, `UsageAPIClient.swift:79` — the closure interpolates `$0` which is always a value-free message string built at the call sites above | PASS — no token-adjacent field is interpolated into a `.public` log |
| No `privacy:` qualifier on any cookie/header/token field anywhere | grep over `Sources/ClaudeCounter` for `cookie\|header\|sessionKey\|cf_clearance\|__cf_bm\|Authorization` cross-referenced against every `AppLog`/`log(` call | PASS — no match logs a secret |
| `.decodeFailed` repro dump is response-body-only — or absent | `UsageResponseClassifier.swift:29-35` returns `.decodeFailed` with **no dump at all** (does not write the request, its `Cookie` header, the response, or `Set-Cookie`) | PASS — stronger than the spec's "response-body-only" allowance |
| `ScrapeDebugLog` cannot capture cookies | `QuotaScraper+Extract.swift:50-70` — the only `ScrapeDebugLog.default.write(...)` call passes `formatDebug(payload)`; `payload` is a `QuotaPayload` (`QuotaPayload.swift:6-14`) holding only percentages, reset minutes, matched text, and `raw` DOM text | PASS |
| The DOM text fed to the dump excludes cookies | `QuotaScraper+JS.swift:182-211` — the extraction JS walks `aria-label` attributes and `nodeType===3` text nodes from the rendered page; it never reads `document.cookie`. Session cookies are `HttpOnly`, so they are unreadable from JS regardless | PASS |
| No other `ScrapeDebugLog.write` call sites | grep — single call site at `QuotaScraper+Extract.swift:51` | PASS |
| Navigation/extract error logs use `.localizedDescription` only | `QuotaScraper+Navigation.swift:37,46`; `QuotaScraper+Extract.swift:17` — log `error.localizedDescription`, which for `URLError`/`WKError` is a generic transport/JS message with no credential content | PASS |

### Decision 2 — host scoping / SSRF

**VERIFIED.** Cookies are attached only to `claude.ai`, stripped on off-host
redirect, and the session keeps no cookie jar of its own.

| Control | Evidence | Result |
|---|---|---|
| Cookies read are filtered to claude.ai | `CookieBridge.swift:42-46` filters `allCookies()` by `isClaudeScoped` before returning | PASS |
| Host match rejects lookalikes/sub-suffixes | `CookieBridge.swift:92-95` — strips a single leading dot then **exact** `caseInsensitiveCompare`; `notclaude.ai`, `claude.ai.evil.com`, `xclaude.ai` all rejected | PASS |
| Write-back inserts only claude.ai cookies | `CookieBridge.swift:79` — `for cookie in parsed where Self.isClaudeScoped(cookie.domain)` | PASS (defense in depth atop `HTTPCookie.cookies(...for:)`) |
| Cookie attached only to a `https://claude.ai` URL | `UsageAPIClient.swift:140,214` build URLs with the hardcoded `Self.host = "claude.ai"`; `get()` sets the Cookie header on that request only | PASS |
| Off-host redirect strips the Cookie header | `OffHostRedirectGuard.swift:19-26` — if the redirect target host is not claude.ai (or a `.claude.ai` subdomain), `stripped.setValue(nil, forHTTPHeaderField: "Cookie")` before following | PASS |
| Redirect with no resolvable host follows unchanged (no synthetic injection) | `OffHostRedirectGuard.swift:15-18` — `nil` host returns the request as-is; URLSession will not attach a stored cookie because the session has no jar (see below) | PASS |
| URLSession carries NO cookie jar of its own | `UsageAPIClient.swift:94-100` — `productionConfiguration()` sets all three: `httpCookieStorage = nil`, `httpCookieAcceptPolicy = .never`, `httpShouldSetCookies = false` | PASS — secrets cannot drift into a second, longer-lived store |
| Session uses the no-jar config in production | `UsageAPIClient.swift:75,83-87` — default `configuration` is `productionConfiguration()`; delegate is `OffHostRedirectGuard()` | PASS |
| org-uuid is UUID-validated before URL interpolation | `UsageAPIClient.swift:168,188,207-209` — `isValidUUID` (`UUID(uuidString:) != nil`) gates both the freshly discovered uuid and a cached uuid; a non-UUID invalidates the cache and re-discovers, never reaching the URL | PASS — no path/query/host injection possible |
| Hostile `/organizations` response cannot redirect the fetch off-host | `UsageAPIClient.swift:199-201,213-215` — only `OrgSummary.uuid` is consumed (no URL/host field in the model, `UsageAPIModels.swift:60-62`); the host is the hardcoded constant. A malicious org list can at most supply a string that must pass `UUID(uuidString:)` | PASS |

### TLS / transport security

**VERIFIED.** No cert-validation bypass, no ATS exception, no custom
auth-challenge handler.

| Control | Evidence | Result |
|---|---|---|
| No App Transport Security exception | No `Info.plist` exists under `App/`; `Package.swift` has no `NSAppTransportSecurity` / `NSAllowsArbitraryLoads`. Default ATS applies (HTTPS + validated TLS) | PASS |
| All endpoint URLs are HTTPS | `UsageAPIClient.swift:140` (`https://…/api/organizations`), `:214` (`https://…/usage`); `QuotaScraper.swift:30` (`https://claude.ai/settings/usage`) | PASS |
| No server-trust / auth-challenge delegate that weakens trust | grep for `URLAuthenticationChallenge` / `serverTrust` / `useCredential` over `App/Sources` returns nothing. `OffHostRedirectGuard` implements only `willPerformHTTPRedirection`; it does not implement `urlSession(_:didReceive:completionHandler:)`, so default system trust evaluation is used | PASS |
| No TLS validation disabled | No `_kCFStreamSSLValidatesCertificateChain`, no `serverTrust` manipulation anywhere | PASS |

### Secrets at rest

**VERIFIED.** Only the (non-secret) org UUID is persisted; cookies stay in the
WebKit store.

| Control | Evidence | Result |
|---|---|---|
| Only the org UUID is written to UserDefaults | `OrgIDStore.swift:24-26` — `defaults.set(uuid, forKey: "org.uuid")`; the type exposes only `read`/`write`/`invalidate` of that one key | PASS |
| org UUID is non-secret | It is an organization identifier, not an authentication credential; possession of it does not authenticate (still requires the cookies) | PASS — acceptable per Decision 2 / task brief |
| No cookie/header/response body in UserDefaults, plist, or plaintext file | grep — no `UserDefaults.set` / `write(to:` of any cookie or header value; cookies live only in `WKWebsiteDataStore.default().httpCookieStore` (`CookieBridge.swift:42,80`) | PASS |
| WebView store excludes cookies from cache purge | `WebViewFactory.swift:43-52` purges only `DiskCache`/`MemoryCache`; cookies/localStorage are deliberately preserved (not exfiltrated) | PASS |

### OWASP Top 10 pass (scoped)

| Category | Assessment |
|---|---|
| A01 Broken Access Control / SSRF (off-host) | Mitigated — exact host match on read, off-host Cookie strip on redirect, hardcoded host, UUID-validated path segment. See Decision 2 table. |
| A02 Cryptographic Failures / sensitive-data exposure | Mitigated — default validated HTTPS; no secret logged, dumped, or persisted insecurely. See Decision 6 + TLS + at-rest tables. |
| A03 Injection | Mitigated — the only externally-influenced value interpolated into a URL is the org uuid, gated by `UUID(uuidString:)` (`UsageAPIClient.swift:207-209`). Cannot inject `../`, query, or an alternate host. |
| A04 Insecure Design | Sound — Decisions 2/6 are enforced in code, single cookie source of truth, no second jar, classification-before-decode order prevents login pages from triggering the expensive fallback. |
| A05 Security Misconfiguration | Sound — no ATS exception; URLSession explicitly stripped of its cookie jar (all three flags). |
| A06 Vulnerable Components | N/A — zero third-party dependencies (`Package.swift` has no `dependencies:`); only Apple frameworks (Foundation, WebKit, AppKit, os). |
| A07 Identification & Auth Failures | Sound — auth is delegated to the existing cookie session; 401 / `/login` / login-HTML / 403-challenge are classified explicitly (`UsageResponseClassifier.swift:11-67`) and never surface secrets. |
| A08 Software & Data Integrity (insecure deserialization) | Mitigated — JSON decode of the untrusted internal response is `try?` (`UsageResponseClassifier.swift:30`, `UsageAPIClient.swift:166`); a decode failure is caught and classified (`.decodeFailed`), never fatal. Models decode only the fields needed; extra/hostile keys are ignored. |
| A09 Security Logging & Monitoring | Sound — value-free operational logging only; no PII/secret in logs. |
| A10 SSRF | Covered under A01 above. |

---

## Findings

### Finding 1 — INFO: redirect guard accepts `*.claude.ai` subdomains while the cookie filter is exact-match

- **Severity:** Informational (no leak; intentional asymmetry, documented for awareness).
- **Location:** `OffHostRedirectGuard.swift:29-32` vs `CookieBridge.swift:92-95`.
- **Issue:** `OffHostRedirectGuard.isClaudeHost` treats any host ending in
  `.claude.ai` (e.g. `api.claude.ai`) as on-host and forwards the `Cookie`
  header on redirect, whereas `CookieBridge.isClaudeScoped` accepts only the
  exact `claude.ai` host. So a redirect to a claude.ai subdomain keeps the
  cookies, but those cookies were only ever read for the bare `claude.ai`
  domain.
- **Why it's not a vulnerability:** Both hosts are within the registrable
  domain `claude.ai`, controlled by the same first party; forwarding the
  session cookie to a legitimate claude.ai subdomain over a server-issued
  redirect is the intended behavior (and what a browser would do for a
  Domain=.claude.ai cookie). No credential leaves the first-party origin. An
  attacker cannot cause a redirect to an arbitrary subdomain they control,
  because claude.ai's own DNS governs which subdomains resolve.
- **Recommendation:** No change required. If you later want strict parity,
  narrow `isClaudeHost` to an exact match — but only if you confirm claude.ai
  never legitimately redirects `/api/...` to a subdomain (it may, e.g. for
  region routing), as tightening it could break the fetch.

### Finding 2 — INFO: `cookieHeader()` joins all stored claude.ai cookies, not just the three auth cookies

- **Severity:** Informational.
- **Location:** `CookieBridge.swift:52-57`.
- **Issue:** The outgoing `Cookie` header includes every `claude.ai`-scoped
  cookie in the store, not only `sessionKey` / `cf_clearance` / `__cf_bm`.
- **Why it's acceptable:** All included cookies are already first-party
  claude.ai cookies the browser would itself send to claude.ai; sending the
  full first-party jar to its own origin is correct and matches the WebView's
  behavior (important for Cloudflare, which gates on the full cookie+UA
  fingerprint). No cross-origin cookie is included (host filter at
  `CookieBridge.swift:43`). The header value is never logged (Decision 6).
- **Recommendation:** No change required.

---

## Acceptance criteria status

- [x] All feature source from Tasks 1–6 read (incl. AppLog, ScrapeDebugLog, JS extraction, QuotaPayload).
- [x] Decision 6 verified — no cookie/header value logged; no `.public` on a token-adjacent field; no secret in any dump or `ScrapeDebugLog`. Each cookie-touching log call cited with file:line.
- [x] Decision 2 verified — cookies attached only to claude.ai; Cookie stripped on off-host redirect; URLSession has no cookie jar. Cited with file:line.
- [x] No TLS/cert bypass, no ATS exception — all claude.ai traffic is validated HTTPS.
- [x] No secret persisted insecurely; org UUID in UserDefaults confirmed as the only persisted value, accepted as non-secret.
- [x] OWASP Top 10 pass completed; org-UUID URL interpolation and JSON deserialization checked for injection/SSRF.
- [x] Report written with severity + file:line + (where applicable) Decision mapping; clean result lists controls and evidence.
- [x] No source code modified by this task.

## Deploy gate

No critical/high findings. **The feature is not blocked by security** and may
proceed to Task 10. No tech-spec change is required (implementation matches
Decisions 2 and 6).
