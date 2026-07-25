#!/bin/zsh
# Build ClaudeCounter.app and optionally install/update in /Applications.
# Uses a stable self-signed cert when available so macOS TCC permissions
# and Login Item registration survive across rebuilds.
set -euo pipefail

SCRIPT_DIR="${0:a:h}"
PROJECT_DIR="$SCRIPT_DIR/../App"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/ClaudeCounter.app"
APP_DIR="$APP_BUNDLE/Contents"
DEST="/Applications/ClaudeCounter.app"
CERT_NAME="Claude Counter Local Signing"

INSTALL=false
RELAUNCH=false
NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --update)  INSTALL=true; RELAUNCH=true ;;
        --notarize) NOTARIZE=true ;;
        --help|-h)
            echo "Usage: build-app.sh [--install] [--update] [--notarize]"
            echo "  --install    build + replace /Applications/ClaudeCounter.app"
            echo "  --update     --install + kill + relaunch"
            echo "  --notarize   sign for distribution, notarize with Apple,"
            echo "               staple the ticket, emit a distributable zip."
            echo "               Requires CODESIGN_IDENTITY + NOTARY_PROFILE env."
            exit 0 ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# Version, single source of truth: an explicit $APP_VERSION env wins (CI sets
# it from the pushed tag); otherwise derive from the latest git tag (v1.2.0 ->
# 1.2.0); otherwise fall back to a dev marker. CFBundleVersion needs a
# monotonically increasing build number, so use the commit count.
if [[ -z "${APP_VERSION:-}" ]]; then
    # `|| true` keeps `set -e`/`pipefail` from aborting here on a tagless
    # checkout (git describe exits 128) — we want the dev-marker fallback below.
    APP_VERSION="$(git -C "$SCRIPT_DIR/.." describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    [[ -z "$APP_VERSION" ]] && APP_VERSION="0.0.0-dev"
fi
BUILD_NUMBER="$(git -C "$SCRIPT_DIR/.." rev-list --count HEAD 2>/dev/null || echo 1)"
echo "Version: $APP_VERSION (build $BUILD_NUMBER)"

echo "Building release..."
builtin cd "$PROJECT_DIR"
xcrun --sdk macosx swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"
cp "$BUILD_DIR/release/ClaudeCounter" "$APP_DIR/MacOS/ClaudeCounter"

# Bundle icon. Sources lives at App/Resources/AppIcon.icns.
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP_DIR/Resources/AppIcon.icns"
    ICON_PLIST_KEY='    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
'
else
    echo "WARN: $ICON_SRC missing — bundle will use the default icon."
    ICON_PLIST_KEY=''
fi

cat > "$APP_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeCounter</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Counter</string>
    <key>CFBundleIdentifier</key>
    <string>com.servitola.claudecounter</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeCounter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
${ICON_PLIST_KEY}    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Pick signing identity.
#   * CODESIGN_IDENTITY set (release path) -> sign with that Developer ID and
#     turn on the hardened runtime + a secure timestamp, both of which Apple
#     requires before it will notarize the build.
#   * otherwise (daily local dev) -> stable self-signed cert if present, else
#     ad-hoc. The stable cert keeps TCC permissions + Login Item registration
#     alive across rebuilds. Resolve by SHA-1 (not name) to avoid "ambiguous"
#     errors when setup-cert ran more than once and left duplicate certs.
CODESIGN_EXTRA=()
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    SIGN_ID="$CODESIGN_IDENTITY"
    CODESIGN_EXTRA=(--options runtime --timestamp)
    echo "Signing for distribution (hardened runtime): $SIGN_ID"
else
    CERT_SHA=$(security find-identity -p basic 2>/dev/null \
        | grep "\"$CERT_NAME\"" | head -1 | awk '{print $2}')
    if [[ -n "$CERT_SHA" ]]; then
        SIGN_ID="$CERT_SHA"
        echo "Signing with stable identity: $CERT_NAME ($CERT_SHA)"
    else
        SIGN_ID="-"
        echo "WARN: stable cert not found — using ad-hoc signing."
        echo "      Run 'make setup-cert' once to preserve permissions"
        echo "      (TCC + Login Item) across rebuilds."
    fi
fi
codesign --force --deep --sign "$SIGN_ID" "${CODESIGN_EXTRA[@]}" "$APP_BUNDLE"

# Notarize + staple. Submit a zip of the signed bundle to Apple, wait for the
# verdict, then staple the ticket onto the .app so it validates offline.
if $NOTARIZE; then
    : "${CODESIGN_IDENTITY:?--notarize needs CODESIGN_IDENTITY (a Developer ID Application identity)}"
    : "${NOTARY_PROFILE:?--notarize needs NOTARY_PROFILE (keychain profile from 'notarytool store-credentials')}"
    NOTARIZE_ZIP="$BUILD_DIR/ClaudeCounter-notarize.zip"
    echo "Submitting to Apple notary service (profile: $NOTARY_PROFILE)..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"
    SUBMIT_OUT=$(xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
    echo "$SUBMIT_OUT"
    rm -f "$NOTARIZE_ZIP"
    if ! echo "$SUBMIT_OUT" | grep -q "status: Accepted"; then
        SUB_ID=$(echo "$SUBMIT_OUT" | awk '/  id:/{print $2; exit}')
        [[ -n "$SUB_ID" ]] && xcrun notarytool log "$SUB_ID" \
            --keychain-profile "$NOTARY_PROFILE" || true
        echo "ERROR: notarization was not Accepted." >&2
        exit 1
    fi
    echo "Stapling ticket..."
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
fi

if $INSTALL; then
    WAS_RUNNING=false
    if pgrep -x ClaudeCounter >/dev/null; then
        WAS_RUNNING=true
        echo "Stopping running instance..."
        pkill -x ClaudeCounter || true
        # Wait up to 3s for clean exit before forcing.
        for _ in 1 2 3 4 5 6; do
            pgrep -x ClaudeCounter >/dev/null || break
            sleep 0.5
        done
        pkill -9 -x ClaudeCounter 2>/dev/null || true
    fi

    echo "Installing to /Applications..."
    rm -rf "$DEST"
    cp -R "$APP_BUNDLE" "$DEST"
    # Strip quarantine attribute just in case.
    xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

    if $RELAUNCH || $WAS_RUNNING; then
        echo "Launching..."
        open "$DEST"
    fi
fi

# Emit the distributable artifact (notarized + stapled) for a GitHub release.
DIST_ZIP=""
if $NOTARIZE; then
    DIST_ZIP="$SCRIPT_DIR/../ClaudeCounter-${APP_VERSION}.zip"
    rm -f "$DIST_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"
    shasum -a 256 "$DIST_ZIP" | tee "$DIST_ZIP.sha256"
fi

echo ""
echo "=== Build Summary ==="
echo "Version:    $APP_VERSION (build $BUILD_NUMBER)"
echo "Identity:   $SIGN_ID"
echo "Bundle:     $APP_BUNDLE"
$INSTALL && echo "Installed:  $DEST"
[[ -n "$DIST_ZIP" ]] && echo "Artifact:   $DIST_ZIP"
echo "====================="
