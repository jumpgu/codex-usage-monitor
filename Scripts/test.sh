#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/toolchain.sh"
mkdir -p "$ROOT/.build/tests"
clang -fobjc-arc -O2 -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -mmacosx-version-min=13.0 -framework Foundation -framework AppKit "$ROOT/Tests/MonitorTests.m" -o "$ROOT/.build/tests/MonitorTests"
"$ROOT/.build/tests/MonitorTests"
