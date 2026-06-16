#!/bin/zsh
set -euo pipefail

KEEP_DATA=0
for arg in "$@"; do
  case "$arg" in
    --keep-data)
      KEEP_DATA=1
      ;;
    *)
      echo "Usage: $0 [--keep-data]" >&2
      exit 2
      ;;
  esac
done

APP_NAME="Codex Usage.app"
SYSTEM_APP_DIR="/Applications/$APP_NAME"
USER_APP_DIR="$HOME/Applications/$APP_NAME"
SUPPORT_DIR="$HOME/Library/Application Support/CodexUsage"
HELPER="$SUPPORT_DIR/CodexUsageMenuBarHelper"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
COLLECTOR_PLIST="$LAUNCH_AGENTS/com.gukai.CodexUsage.collector.plist"
MENUBAR_PLIST="$LAUNCH_AGENTS/com.gukai.CodexUsage.menubar.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN" "$COLLECTOR_PLIST" >/dev/null 2>&1 || true
launchctl bootout "$DOMAIN" "$MENUBAR_PLIST" >/dev/null 2>&1 || true

osascript -e 'tell application id "com.gukai.CodexUsage" to quit' >/dev/null 2>&1 || true
pkill -f "$SYSTEM_APP_DIR/Contents/MacOS/CodexUsageMonitor" >/dev/null 2>&1 || true
pkill -f "$USER_APP_DIR/Contents/MacOS/CodexUsageMonitor" >/dev/null 2>&1 || true
pkill -f "$HELPER" >/dev/null 2>&1 || true

rm -f "$COLLECTOR_PLIST" "$MENUBAR_PLIST"
rm -rf "$SYSTEM_APP_DIR" "$USER_APP_DIR"

if [[ "$KEEP_DATA" == "1" ]]; then
  rm -f "$HELPER"
  echo "Uninstalled Codex Usage app and launch agents; kept $SUPPORT_DIR"
else
  rm -rf "$SUPPORT_DIR"
  echo "Uninstalled Codex Usage app, launch agents, and support data"
fi
