#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"

xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  "$ROOT/Sources/MenuFold/Models/MenuBarItem.swift" \
  "$ROOT/Sources/MenuFold/Models/AppPreferences.swift" \
  "$ROOT/scripts/self-test.swift" \
  -o "$ROOT/.build/MenuFoldSelfTest" \
  -framework AppKit

"$ROOT/.build/MenuFoldSelfTest"
