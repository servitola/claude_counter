#!/bin/sh
set -eu

repo=servitola/claude_counter
tap_dir=${TAP_DIR:-$HOME/projects/homebrew-tap}
cask=Casks/claude-counter.rb
changelog=CHANGELOG.md
notary_profile=claude-counter-notary

usage() {
	cat <<EOF2
usage: scripts/release.sh [--dry-run] <step>

  check [--fast] [version]  preflight: main, clean tree, in sync with origin, make ci (--fast skips it),
                            CHANGELOG, notary credentials, Developer ID, GitHub CI on HEAD, tag free
  bump <version>            cut Unreleased in $changelog into "## <version> — <date>", leave a fresh Unreleased
  notes <version>           print that version's section of $changelog, for the GitHub release
  build <version>           APP_VERSION=<version> make release-notarized; the tag must exist and sit on HEAD
  cask <version>            put version and sha256 of the built zip into the tap cask and stage only that file

Nothing here commits, tags or pushes. --dry-run changes no file (bump, cask): it prints the diff.
The tap checkout is \$TAP_DIR, $tap_dir by default.
EOF2
}

dry_run=false
blocked=0

say() { printf '%s\n' "$*"; }
ok() { say "  ok    $*"; }
warn() { say "  warn  $*"; }
blocker() {
	say "  BLOCK $*"
	blocked=$((blocked + 1))
}
die() {
	say "release: $*" >&2
	exit 1
}

latest_tag_version() {
	git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

apply() {
	target=$1 edited=$2
	diff -u "$target" "$edited" | sed "1s|.*|--- $target|; 2s|.*|+++ $target (after)|" || true
	# Not mv: mktemp makes the copy 0600 and would replace the target's mode.
	$dry_run || cat "$edited" >"$target"
	rm -f "$edited"
}

unreleased_lines() {
	sed -n '/^## Unreleased$/,/^## [0-9]/p' "$changelog" | sed '1d;$d' | grep -c '[^[:space:]]' || true
}

valid_version() {
	say "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "\"$1\" is not MAJOR.MINOR.PATCH"
}

check() {
	fast=false
	version=
	for arg in "$@"; do
		case $arg in
		--fast) fast=true ;;
		*) version=${arg#v} ;;
		esac
	done
	[ -z "$version" ] || valid_version "$version"

	say "preflight at $(git rev-parse --short HEAD):"
	branch=$(git rev-parse --abbrev-ref HEAD)
	if [ "$branch" = main ]; then ok "on main"; else blocker "on $branch, releases are cut from main"; fi

	if [ -z "$(git status --porcelain)" ]; then ok "working tree is clean"; else blocker "working tree is not clean"; fi

	if git fetch --quiet origin main 2>/dev/null; then
		ahead=$(git rev-list --count origin/main..HEAD)
		behind=$(git rev-list --count HEAD..origin/main)
		if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
			ok "in sync with origin/main"
		else
			blocker "$ahead ahead of and $behind behind origin/main — CI has not seen this HEAD"
		fi
	else
		blocker "cannot fetch origin"
	fi

	if [ -n "$version" ]; then
		if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
			blocker "tag v$version already exists locally"
		elif git ls-remote --exit-code --tags origin "refs/tags/v$version" >/dev/null 2>&1; then
			blocker "tag v$version already exists on origin"
		else
			ok "tag v$version is free"
		fi
	fi

	if [ ! -f "$changelog" ]; then
		blocker "no $changelog"
	elif [ -n "$version" ] && grep -q "^## $version " "$changelog"; then
		ok "$changelog has a section for $version"
	elif [ "$(unreleased_lines)" -gt 0 ]; then
		ok "$changelog Unreleased has entries"
	else
		blocker "Unreleased in $changelog is empty — nothing to release"
	fi

	key_id=${NOTARY_KEY_ID:-${APPLE_SERVITOLA_APPSTORE_KEY_ID:-}}
	issuer=${NOTARY_ISSUER:-${APPLE_SERVITOLA_APPSTORE_KEY_ISSUER_ID:-}}
	key=${NOTARY_KEY:-}
	[ -n "$key" ] || [ -z "$key_id" ] || key=$HOME/.appstoreconnect/private_keys/AuthKey_$key_id.p8
	if [ -n "$key" ] && [ -f "$key" ] && [ -n "$key_id" ] && [ -n "$issuer" ]; then
		ok "notary API key $key_id"
	elif [ -n "$key" ] && [ ! -f "$key" ]; then
		blocker "notary key file $key is missing (keychain profile $notary_profile would be the fallback, not verifiable offline)"
	else
		warn "no notary API key/issuer in the environment — build falls back to keychain profile $notary_profile, which only Apple can confirm"
	fi

	devid=${DEVID:-$(sed -n 's/^DEVID *?= *//p' Makefile)}
	if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$devid"; then
		ok "signing identity $devid"
	else
		blocker "no valid identity \"$devid\" in the keychain"
	fi

	runs=$(gh run list --repo "$repo" --commit "$(git rev-parse HEAD)" --json conclusion --jq '.[].conclusion' 2>/dev/null || true)
	if [ -z "$runs" ]; then
		blocker "no GitHub CI run for HEAD — the Gitea mirror has not delivered it, or CI has not finished"
	elif [ -n "$(say "$runs" | grep -v '^success$' || true)" ]; then
		blocker "GitHub CI on HEAD is not green: $(say "$runs" | tr '\n' ' ')"
	else
		ok "GitHub CI on HEAD is green"
	fi

	if $fast; then
		warn "make ci skipped (--fast)"
	elif make ci >/dev/null 2>&1; then
		ok "make ci"
	else
		blocker "make ci fails"
	fi
}

