# Contributing

Thanks for looking. This is a small tool with a narrow job, so contributions are very
welcome but the bar for scope creep is high — it should stay something you can read in
one sitting.

## Reporting a problem

Handoff bugs are hard to debug from a description alone. Please include:

```bash
# macOS and hardware
sw_vers && uname -m

# Options+ version
defaults read /Applications/logioptionsplus.app/Contents/Info.plist CFBundleShortVersionString

# the guard's own log, from the account where it misbehaved
tail -40 ~/Library/Logs/logi-session-guard.log

# what the guard thinks the state is
cat ~/Library/Caches/logi-guard/state

# who actually holds the mouse (should be exactly one uid)
ps -axo uid,user,comm | grep logioptionsplus_agent | grep -v updater

# is the job loaded and running?
launchctl print "gui/$(id -u)/com.local.logi-session-guard" | grep -E "state|pid"
```

Also say **how many accounts** were logged in and **which direction** you switched.
Please redact usernames if you'd rather not share them — `uid` numbers are enough.

### Known non-bugs

- **A 20–25 second handoff.** Most of that is macOS's login-window transition and
  Options+ enumerating the device. See the timing table in the README.
- **A 2–3 second overlap where both accounts hold the mouse.** Documented race in the
  poll window; it self-corrects.
- **The countdown finishing before your buttons respond.** `LOGI_GUARD_ETA` is an
  estimate tuned on one machine. Adjust it to your hardware.

## Testing a change

This is the awkward part: **you need at least two macOS accounts** and you have to
actually switch between them. There's no meaningful unit test for "did launchd hand the
HID device over."

A reasonable loop:

1. `sudo ./install.sh` on your change
2. Open a recorder in one account so you have evidence from the switched-away side:

```bash
while true; do
  printf '%s console=%s managers=[%s]\n' "$(date +%H:%M:%S)" \
    "$(/usr/bin/stat -f%Su /dev/console)" \
    "$(ps -axo uid,comm | grep logioptionsplus_agent | grep -v updater | awk '{print $1}' | sort -u | tr '\n' ',')"
  sleep 2
done
```

3. Switch away, wait, switch back, switch a third time — some issues only appear on the
   second or third cycle
4. Check that `managers=[...]` never shows two uids *persisting*

Please say in the PR how many accounts you tested with and how many switch cycles.

## Code layout

| File | What it is |
|---|---|
| `src/logi-session-guard.sh` | the whole arbitration — bash, no dependencies |
| `src/LogiMouseStatus.swift` | optional menu-bar helper, reads the state file |
| `install.sh` / `uninstall.sh` | launchd wiring |

The two components talk **only** through `~/Library/Caches/logi-guard/state`. Keep it
that way — it means the helper can crash without touching your mouse, and anyone can
write a different UI against the same contract.

## Conventions

**Use absolute paths for BSD tools.** The guard runs under launchd, where `stat`, `sed`
and `ls` are BSD. Someone's Homebrew coreutils could shadow them in an interactive shell,
so write `/usr/bin/stat -f%Su`, not `stat -f%Su`.

**Don't hardcode Logitech's label or paths in the guard.** The installer reads them from
Logitech's own plist and passes them in via `EnvironmentVariables`. If you need another
Logitech-specific path, follow that pattern.

**Verify the signal, not a proxy for it.** An earlier version detected readiness by
waiting for the agent *process* to exist and reported success in 1 second when reality was
25 — the process spawns instantly and does its device work afterwards. If you add a new
check, confirm it observes the event you actually care about.

**No secrets, no personal paths.** Nothing in this repo should contain a username, a home
directory, or a machine-specific identifier. Use `$HOME`, `id -un`, `NSUserName()`.

## Things that would genuinely help

- **Removing the transient overlap** without adding a fixed delay to every handoff.
  A release-then-claim handshake through the state file is the obvious direction.
- **A better readiness signal.** `devio_cache/paired.xml` works but is undocumented and
  could change. Anything more durable would be a real improvement.
- **Other vendors.** Razer, SteelSeries, Elgato and Logitech's own webcam software all
  have the same single-owner-agent problem. The arbitration logic is vendor-neutral;
  only the label, plist path and readiness signal differ.
- **Reports from more hardware.** Enumeration time varies by device count, and the
  `LOGI_GUARD_ETA` default is one data point.

## Scope

Things this project should **not** grow into: a general mouse remapper, a launchd
manager, or anything with a settings UI. It arbitrates one device between sessions. If a
change doesn't serve that, it probably belongs elsewhere.

## License

Contributions are accepted under the MIT license in [LICENSE](LICENSE).
