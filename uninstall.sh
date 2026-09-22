#!/bin/bash
#
# Removes logi-session-guard and restores stock Logi Options+ behavior.
#   sudo ./uninstall.sh
#
set -uo pipefail
GUARD_LABEL="com.local.logi-session-guard"
UI_LABEL="com.local.logimousestatus"
LOGI_PLIST="/Library/LaunchAgents/com.logi.optionsplus.plist"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo:  sudo ./uninstall.sh" >&2; exit 1; }

LOGI_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$LOGI_PLIST" 2>/dev/null || echo com.logi.cp-dev-mgr)"

echo "==> Unloading from every active GUI session"
for uid in $(ps -axo uid,command | awk '/loginwindow.app\/Contents\/MacOS\/loginwindow console/ {print $1}' | sort -u); do
  [ "$uid" -ge 500 ] || continue
  name="$(id -un "$uid" 2>/dev/null || echo "uid $uid")"
  for L in "$GUARD_LABEL" "$UI_LABEL"; do
    launchctl bootout "gui/${uid}/${L}" 2>/dev/null || true
  done
  # put Logitech's own agent back everywhere
  launchctl enable    "gui/${uid}/${LOGI_LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/${uid}" "$LOGI_PLIST" 2>/dev/null || true
  echo "    restored ${name}"
done

echo "==> Removing files"
rm -f  "/Library/LaunchAgents/${GUARD_LABEL}.plist" \
       "/Library/LaunchAgents/${UI_LABEL}.plist" \
       /usr/local/bin/logi-session-guard.sh
rm -rf /Applications/LogiMouseStatus.app

echo "==> Per-account leftovers (logs and state)"
for home in /Users/*; do
  u="$(basename "$home")"; [ "$u" = "Shared" ] && continue
  id -u "$u" >/dev/null 2>&1 || continue
  rm -rf "${home}/Library/Caches/logi-guard" 2>/dev/null
  rm -f  "${home}/Library/Logs/logi-session-guard.log" 2>/dev/null
done

echo
echo "Removed. Logi Options+ is back to its stock behavior."
