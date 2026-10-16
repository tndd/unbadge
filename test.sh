#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
testdir="$(mktemp -d -t badge-control-tests)"
trap 'rm -rf "$testdir"' EXIT
xcrun swiftc -swift-version 5 Sources/BadgeStore.swift Sources/SettingsDockTile.swift Sources/ApplicationCatalog.swift Tests/main.swift -o "$testdir/tests"
"$testdir/tests"
