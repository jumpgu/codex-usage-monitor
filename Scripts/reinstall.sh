#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/Scripts/uninstall.sh" --keep-data
"$ROOT/Scripts/install.sh"