bump() {
	version=$1
	valid_version "$version"
	current=$(latest_tag_version)
	if [ -n "$current" ]; then
		newest=$(printf '%s\n%s\n' "$current" "$version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
		if [ "$version" = "$current" ] || [ "$newest" != "$version" ]; then die "$version is not above the latest tag v$current"; fi
	fi
	if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then die "tag v$version already exists"; fi
	grep -q '^## Unreleased$' "$changelog" || die "$changelog has no \"## Unreleased\" section"
	[ "$(unreleased_lines)" -gt 0 ] || die "Unreleased in $changelog is empty — nothing to release"

	say "bump ${current:-none} -> $version:"
	edited=$(mktemp)
	awk -v heading="## $version — $(date +%Y-%m-%d)" '{ print } /^## Unreleased$/ { print ""; print heading }' "$changelog" >"$edited"
	apply "$changelog" "$edited"
}

notes() {
	section=$(awk -v start="## $1 " 'index($0, start) == 1 { inside = 1; next } /^## / { inside = 0 } inside' "$changelog")
	[ -n "$section" ] || die "$changelog has no section for $1"
	# GitHub renders a newline inside a release body as a line break, so wrapped lines are joined.
	say "$section" | sed -e '/./,$!d' | awk '
		/^(- |#|$)/ { if (line != "") print line; line = ""; if ($0 ~ /^(#|$)/) { print; next } }
		{ sub(/^ +/, ""); line = (line == "" ? $0 : line " " $0) }
		END { if (line != "") print line }'
}

build() {
	version=$1
	valid_version "$version"
	git rev-parse -q --verify "refs/tags/v$version" >/dev/null || die "tag v$version does not exist locally — the bump commit is tagged before the build"
	[ "$(git rev-parse "v$version^{commit}")" = "$(git rev-parse HEAD)" ] || die "v$version does not point at HEAD"
	[ -z "$(git status --porcelain)" ] || die "working tree is not clean"

	APP_VERSION=$version make release-notarized

	zip=ClaudeCounter-$version.zip
	[ -f "$zip" ] && [ -f "$zip.sha256" ] || die "$zip or its .sha256 was not produced"

	check_dir=$(mktemp -d)
	ditto -x -k "$zip" "$check_dir"
	built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$check_dir/ClaudeCounter.app/Contents/Info.plist")
	[ "$built" = "$version" ] || die "$zip carries version $built"
	xcrun stapler validate "$check_dir/ClaudeCounter.app" >/dev/null || die "$zip is not stapled"
	spctl -a -vv -t exec "$check_dir/ClaudeCounter.app" 2>&1 | grep -q 'Notarized Developer ID' || die "Gatekeeper does not report Notarized Developer ID for $zip"
	rm -rf "$check_dir"
	say "$zip: version $version, stapled, Notarized Developer ID, sha256 $(cut -d' ' -f1 "$zip.sha256")"
}

update_cask() {
	version=$1
	valid_version "$version"
	[ -f "$tap_dir/$cask" ] || die "no $cask in $tap_dir — set TAP_DIR to the tap checkout that pushes to origin"
	sumfile=ClaudeCounter-$version.zip.sha256
	[ -f "$sumfile" ] || die "$sumfile is missing — run build $version first"
	sha=$(cut -d' ' -f1 "$sumfile")
	say "$sha" | grep -Eq '^[0-9a-f]{64}$' || die "$sumfile does not start with a sha256"
	if [ -f "ClaudeCounter-$version.zip" ] && [ "$(shasum -a 256 "ClaudeCounter-$version.zip" | cut -d' ' -f1)" != "$sha" ]; then
		die "$sumfile does not match ClaudeCounter-$version.zip — rebuild"
	fi

	say "cask in $tap_dir:"
	edited=$(mktemp)
	sed -e "s|^  version \".*\"$|  version \"$version\"|" -e "s|^  sha256 \".*\"$|  sha256 \"$sha\"|" "$tap_dir/$cask" >"$edited"
	apply "$tap_dir/$cask" "$edited"
	# Only this path: the tap checkout often holds unrelated edits (Casks/glasswings.rb).
	$dry_run || git -C "$tap_dir" add -- "$cask"
}

if [ "${1:-}" = --dry-run ]; then
	dry_run=true
	shift
fi
step=${1:-}
[ $# -eq 0 ] || shift
cd "$(dirname "$0")/.."

case $step in
check)
	check "$@"
	;;
notes | bump | build | cask)
	[ $# -eq 1 ] || die "$step needs a version"
	version=${1#v}
	case $step in
	notes) notes "$version" ;;
	bump) bump "$version" ;;
	build) build "$version" ;;
	cask) update_cask "$version" ;;
	esac
	;;
-h | --help | '')
	usage
	exit 0
	;;
*)
	usage >&2
	exit 64
	;;
esac

if [ "$blocked" -gt 0 ]; then
	say "release: $blocked blocker(s) — a real release stops here"
	exit 1
fi
