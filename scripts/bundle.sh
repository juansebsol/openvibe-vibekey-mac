#!/bin/bash
# Builds VibeKey.app (menu bar app + bundled CLI) into ./build.
# Usage: scripts/bundle.sh            (ad-hoc signed)
#        SIGN_IDENTITY="Apple Development: …" scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-local.openvibe.vibekey-mac}"
SIGN="${SIGN_IDENTITY:--}"

swift build -c release --product VibeKey
swift build -c release --product vibekey-cli
BIN="$(swift build -c release --show-bin-path)"

APP="build/VibeKey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/VibeKey" "$APP/Contents/MacOS/VibeKey"
cp "$BIN/vibekey-cli" "$APP/Contents/MacOS/vibekey-cli"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: swift scripts/make-icon.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Vibe Key</string>
  <key>CFBundleDisplayName</key><string>Vibe Key</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>VibeKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Vibe Key records from the AU05 microphone while you hold the Mic button (only if you configure a Voice Record action).</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign "$SIGN" "$APP/Contents/MacOS/vibekey-cli"
codesign --force --options runtime --entitlements /dev/stdin --sign "$SIGN" "$APP" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENT

echo "Built $APP"
echo "Install: cp -R $APP /Applications/   (then open it from /Applications)"
