#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/toolchain.sh"
APP_DIR="/Applications/Codex Usage.app"
[[ -w /Applications ]] || APP_DIR="$HOME/Applications/Codex Usage.app"
SUPPORT_DIR="$HOME/Library/Application Support/CodexUsage"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
MENUBAR_PLIST="$LAUNCH_AGENTS/com.gukai.CodexUsage.menubar.plist"
COLLECTOR_PLIST="$LAUNCH_AGENTS/com.gukai.CodexUsage.collector.plist"
DOMAIN="gui/$(id -u)"

"$ROOT/Scripts/build-objc.sh"
mkdir -p "$SUPPORT_DIR" "$LAUNCH_AGENTS" "$HOME/Library/Logs"
STAGING="$(mktemp -d "$SUPPORT_DIR/install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/Codex Usage.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$ROOT/.build/objc/CodexUsageMonitor" "$STAGED_APP/Contents/MacOS/"
cp "$ROOT/Packaging/AppIcon.icns" "$STAGED_APP/Contents/Resources/"
cp "$ROOT/Packaging/PrivacyInfo.xcprivacy" "$STAGED_APP/Contents/Resources/"
python3 - "$STAGED_APP" "$MENUBAR_PLIST" "$APP_DIR" <<'PY'
import os,sys,plistlib
staged,agent,app=sys.argv[1:]
info=dict(CFBundleDevelopmentRegion='zh_CN',CFBundleDisplayName='Codex Usage',
          CFBundleExecutable='CodexUsageMonitor',CFBundleIconFile='AppIcon',
          CFBundleIdentifier='com.gukai.CodexUsage',CFBundleInfoDictionaryVersion='6.0',
          CFBundleName='Codex Usage',CFBundlePackageType='APPL',
          CFBundleShortVersionString='0.1.10',CFBundleVersion='11',
          LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True)
with open(staged+'/Contents/Info.plist','wb') as f: plistlib.dump(info,f)
job=dict(Label='com.gukai.CodexUsage.menubar',
         ProgramArguments=[app+'/Contents/MacOS/CodexUsageMonitor','--menubar'],
         RunAtLoad=True,KeepAlive={'SuccessfulExit':False},ThrottleInterval=10,
         ProcessType='Interactive',
         StandardErrorPath='/dev/null',StandardOutPath='/dev/null')
if os.environ.get('CODEX_HOME'):
    job['EnvironmentVariables']={'CODEX_HOME':os.path.abspath(os.path.expanduser(os.environ['CODEX_HOME']))}
with open(agent+'.pending','wb') as f: plistlib.dump(job,f)
PY
codesign --force --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
launchctl bootout "$DOMAIN/com.gukai.CodexUsage.collector" >/dev/null 2>&1 || true
launchctl bootout "$DOMAIN/com.gukai.CodexUsage.menubar" >/dev/null 2>&1 || true
rm -f "$COLLECTOR_PLIST"
# Keep recovery copies compressed so macOS cannot index them as extra apps.
if [[ -d "$APP_DIR" ]]; then
  mkdir -p "$SUPPORT_DIR/Backups"
  ARCHIVE="$SUPPORT_DIR/Backups/CodexUsage-$(date +%Y%m%d%H%M%S).tar.gz"
  tar -czf "$STAGING/previous.tar.gz" -C "$(dirname "$APP_DIR")" "$(basename "$APP_DIR")"
  mv "$STAGING/previous.tar.gz" "$ARCHIVE"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP_DIR" >/dev/null 2>&1 || true
  mv "$APP_DIR" "$STAGING/previous.retired"
fi
mkdir -p "$(dirname "$APP_DIR")"
mv "$STAGED_APP" "$APP_DIR"
mv "$MENUBAR_PLIST.pending" "$MENUBAR_PLIST"
"$APP_DIR/Contents/MacOS/CodexUsageMonitor" --collect --print
launchctl bootstrap "$DOMAIN" "$MENUBAR_PLIST"
launchctl kickstart "$DOMAIN/com.gukai.CodexUsage.menubar"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
echo "Installed $APP_DIR (menu bar, refresh every 60 seconds, start at login)"
