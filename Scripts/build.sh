#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
CORE_SOURCES=("$ROOT"/Sources/CodexUsageCore/*.swift)

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

swiftc \
  -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -parse-as-library \
  -emit-library \
  -static \
  -emit-module \
  -module-name CodexUsageCore \
  -emit-module-path "$BUILD_DIR/CodexUsageCore.swiftmodule" \
  "${CORE_SOURCES[@]}" \
  -o "$BUILD_DIR/libCodexUsageCore.a"

swiftc \
  -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lCodexUsageCore \
  "$ROOT/Sources/CodexUsageCLI/main.swift" \
  -o "$BUILD_DIR/CodexUsageCLI"

swiftc \
  -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lCodexUsageCore \
  "$ROOT/Sources/CodexUsageMenuBar/main.swift" \
  -o "$BUILD_DIR/CodexUsageMenuBar"

swiftc \
  -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -application-extension \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lCodexUsageCore \
  "$ROOT/Sources/CodexUsageWidgets/main.swift" \
  -o "$BUILD_DIR/CodexUsageWidgets"

echo "Built products in $BUILD_DIR"
