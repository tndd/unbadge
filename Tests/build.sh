#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
testdir="$(mktemp -d "$PWD/.build/bundle-tests.XXXXXX")"
trap 'rm -rf "$testdir"' EXIT
target="$testdir/Unbadge Test.app"

./build.sh "$target"
icon=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$target/Contents/Info.plist")
[[ "$icon" == Unbadge-*.icns && -f "$target/Contents/Resources/$icon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")" == 0.4.1 ]]

# 旧バンドルの残骸が再ビルドで引き継がれないこと。
touch "$target/Contents/Resources/OldIcon.icns" "$target/Contents/MacOS/OldExecutable"
./build.sh "$target"
[[ ! -e "$target/Contents/Resources/OldIcon.icns" && ! -e "$target/Contents/MacOS/OldExecutable" ]]

# ビルド途中の失敗で、正常な旧版が壊れないこと。
before="$(shasum -a 256 "$target/Contents/MacOS/Unbadge")"
mkdir "$testdir/tools"
print '#!/bin/zsh\nexit 97' > "$testdir/tools/xcrun"
chmod +x "$testdir/tools/xcrun"
if PATH="$testdir/tools:$PATH" ./build.sh "$target" >"$testdir/failure.log" 2>&1; then
    print -u2 '失敗を注入したビルドが成功扱いになりました。'
    exit 1
fi
[[ "$before" == "$(shasum -a 256 "$target/Contents/MacOS/Unbadge")" ]]
codesign --verify --strict "$target"

# 他のアプリを指定しても上書きしないこと。
other="$testdir/Other.app"
mkdir -p "$other/Contents"
print '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.other</string></dict></plist>' > "$other/Contents/Info.plist"
touch "$other/keep"
if ./build.sh "$other" >"$testdir/other.log" 2>&1; then
    print -u2 '別アプリの上書きが成功扱いになりました。'
    exit 1
fi
[[ -f "$other/keep" ]]
[[ -z "$(find "$testdir" -maxdepth 1 -name '.unbadge-build.*' -print)" ]]
print 'バンドル生成・旧ファイル除去・失敗時の保持・別アプリ保護の検証に成功。'
