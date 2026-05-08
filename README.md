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

Idle footprint is **~76 MB** (yes, really — see [AGENTS.md](AGENTS.md)
for how). No telemetry, no analytics, all scraping happens locally.

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
- **Want to see what was scraped?** — `cat /tmp/claude_counter_debug.txt`
  shows the last extraction (percentages, raw text, regex matches).

## How it works (the short version)

1. Every 60 seconds a tiny hidden WebView spawns, loads
   `claude.ai/settings/usage`, runs an extraction script, dies.
2. The script reads `aria-label`s and text nodes from the React DOM
   (claude.ai is a heavy SPA; `body.innerText` is empty).
3. Results land in `AppState`; the menu-bar title re-renders.
4. Cookies live in a shared `WKWebsiteDataStore` so login persists
   between scrapes and across app restarts.

The longer version, plus all the architecture, conventions, and
build pipeline notes, is in [AGENTS.md](AGENTS.md).

## Privacy

- All scraping happens locally in your machine's WebKit.
- Cookies stored in `~/Library/WebKit/com.servitola.claudecounter/`
  and nowhere else.
- No outbound traffic except to `claude.ai`.
- Source is 100% open in this repository.
