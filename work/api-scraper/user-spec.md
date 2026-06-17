---
created: 2026-06-17
status: draft
size: M
---

# User Spec: JSON API scraper (drop per-minute WebView)

## Problem

The menu-bar app keeps idle memory at ~82 MB because it spins up a full
WKWebView every 60 s to render `claude.ai/settings/usage` and scrape the
DOM. The owner wants the footprint materially smaller and the data path
more robust.

A spike confirmed claude.ai exposes the same data as clean JSON over an
authenticated endpoint that Apple's URLSession can reach (curl is blocked
by Cloudflare's TLS fingerprinting; URLSession is not):

```
GET https://claude.ai/api/organizations/{org_uuid}/usage
→ { "limits": [
     {"group":"session","kind":"session","percent":3,"resets_at":"...Z"},
     {"group":"weekly","kind":"weekly_all","percent":51,"resets_at":"...Z","is_active":true},
     {"group":"weekly","kind":"weekly_scoped","percent":8,"resets_at":"...Z","scope":{"model":{"display_name":"Sonnet"}}}
   ], ... }
```

Reset times arrive as ISO-8601 timestamps — no localized-string regex
parsing needed.

## Goals

- Fetch usage via the JSON API using the existing logged-in session
  cookies, instead of rendering the SPA.
- Reduce idle memory (target: roughly one-third of current, ~25–35 MB —
  not 10×; the AppKit/WebKit floor remains).
- Keep the login flow and resilience intact: when the API path fails
  (expired Cloudflare clearance, not logged in), recover automatically.

## Non-goals

- No change to the menu-bar UI, formatting, or login window.
- No attempt to remove WebKit from the link line entirely (still needed
  for login + Cloudflare-clearance refresh).
- No new external dependencies.

## Requirements

- **US-1:** App fetches usage from `/api/organizations/{uuid}/usage` via
  URLSession on the existing 60 s cadence, reusing cookies from the
  shared `WKWebsiteDataStore.default()`.
- **US-2:** Organization UUID is discovered via `/api/organizations` and
  cached; re-discovered if a request later fails with not-found/auth.
- **US-3:** Usage JSON maps to the existing `ClaudeUsage` model
  (current %, weekly %, current reset time, weekly reset time) using the
  `limits[]` array, with reset times taken from `resets_at` directly.
- **US-4:** On API failure (HTTP 401/403, or Cloudflare challenge HTML),
  the app falls back to the WKWebView path to refresh session/Cloudflare
  cookies (and to surface login when required), then resumes the API path.
- **US-5:** When not logged in, behavior matches today: app waits quietly
  until the user logs in via the existing window, no crash, no spam.
- **US-6:** Idle footprint drops measurably (no WKWebView instantiated on
  the normal per-minute path).

## How to verify

- Run the app logged in → menu bar shows the same numbers as the
  claude.ai usage page, refreshing each minute.
- Activity Monitor: steady-state memory is materially below 82 MB and no
  transient WebContent/GPU helper processes appear on each tick.
- Expire/clear `cf_clearance` → app recovers automatically (one WebView
  refresh, then API resumes).
- Log out → app stops updating gracefully and shows login when the window
  is opened; log back in → updates resume.

## Edge cases

- Multiple organizations on the account → pick the active/first org,
  cache it.
- API returns an unexpected shape (internal endpoint, unversioned) →
  fall back to WebView DOM scrape rather than showing stale/blank data.
- System sleep/wake → immediate refresh (existing behavior preserved).
</content>
</invoke>
