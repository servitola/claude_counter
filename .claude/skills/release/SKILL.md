---
name: release
description: |
  Releases Claude Counter end to end: preflight, version and changelog, the owner's go-ahead, tag and
  push to Gitea, the local notarized build, the GitHub release, the Homebrew cask in servitola/tap,
  and the upgraded install on this Mac.

  Use when: "выпускай", "выпусти релиз", "сделай релиз", "выкати новую версию", "обнови cask",
  "release it", "cut a release", "ship 1.2.0", "bump the version and publish"
---

# Releasing Claude Counter

`scripts/release.sh` does the mechanical steps and never commits, tags or pushes; this skill
supplies the judgement and the order. Everything that leaves the machine waits for the owner's
"yes" in Phase 3: a published tag and a cask sha256 cannot be taken back once someone has installed.

Facts that shape the order:

- `origin` is the private Gitea: push here only. `github` is the public GitHub, fed by a Gitea push
  mirror (`git push --mirror --force`, sync on commit). Never push to `github`: the next sync wipes it.
- The app is built, signed and notarized **locally**; GitHub only hosts the zip. CI on GitHub runs
  `make ci`, it does not build the release.
- Versions are semantic (`1.2.0`), tags `v1.2.0`. Patch for fixes, minor for features, major for
  breakage of settings or the bundle ID.
- Commit messages carry no AI co-author or "Generated with" footer; the `commit-msg` hook rejects it.

## Phase 1: Preflight

1. `scripts/release.sh check <version>`. A `BLOCK` line stops the release; fix the cause, re-run.
   `--fast` skips `make ci` (only when CI on HEAD is already green and nothing changed since).
   Local commits the mirror has not delivered are a blocker by design: pushing them is the owner's call.
2. A red or missing GitHub run: `gh run list -R servitola/claude_counter --limit 5`,
   `gh run view <id> --log-failed`. No run at all means the mirror has not delivered HEAD; see Phase 4 step 2.

**Checkpoint:** every `check` line is `ok` (a `warn` on the notary credentials is named to the owner).

## Phase 2: Version and changelog

1. Read `git log --oneline v<last>..HEAD` and `CHANGELOG.md` → `## Unreleased`. Every user-visible
   change has a line there; add the missing ones (Added / Changed / Fixed).
2. Pick the version, then `scripts/release.sh --dry-run bump <version>`, read the diff, then
   `scripts/release.sh bump <version>`.
3. Commit exactly `CHANGELOG.md` as `release <version>`, then tag that commit:
   `git tag -a v<version> -m "Claude Counter <version>"`. The tag is local only; `push.followTags`
   is on for this machine, so the next push carries it, which is Phase 4 step 1.
4. `scripts/release.sh build <version>`. It runs `APP_VERSION=<version> make release-notarized`
   (`build-app.sh` reads `APP_VERSION` first, git tag second), then unpacks the zip and checks
   Info.plist version, stapled ticket and `spctl` "Notarized Developer ID". Needs network to Apple
   and the keychain; run it with the Bash sandbox disabled. Notarization takes minutes.
   Notarization is a non-GUI session: `notarytool store-credentials` validates but silently fails to
   persist, so the build uses the App Store Connect API key
   (`APPLE_SERVITOLA_APPSTORE_KEY_ID`, `APPLE_SERVITOLA_APPSTORE_KEY_ISSUER_ID`,
   `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`); the keychain profile is only a fallback.

**Checkpoint:** one local commit, tag `v<version>` on HEAD, `ClaudeCounter-<version>.zip` and
`.sha256` in the repo root (git-ignored), nothing pushed.

## Phase 3: Stop gate

1. Show the owner: version and why, the `## <version>` section (`scripts/release.sh notes <version>`),
   `git show --stat HEAD`, and what follows: push `main` and the tag to Gitea, GitHub release with the
   zip, cask commit pushed to the tap.
2. Wait for an explicit yes. Anything else: stop. Commit and tag are local and can be reset
   (`git tag -d v<version>`, `git reset --hard HEAD~1`) while nothing is pushed.

**Checkpoint:** the owner's "yes" is in this conversation, after the summary.

## Phase 4: Publish

1. `git push --follow-tags origin main` (or `git push origin main v<version>`): commit and tag
   together, to `origin` only.
2. Wait until the mirror delivers the tag: `git ls-remote github 'refs/tags/v<version>^{}'` equals
   `git rev-parse v<version>^{commit}`. If it takes more than a minute, trigger a sync and read the error:
   ```sh
   source ~/.config/gitea_token.sh
   c=(-sS --cert ~/.config/gitea-ca/clients/mac/mac.crt --key ~/.config/gitea-ca/clients/mac/mac.key
      -H "Authorization: token $GITEA_TOKEN")
   curl "${c[@]}" -X POST "$GITEA_URL/api/v1/repos/servitola/claude_counter/push_mirrors-sync"
   curl "${c[@]}" "$GITEA_URL/api/v1/repos/servitola/claude_counter/push_mirrors" | jq '.[].last_error'
   ```
3. Only now: `gh release create v<version> ClaudeCounter-<version>.zip -R servitola/claude_counter
   --verify-tag --title "Claude Counter <version>" --notes "$(scripts/release.sh notes <version>)"`.
   Never before step 2: without the tag on GitHub, `gh` creates it on the old default-branch commit,
   and the mirror push is then rejected ("cannot lock ref ... reference already exists").
4. `gh release view v<version> -R servitola/claude_counter --json assets --jq '.assets[].name'`
   names the zip. `gh run list -R servitola/claude_counter --limit 3`: CI on the pushed commit green.

**Checkpoint:** GitHub tag equals the local tag, release has the zip, mirror `last_error` is empty.

## Phase 5: Cask

The tap lives in `~/projects/homebrew-tap`. Its `origin` is Gitea, mirrored to public GitHub
`servitola/homebrew-tap` (the `github` remote there is fetch-only). Push to `origin` only.

1. `scripts/release.sh --dry-run cask <version>`, read the diff, then `scripts/release.sh cask <version>`.
   It edits `Casks/claude-counter.rb` only and stages only that file: the checkout often holds
   unrelated edits (`Casks/glasswings.rb`) that stay untouched.
2. `git -C ~/projects/homebrew-tap commit -m "claude-counter <version>" -- Casks/claude-counter.rb`
   (the path after `--` keeps anything else out), then `git -C ~/projects/homebrew-tap push origin main`.
3. Wait for the mirror: `git ls-remote https://github.com/servitola/homebrew-tap main` equals the
   new commit.

**Checkpoint:** tap commit on both Gitea and GitHub, `git -C ~/projects/homebrew-tap status` still
shows the owner's own edits and nothing else of ours.

## Phase 6: Install and verify here

1. `brew update && brew upgrade --cask claude-counter`. The cask does not relaunch the app; `open
   /Applications/ClaudeCounter.app` yourself.
2. `spctl -a -vv -t exec /Applications/ClaudeCounter.app` says `accepted`, `source=Notarized Developer ID`.
3. `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/ClaudeCounter.app/Contents/Info.plist`
   prints `<version>`; the menu-bar title shows numbers.

**Checkpoint:** installed bundle reports `<version>`, Gatekeeper accepts it as notarized.

**Something failed after Phase 3?** Follow [rollback.md](references/rollback.md).

## Final check

- [ ] the owner's yes came before the first push
- [ ] nothing was pushed to `github`; GitHub got everything through the mirror
- [ ] release zip sha256 equals the cask's `sha256`
- [ ] the tap commit touched `Casks/claude-counter.rb` only
