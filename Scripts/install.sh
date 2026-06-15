#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJC_BUILD_DIR="$ROOT/.build/objc"
SWIFT_BUILD_DIR="$ROOT/.build/release"
APP_NAME="Codex Usage.app"
SYSTEM_APP_DIR="/Applications/$APP_NAME"
USER_APP_DIR="$HOME/Applications/$APP_NAME"
APP_DIR="$SYSTEM_APP_DIR"
TEST_DIR="/Applications/.codexusage-install-test"
rm -rf "$TEST_DIR" >/dev/null 2>&1 || true
if mkdir "$TEST_DIR" >/dev/null 2>&1; then
  rmdir "$TEST_DIR"
else
  APP_DIR="$USER_APP_DIR"
fi
EXT_DIR="$APP_DIR/Contents/PlugIns/CodexUsageWidgets.appex"
USER_EXT_DIR="$USER_APP_DIR/Contents/PlugIns/CodexUsageWidgets.appex"
SUPPORT_DIR="$HOME/Library/Application Support/CodexUsage"
HELPER="$SUPPORT_DIR/CodexUsageMenuBarHelper"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
COLLECTOR_PLIST="$LAUNCH_AGENTS/com.gukai.CodexUsage.collector.plist"
MENUBAR_PLIST="$LAUNCH_AGENTS/com.gukai.CodexUsage.menubar.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT/Scripts/build-objc.sh"
"$ROOT/Scripts/build.sh"
swift "$ROOT/Scripts/generate-icon.swift" "$ROOT"
iconutil -c icns "$ROOT/Packaging/AppIcon.iconset" -o "$ROOT/Packaging/AppIcon.icns"

osascript -e 'tell application id "com.gukai.CodexUsage" to quit' >/dev/null 2>&1 || true
pkill -f "$SYSTEM_APP_DIR/Contents/MacOS/CodexUsageMonitor" >/dev/null 2>&1 || true
pkill -f "$USER_APP_DIR/Contents/MacOS/CodexUsageMonitor" >/dev/null 2>&1 || true

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$EXT_DIR/Contents/MacOS" "$LAUNCH_AGENTS" "$SUPPORT_DIR"

cp "$OBJC_BUILD_DIR/CodexUsageMonitor" "$APP_DIR/Contents/MacOS/CodexUsageMonitor"
cp "$OBJC_BUILD_DIR/CodexUsageMonitor" "$HELPER"
cp "$ROOT/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$SWIFT_BUILD_DIR/CodexUsageWidgets" "$EXT_DIR/Contents/MacOS/CodexUsageWidgets"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Usage</string>
  <key>CFBundleExecutable</key>
  <string>CodexUsageMonitor</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.gukai.CodexUsage</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Codex Usage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$EXT_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Usage</string>
  <key>CFBundleExecutable</key>
  <string>CodexUsageWidgets</string>
  <key>CFBundleIdentifier</key>
  <string>com.gukai.CodexUsage.widgets</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CodexUsageWidgets</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
    <key>NSExtensionAttributes</key>
    <dict>
      <key>WKAppBundleIdentifier</key>
      <string>com.gukai.CodexUsage</string>
    </dict>
  </dict>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_DIR/Contents/MacOS/CodexUsageMonitor"
/usr/bin/codesign --force --sign - "$HELPER"
/usr/bin/codesign --force --sign - --entitlements "$ROOT/Packaging/CodexUsageWidget.entitlements" "$EXT_DIR"
/usr/bin/codesign --force --sign - "$APP_DIR"

"$APP_DIR/Contents/MacOS/CodexUsageMonitor" --collect --print

cat > "$COLLECTOR_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.gukai.CodexUsage.collector</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_DIR/Contents/MacOS/CodexUsageMonitor</string>
    <string>--collect</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/CodexUsage.collector.err.log</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/CodexUsage.collector.out.log</string>
</dict>
</plist>
PLIST

cat > "$MENUBAR_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.gukai.CodexUsage.menubar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER</string>
    <string>--menubar</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/CodexUsage.menubar.err.log</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/CodexUsage.menubar.out.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$COLLECTOR_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$MENUBAR_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$COLLECTOR_PLIST"
launchctl bootstrap "gui/$(id -u)" "$MENUBAR_PLIST"
launchctl kickstart -k "gui/$(id -u)/com.gukai.CodexUsage.collector"
launchctl kickstart -k "gui/$(id -u)/com.gukai.CodexUsage.menubar"

if [[ "$APP_DIR" != "$USER_APP_DIR" ]]; then
  rm -rf "$USER_APP_DIR"
fi

"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
pluginkit -r "$USER_EXT_DIR" >/dev/null 2>&1 || true
pluginkit -r "$EXT_DIR" >/dev/null 2>&1 || true
pluginkit -a "$EXT_DIR" || true
pluginkit -e use -i com.gukai.CodexUsage.widgets >/dev/null 2>&1 || true
killall WidgetKitExtension WidgetKitExtensionAgent chronod >/dev/null 2>&1 || true

echo "Installed $APP_DIR"
echo "Summary $HOME/Library/Application Support/CodexUsage/usage_summary.json"
