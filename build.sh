#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="${1:-.build/Unbadge.app}"
iconset=".build/Unbadge.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -swift-version 5 Sources/BadgeStore.swift Sources/ApplicationCatalog.swift Sources/main.swift -o "$app/Contents/MacOS/Unbadge" -framework AppKit -framework ApplicationServices
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.tndd.Unbadge</string>
<key>CFBundleName</key><string>Unbadge</string>
<key>CFBundleDisplayName</key><string>Unbadge</string>
<key>CFBundleExecutable</key><string>Unbadge</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "作成完了: $app"
