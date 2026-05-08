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
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --update)  INSTALL=true; RELAUNCH=true ;;
        --help|-h)
            echo "Usage: build-app.sh [--install] [--update]"
            echo "  --install   build + replace /Applications/ClaudeCounter.app"
            echo "  --update    --install + kill + relaunch"
            exit 0 ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
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

# Pick signing identity: stable self-signed cert if present, else ad-hoc.
# A self-signed cert won't appear in `find-identity -p codesigning` (no
# trust attachment) but codesign can still use it by name as long as the
# private key is in the keychain.
if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    SIGN_ID="$CERT_NAME"
    echo "Signing with stable identity: $CERT_NAME"
else
    SIGN_ID="-"
    echo "WARN: stable cert not found — using ad-hoc signing."
    echo "      Run 'make setup-cert' once to preserve permissions"
    echo "      (TCC + Login Item) across rebuilds."
fi
codesign --force --deep --sign "$SIGN_ID" "$APP_BUNDLE"

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

echo ""
echo "=== Build Summary ==="
echo "Identity:   $SIGN_ID"
echo "Bundle:     $APP_BUNDLE"
$INSTALL && echo "Installed:  $DEST"
echo "====================="
