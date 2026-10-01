# When a release breaks half-way

A tag that someone may have installed from is never moved or deleted: the cask pins the zip's
sha256, and a re-tag or re-upload changes it under everyone who installed. Fix forward with a patch
version. The one exception is a tag nobody could have installed (release and cask never published),
and even then deleting it is the owner's decision. Never push to `github` to "fix" anything there:
the mirror force-overwrites it.

| Where it failed | State | What to do |
| --- | --- | --- |
| `build` fails in notarization ("not Accepted") | nothing pushed | Read the log `build-app.sh` prints (`notarytool log`). Fix, amend the commit, move the local tag (`git tag -f`): still local, so allowed. Re-run `build`. |
| `build` fails on credentials | nothing pushed | Check `APPLE_SERVITOLA_APPSTORE_KEY_ID` / `_ISSUER_ID` and the `.p8` in `~/.appstoreconnect/private_keys/`. `store-credentials` silently does not persist from a non-GUI session, so do not rely on the keychain profile. Disable the Bash sandbox for codesign/notarytool. |
| Pushed to Gitea, tag missing on GitHub | release not created | Trigger the mirror sync and read `last_error` (Phase 4 step 2). Do not create the release until `git ls-remote github 'refs/tags/v<version>^{}'` matches. |
| Mirror `last_error` mentions "cannot lock ref ... reference already exists" | a release was created before the mirror delivered the tag, so GitHub made the tag on an older commit | Delete that GitHub release and its tag (`gh release delete v<version> -R servitola/claude_counter --cleanup-tag`) with the owner's word, nobody can have installed it (the cask is not updated yet), trigger the sync, then `gh release create` again. |
| Release created, zip missing or wrong | cask not updated yet, nobody installs it | `gh release upload v<version> ClaudeCounter-<version>.zip -R servitola/claude_counter --clobber`, then compare `shasum -a 256` of a downloaded copy with the `.sha256`. |
| Release live, cask not updated | users keep the previous version | Nothing is broken. Resume at Phase 5. |
| `cask` step: sha256 mismatch | cask would fail to install | Rebuild only if nothing is published. Otherwise the `.sha256` file is the truth for the uploaded zip: download the release asset and hash it. If they differ, the asset was replaced: stop and tell the owner. |
| Tap commit pushed, mirror does not show it | GitHub mirror lags or sync is down | Wait; sync from the Gitea API as in the skill. Anything pushed to GitHub directly is erased by the next force run. |
| Tap commit has extra files | unrelated edits committed | Do not force-push. `git -C ~/projects/homebrew-tap revert <commit>` with the owner's word, then redo the commit with `-- Casks/claude-counter.rb`. |
| Installed version misbehaves here | bad release is live | Revert the tap commit (`git revert`, push to `origin`), `brew update && brew reinstall --cask claude-counter` to get the previous zip, then release the next patch version. |
