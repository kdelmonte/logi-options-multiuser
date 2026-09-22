#!/bin/bash
#
# Installer for logi-session-guard.
#   sudo ./install.sh              # guard + menu-bar status helper
#   sudo ./install.sh --no-ui      # guard only (skips the Swift build)
#
set -uo pipefail

GUARD_LABEL="com.local.logi-session-guard"
UI_LABEL="com.local.logimousestatus"
GUARD_BIN="/usr/local/bin/logi-session-guard.sh"
GUARD_PLIST="/Library/LaunchAgents/${GUARD_LABEL}.plist"
UI_APP="/Applications/LogiMouseStatus.app"
UI_PLIST="/Library/LaunchAgents/${UI_LABEL}.plist"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src"
WITH_UI=1
[ "${1:-}" = "--no-ui" ] && WITH_UI=0

die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo:  sudo ./install.sh"
[ "$(uname -s)" = "Darwin" ] || die "macOS only"
[ -f "$SRC_DIR/logi-session-guard.sh" ] || die "missing $SRC_DIR/logi-session-guard.sh"

echo "==> Checking for Logi Options+"
LOGI_PLIST="/Library/LaunchAgents/com.logi.optionsplus.plist"
[ -f "$LOGI_PLIST" ] || die "Logi Options+ does not appear to be installed ($LOGI_PLIST not found)"
LOGI_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$LOGI_PLIST" 2>/dev/null)"
[ -n "$LOGI_LABEL" ] || die "could not read the Label from $LOGI_PLIST"
echo "    found: $LOGI_LABEL"

echo "==> Installing the guard"
install -d -o root -g wheel -m 755 /usr/local/bin
install -o root -g wheel -m 755 "$SRC_DIR/logi-session-guard.sh" "$GUARD_BIN"

cat > "$GUARD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${GUARD_LABEL}</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>${GUARD_BIN}</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>LOGI_GUARD_LABEL</key><string>${LOGI_LABEL}</string>
        <key>LOGI_GUARD_PLIST</key><string>${LOGI_PLIST}</string>
        <key>LOGI_GUARD_POLL</key><string>1</string>
        <key>LOGI_GUARD_NOTIFY</key><string>0</string>
        <key>LOGI_GUARD_ETA</key><string>15</string>
    </dict>
</dict>
</plist>
PLIST
chown root:wheel "$GUARD_PLIST"; chmod 644 "$GUARD_PLIST"
plutil -lint "$GUARD_PLIST" >/dev/null || die "generated plist is invalid"

if [ "$WITH_UI" = "1" ]; then
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "    swiftc not found — skipping the menu-bar helper."
    echo "    Install Xcode Command Line Tools (xcode-select --install) and re-run,"
    echo "    or use --no-ui to silence this."
    WITH_UI=0
  fi
fi

if [ "$WITH_UI" = "1" ]; then
  echo "==> Building the menu-bar helper"
  TMP="$(mktemp -d)"
  swiftc -O -o "$TMP/LogiMouseStatus" "$SRC_DIR/LogiMouseStatus.swift" 2>/dev/null \
    || die "swiftc failed"
  rm -rf "$UI_APP"
  mkdir -p "$UI_APP/Contents/MacOS"
  mv "$TMP/LogiMouseStatus" "$UI_APP/Contents/MacOS/"
  cat > "$UI_APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>LogiMouseStatus</string>
    <key>CFBundleIdentifier</key><string>com.local.logimousestatus</string>
    <key>CFBundleName</key><string>LogiMouseStatus</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PL
  codesign --force --deep -s - "$UI_APP" >/dev/null 2>&1
  chown -R root:wheel "$UI_APP"
  xattr -dr com.apple.quarantine "$UI_APP" 2>/dev/null || true
  rm -rf "$TMP"

  cat > "$UI_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${UI_LABEL}</string>
    <key>ProgramArguments</key>
    <array><string>${UI_APP}/Contents/MacOS/LogiMouseStatus</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
  chown root:wheel "$UI_PLIST"; chmod 644 "$UI_PLIST"
  plutil -lint "$UI_PLIST" >/dev/null || die "generated UI plist is invalid"
fi

echo "==> Loading into every active GUI session"
for uid in $(ps -axo uid,command | awk '/loginwindow.app\/Contents\/MacOS\/loginwindow console/ {print $1}' | sort -u); do
  [ "$uid" -ge 500 ] || continue
  name="$(id -un "$uid" 2>/dev/null || echo "uid $uid")"
  for L in "$GUARD_LABEL" "$UI_LABEL"; do
    launchctl bootout "gui/${uid}/${L}" 2>/dev/null || true
    launchctl enable  "gui/${uid}/${L}" 2>/dev/null || true
  done
  launchctl bootstrap "gui/${uid}" "$GUARD_PLIST" 2>/dev/null && echo "    guard  -> ${name}"
  [ "$WITH_UI" = "1" ] && launchctl bootstrap "gui/${uid}" "$UI_PLIST" 2>/dev/null && echo "    status -> ${name}"
done

cat <<'DONE'

Installed. Other accounts pick it up automatically at their next login.

  log     ~/Library/Logs/logi-session-guard.log   (per account)
  state   ~/Library/Caches/logi-guard/state
  remove  sudo ./uninstall.sh

Test it: switch accounts and back. The menu-bar dot goes grey while another
account holds the mouse and green when yours does.
DONE
