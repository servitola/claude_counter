# Claude Counter

A tiny macOS menu-bar app that shows your **Claude.ai usage** live in the
top bar — current 5-hour window %, time until reset, and weekly %.

```
                                                  9% 2h 28m   26%   🔋  📶  🔍
                                                  ^^^^^^^^^^^^^^
                                              this is the app
```

Click the indicator → menu with **Open Usage Page**, **Launch at Login**,
**Refresh Now**, **Quit**. The Usage Page is a real Claude.ai window
embedded in the app, so you log in once and it stays logged in across
reboots.

Idle footprint is **~14 MB** (Activity Monitor "Memory" column — see
[AGENTS.md](AGENTS.md) for how). No telemetry, no analytics, all data
fetched locally straight from Claude.ai.

---

## Requirements

- macOS 15 (Sequoia) or newer
- A Claude.ai subscription (free or paid)
- Xcode command-line tools (`xcode-select --install`)
- `openssl` (comes from Homebrew or Xcode)

## Install

```bash
git clone https://github.com/servitola/claude_counter.git
cd claude_counter
make setup-cert     # one-time, creates a stable code-signing cert
make install        # builds, signs, copies to /Applications, launches
```

You'll be prompted for your login keychain password once during
`setup-cert` — that's so the cert can be used silently afterwards.

## First-time setup

1. Click the menu-bar item → **Open Usage Page**
2. Log in to Claude.ai (Google OAuth pop-up is supported)
3. Close the window — the app keeps running in the menu bar
4. Within a minute the bar shows live percentages
5. Click the menu-bar item → **Launch at Login** if you want it to
   auto-start

## Updating

```bash
git pull
make update
```

`make update` rebuilds, replaces the bundle, kills the running
instance, and relaunches it. Because the code-signing cert is stable,
macOS does **not** reset Login Item registration or any granted
permissions.

## Uninstall

```bash
make uninstall    # remove app, keep cookies + preferences
make purge        # uninstall + delete cookies and preferences too
```

## Troubleshooting

- **Bar shows `–%`** — you're not logged in yet, or login expired.
  Open the Usage Page from the menu and log in again.
- **Bar shows nothing at all** — `pgrep -lf ClaudeCounter` to check
  if it's running. `make update` to reinstall.
- **Want to see what the fallback scraped?** —
  `cat ~/Library/Logs/ClaudeCounter/scrape-debug.txt` shows the last DOM
  extraction (only written when the WebView fallback runs).

## How it works (the short version)

1. Every 60 seconds the app makes a direct HTTPS request (via
   `URLSession`) to Claude.ai's usage API, reusing your logged-in
   cookies. No browser is launched.
2. The JSON response (current 5h window, weekly %, reset timestamps)
   lands in `AppState`; the menu-bar title re-renders.
3. Cookies live in a shared `WKWebsiteDataStore` (written by the login
   window), so the session persists across app restarts.
4. **Fallback:** if the request hits a Cloudflare challenge (expired
   clearance) or an unexpected response, a hidden WebView spins up once
   to refresh the session / DOM-scrape, then the API path resumes. When
   logged out, the app waits quietly instead of retrying every minute.

The longer version, plus all the architecture, conventions, and
build pipeline notes, is in [AGENTS.md](AGENTS.md).

## JSON export (for other programs)

Every successful refresh writes the current usage snapshot to a JSON file
so other tools (scripts, status bars, Raycast, etc.) can read your token
state without scraping anything themselves:

```
~/Library/Application Support/ClaudeCounter/usage.json
```

```json
{
  "schemaVersion": 1,
  "currentPercent": 9,
  "weeklyPercent": 26,
  "currentResetAt": "2026-07-14T15:30:00Z",
  "weeklyResetAt": "2026-07-20T00:00:00Z",
  "updatedAt": "2026-07-14T13:02:00Z"
}
```

- `schemaVersion` and `updatedAt` are **always** present. `updatedAt` is
  the time of the snapshot — check it to detect a stale file (the app
  refreshes about once a minute while running).
- The four usage fields are **omitted** when unknown (e.g. before the
  first successful fetch, or when the app is logged out). Treat a missing
  key as "unknown".
- Percentages are integers `0..100`; reset timestamps and `updatedAt` are
  ISO-8601 (UTC).
- The write is atomic, so a reader never sees a half-written file.

Example — poll it from the shell with [`jq`](https://jqlang.github.io/jq/):

```bash
jq -r '"5h: \(.currentPercent // "?")%  week: \(.weeklyPercent // "?")%"' \
  ~/Library/Application\ Support/ClaudeCounter/usage.json
```

No server and no open port — it's just a local file, consistent with the
app's no-telemetry design.

## Privacy

- All requests go straight from your machine to `claude.ai` — nowhere else.
- Session cookies stay in `~/Library/WebKit/com.servitola.claudecounter/`
  and are sent only to `claude.ai` (stripped on any off-host redirect);
  they are never logged.
- No telemetry, no analytics, no outbound traffic except to `claude.ai`.
- Source is 100% open in this repository.
