#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="${1:-.build/Badge Control.app}"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -O -swift-version 5 Sources/BadgeStore.swift Sources/ApplicationCatalog.swift Sources/main.swift -o "$app/Contents/MacOS/BadgeControl" -framework AppKit -framework ApplicationServices
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex.BadgeControl</string>
<key>CFBundleName</key><string>Badge Control</string>
<key>CFBundleExecutable</key><string>BadgeControl</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "作成完了: $app"
