#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/objc"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

clang \
  -fobjc-arc \
  -O2 \
  -isysroot "$SDK" \
  -mmacosx-version-min=13.0 \
  -framework Foundation \
  -framework AppKit \
  "$ROOT/Sources/ObjC/CodexUsageMonitor.m" \
  -o "$BUILD_DIR/CodexUsageMonitor"

echo "Built $BUILD_DIR/CodexUsageMonitor"
