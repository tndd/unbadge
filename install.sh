#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
destination="${1:-$HOME/Applications/Unbadge.app}"
destination="${destination:A}"

# 出力先の識別と、失敗時に旧版を残す置換はbuild.sh側で行う。
./build.sh "$destination"
register=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
touch "$destination"
"$register" -f "$destination"
mdimport "$destination"
print "インストール完了: $destination"
print 'SpotlightやAlfredの検索欄を開き直して、Unbadgeを確認してください。'
