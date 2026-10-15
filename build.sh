#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
output="${1:-.build/Unbadge.app}"
output="${output:A}"
if [[ "${output:e}" != app ]]; then
    print -u2 '出力先には .app を指定してください。'
    exit 1
fi
if [[ -e "$output" ]]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$identifier" != io.github.tndd.Unbadge ]]; then
        print -u2 '出力先がUnbadgeではないため、上書きを中止しました。'
        exit 1
    fi
fi
mkdir -p "${output:h}" .build
stage="$(mktemp -d "${output:h}/.unbadge-build.XXXXXX")"
trap 'if [[ ! -e "$output" && -d "$stage/previous.app" ]]; then mv "$stage/previous.app" "$output"; fi; rm -rf "$stage"' EXIT
app="$stage/Unbadge.app"
icon_hash="$(shasum -a 256 Resources/AppIcon.png)"
icon_hash="${icon_hash%% *}"
icon_name="Unbadge-${icon_hash[1,12]}.icns"
iconset=".build/Unbadge.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
xcrun swiftc Scripts/pack-icon.swift -o .build/pack-icon
.build/pack-icon "$iconset" "$app/Contents/Resources/$icon_name"
xcrun swiftc -O -swift-version 5 Sources/BadgeStore.swift Sources/ApplicationCatalog.swift Sources/main.swift -o "$app/Contents/MacOS/Unbadge" -framework AppKit -framework ApplicationServices
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.tndd.Unbadge</string>
<key>CFBundleName</key><string>Unbadge</string>
<key>CFBundleDisplayName</key><string>Unbadge</string>
<key>CFBundleExecutable</key><string>Unbadge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $icon_name" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
if [[ -e "$output" ]]; then mv "$output" "$stage/previous.app"; fi
mv "$app" "$output"
print "作成完了: $output"
