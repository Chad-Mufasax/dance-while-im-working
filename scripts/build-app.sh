#!/usr/bin/env bash
# Build DanceWhileImWorking.app from the SPM target.
# Outputs to dist/DanceWhileImWorking.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="DanceWhileImWorking"
BUNDLE_ID="com.mufasa.dance-while-im-working"
CONFIG="${1:-release}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$ROOT/dist/$APP_NAME.app"

echo "==> assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Dance While I'm Working</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>dance-while-im-working reads terminal windows to detect Claude Code permission prompts.</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "==> ad-hoc code signing (required for Accessibility permission persistence)"
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\""
