#!/bin/bash
# Builds Tint.app and installs it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Tint.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target arm64-apple-macos13 main.swift -o "$APP/Contents/MacOS/Tint"

mkdir -p "$APP/Contents/Resources"
swift make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.tint</string>
    <key>CFBundleName</key><string>Tint</string>
    <key>CFBundleExecutable</key><string>Tint</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Move rather than copy, so Spotlight doesn't list a second Tint.app in build/.
rm -rf /Applications/Tint.app
mv "$APP" /Applications/
echo "Installed /Applications/Tint.app"
