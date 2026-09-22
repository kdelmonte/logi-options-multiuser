# logi-options-multiuser

**Fixes Logi Options+ "Fix Device" errors when using multiple macOS accounts with fast
user switching.** Each account keeps its own button mappings.

If you use more than one macOS account and switch between them without logging out,
Logi Options+ breaks: "Fix Device" errors, settings that silently stop applying, and the
app quitting at random. This fixes that, and every account keeps its own button mappings.

---

## The problem

Logi Options+ installs its device manager from a **system-wide** LaunchAgent
(`/Library/LaunchAgents/com.logi.optionsplus.plist`). macOS starts system-wide agents in
*every* GUI login session — so with two accounts logged in, two device managers both try
to own one physical mouse. Neither wins cleanly.

This isn't unique to Logitech. Every mouse-customization tool on macOS has some version
of it, and none of them solve it:

| Tool | Multi-user status |
|---|---|
| Logi Options+ | breaks under fast user switching |
| Mac Mouse Fix | [open issue](https://github.com/noah-nuebling/mac-mouse-fix/issues/1669), no fix |
| BetterTouchTool | developer: *"no good way to workaround this"* |
| Karabiner-Elements | [issue](https://github.com/pqrs-org/Karabiner-Elements/issues/4433) closed as stale |

The common workaround you'll find online is to permanently disable Options+ in secondary
accounts. That trades one broken thing for another.

## The fix

Only one person is at the screen at a time. macOS already tracks who that is — the
**console user**, readable from `/dev/console`.

A small guard runs in each session and asks one question every second: *am I the console
user?*

| Answer | Action |
|---|---|
| Yes | start my device manager (`launchctl kickstart -k`) |
| No | stop my device manager (`launchctl bootout`) |

Exactly one device manager is alive at any moment, and it's always the right one. Each
account keeps its own settings, because each account's own agent runs when that person is
at the screen.

## Install

```bash
git clone https://github.com/kdelmonte/logi-options-multiuser.git
cd logi-options-multiuser
sudo ./install.sh
```

That's it. Every account on the machine is covered, including accounts that aren't logged
in yet and any you create later — the guard installs as a system-wide LaunchAgent, the
same mechanism Logitech uses.

Guard only, skipping the menu-bar helper:

```bash
sudo ./install.sh --no-ui
```

**Requirements:** macOS 12+, Logi Options+ already installed, and Xcode Command Line
Tools (`xcode-select --install`) for the menu-bar helper. The installer verifies Options+
is present and reads its label from the plist rather than assuming one.

## The menu-bar dot

A small status item shows who holds the mouse, in every account:

| Dot | Meaning |
|---|---|
| 🟢 green | this account holds the mouse and it has settled |
| 🟠 amber + `12s` | claiming it — counts down, then turns green |
| ⚪️ grey | another account holds it (click to see which) |
| 🔴 red + `!` | Options+ never reported pairing — something is wrong |

Click it for detail and a shortcut to the log.

## What a switch looks like

Say `alice` and `bob` are both logged in, and `alice` is at the screen:

```
alice's menu bar:  🟢        bob's menu bar:  ⚪️
```

`alice` switches to `bob`. Within about a second, `alice`'s guard releases the mouse;
`bob`'s guard claims it and counts down while Options+ enumerates the device:

```
alice's menu bar:  ⚪️        bob's menu bar:  🟠 12s  →  🟢
```

`bob` now has the mouse with *bob's* button mappings. Switching back reverses it.

A full handoff takes roughly 20–25 seconds end to end. Most of that is not this tool:

| Phase | Duration | Owner |
|---|---|---|
| macOS login-window transition | 5–7s | Apple |
| Guard detects the console change | ~1s | **this tool** |
| Options+ pairs the device | ~8s | Logitech |
| Mappings become responsive | ~15s | Logitech |

## Configuration

Settings live in the LaunchAgent's `EnvironmentVariables`. Change one without
reinstalling:

```bash
sudo /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:LOGI_GUARD_ETA 12" \
  /Library/LaunchAgents/com.local.logi-session-guard.plist
# then reload (see below)
```

| Key | Default | Meaning |
|---|---|---|
| `LOGI_GUARD_POLL` | `1` | seconds between console-user checks |
| `LOGI_GUARD_ETA` | `15` | seconds from pairing until buttons respond — tune to your hardware |
| `LOGI_GUARD_NOTIFY` | `0` | `1` also posts a notification on handoff |
| `LOGI_GUARD_LABEL` | auto | Logitech's agent label, detected at install |
| `LOGI_GUARD_PLIST` | auto | Logitech's LaunchAgent path, detected at install |

## Operations

```bash
# health check, in whichever account you're in
launchctl print "gui/$(id -u)/com.local.logi-session-guard" | grep -E "state|pid"
tail -20 ~/Library/Logs/logi-session-guard.log

# who holds the mouse right now (should be exactly one uid)
ps -axo uid,user,comm | grep logioptionsplus_agent | grep -v updater

# what the menu bar is showing
cat ~/Library/Caches/logi-guard/state

# reload after changing a setting
for uid in $(ps -axo uid,command | awk '/loginwindow console/ {print $1}' | sort -u); do
  [ "$uid" -ge 500 ] || continue
  sudo launchctl bootout "gui/${uid}/com.local.logi-session-guard" 2>/dev/null
  sudo launchctl bootstrap "gui/${uid}" \
    /Library/LaunchAgents/com.local.logi-session-guard.plist
done
```

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes everything, restores Logitech's agent in every session, and deletes per-account
logs and state. Options+ itself is untouched.

## Known issues

**Transient overlap at switch.** Both sessions may briefly hold a device manager for 2–3
seconds while one releases and the other claims. It self-corrects and has never produced
a visible fault in testing, but it is a real race in the poll window. If it ever causes a
hiccup, add a short sleep at the top of `claim_device` so the outgoing session releases
first — at the cost of that delay on every handoff.

**The ETA is hardware-specific.** The 15-second default was measured on one machine with
one mouse. More devices means longer enumeration. Watch the log and adjust
`LOGI_GUARD_ETA` to match.

**It depends on Logitech internals.** The agent label, the LaunchAgent path, and
`devio_cache/paired.xml` as a readiness signal are not public API. An Options+ update
could change any of them. The installer detects the label and path rather than hardcoding
them, but the readiness signal has no such fallback — if handoffs start reporting
"unconfirmed", that's the first thing to check.

## How it runs by itself

`launchd` does the work — the same mechanism Logitech uses, which is why it's present
wherever their agent is:

- `RunAtLoad` starts it when a session begins
- `KeepAlive` restarts it if it ever dies
- `LimitLoadToSessionType: Aqua` limits it to GUI sessions
- Living in `/Library/LaunchAgents` means **every** account gets it, including future ones

`ProcessType: Interactive` matters too. With `Background`, launchd CPU-throttles the job
and detection lag grows to 10+ seconds in a switched-away session.

## Design notes

**Readiness is detected by watching `devio_cache/paired.xml`**, which Options+ rewrites
when it genuinely enumerates and pairs a device. An earlier version waited for the agent
*process* to exist and reported "ready" in 1 second when reality was closer to 25 — the
process spawns almost instantly and does its device work afterwards. If you instrument
someone else's software, check that the signal you can observe is the event you care
about.

**The UI is decoupled from the arbitration.** The guard writes a small state file; the
menu-bar helper polls it. Neither knows how the other works, so the helper can crash
without affecting your mouse, and you can replace it with anything that reads:

```
state=ready|settling|inactive|error
owner=<user currently holding the mouse>
deadline=<unix epoch; flip amber→green when it passes>
```

## Generalizing

Nothing here is really about Logitech. The pattern applies to **any system-wide
LaunchAgent that can only have one owner**: poll `/dev/console`, `bootout` when you're not
the console user, `kickstart -k` when you become it, and ship it as a system-wide agent so
new accounts are covered automatically. Logitech's own webcam software has the same
double-run problem.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports need at least two accounts and a
switch cycle to be reproducible — the template there lists what to include.

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Logitech. "Logi Options+" is their trademark.
