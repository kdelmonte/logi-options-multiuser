#!/bin/bash
#
# logi-session-guard
#
# Logi Options+ installs its device manager from a SYSTEM-WIDE LaunchAgent, so macOS
# starts a copy in every GUI login session. Under fast user switching, two or more
# sessions then fight over the same physical mouse, producing "Fix Device" errors,
# settings that silently fail to apply, and random quits.
#
# Only one person is at the screen at a time. macOS tracks that as the "console user".
# This guard runs in each session and keeps the device manager alive ONLY in the session
# that currently owns the console, handing it off on every switch. Each account keeps its
# own Options+ settings.
#
# Optional companion: LogiMouseStatus.app renders the state file as a menu-bar dot.

set -u

# Logitech's label and LaunchAgent. Overridable via the environment if Logitech ever
# changes them; the installer verifies these at install time.
LABEL="${LOGI_GUARD_LABEL:-com.logi.cp-dev-mgr}"
PLIST="${LOGI_GUARD_PLIST:-/Library/LaunchAgents/com.logi.optionsplus.plist}"
APP_BUNDLE_ID="${LOGI_GUARD_APP_ID:-com.logi.optionsplus}"

POLL_SECONDS="${LOGI_GUARD_POLL:-1}"   # seconds between console-user checks
NOTIFY="${LOGI_GUARD_NOTIFY:-0}"       # 1 = also post a notification on handoff
ETA="${LOGI_GUARD_ETA:-15}"            # seconds from pairing until buttons respond

ME_NAME="$(id -un)"
ME_UID="$(id -u)"
DOMAIN="gui/${ME_UID}"

LOG="${HOME}/Library/Logs/logi-session-guard.log"
STATE_DIR="${HOME}/Library/Caches/logi-guard"
STATE="${STATE_DIR}/state"

# Options+ rewrites this when it actually enumerates and pairs a device. Watching it is
# far more honest than watching for the agent process, which spawns almost instantly and
# does its device work afterwards.
PAIRED="${HOME}/Library/Application Support/logioptionsplus/devio_cache/paired.xml"

mkdir -p "$(dirname "$LOG")" "$STATE_DIR" 2>/dev/null

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null
  if [ -f "$LOG" ] && [ "$(wc -l <"$LOG" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -n 500 "$LOG" >"${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "$LOG" 2>/dev/null
  fi
}

# write_state <state> <owner> [deadline]
#   state=ready|settling|inactive|error
write_state() {
  local tmp="${STATE}.tmp.$$"
  { printf 'state=%s\nowner=%s\n' "$1" "$2"
    [ -n "${3:-}" ] && printf 'deadline=%s\n' "$3"
  } > "$tmp" 2>/dev/null && mv "$tmp" "$STATE" 2>/dev/null
}

notify() {
  [ "$NOTIFY" = "1" ] || return 0
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1
}

# BSD stat explicitly: GNU coreutils on PATH would reject -f
console_user() { /usr/bin/stat -f%Su /dev/console 2>/dev/null; }
is_loaded()    { launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; }
paired_mtime() { /usr/bin/stat -f%m "$PAIRED" 2>/dev/null || echo 0; }

claim_device() {
  local t0 before now elapsed i=0 ok=0
  t0=$(date +%s)
  before="$(paired_mtime)"

  # provisional estimate, corrected the moment pairing is observed
  write_state settling "$ME_NAME" "$(( t0 + 25 ))"

  log "claiming device manager (console user is ${ME_NAME})"
  launchctl enable "${DOMAIN}/${LABEL}" 2>/dev/null
  if is_loaded; then
    launchctl kickstart -k "${DOMAIN}/${LABEL}" 2>/dev/null
  else
    launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null
  fi

  while [ "$i" -lt 50 ]; do          # up to ~25s
    now="$(paired_mtime)"
    if [ "$now" != "$before" ] && [ "$now" != "0" ]; then ok=1; break; fi
    sleep 0.5
    i=$((i+1))
  done

  elapsed=$(( $(date +%s) - t0 ))
  if [ "$ok" = "1" ]; then
    write_state settling "$ME_NAME" "$(( $(date +%s) + ETA ))"
    log "device paired after ${elapsed}s; buttons expected within ~${ETA}s"
    notify "Mouse paired" "${ME_NAME} · buttons live in ~${ETA}s"
  else
    write_state error "$ME_NAME"
    log "WARNING: no re-pair detected within ${elapsed}s"
    notify "Mouse handoff unconfirmed" "Options+ did not report pairing in ${elapsed}s"
  fi
}

release_device() {
  log "releasing device manager (console user is ${1:-unknown})"
  write_state inactive "${1:-unknown}"
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null
  osascript -e "quit app id \"${APP_BUNDLE_ID}\"" 2>/dev/null
}

last=""
log "guard started for ${ME_NAME} (uid ${ME_UID}), poll=${POLL_SECONDS}s notify=${NOTIFY} eta=${ETA}s"

# reflect reality at startup rather than showing a stale state
if [ "$(console_user)" = "$ME_NAME" ]; then
  write_state ready "$ME_NAME"
else
  write_state inactive "$(console_user)"
fi

while true; do
  active="$(console_user)"
  if [ -n "$active" ] && [ "$active" != "$last" ]; then
    if [ "$active" = "$ME_NAME" ]; then claim_device; else release_device "$active"; fi
    last="$active"
  fi
  sleep "$POLL_SECONDS"
done
