# role: panic-button

A kernel-input-layer daemon that fires recovery actions when a
configured keystroke is pressed, regardless of which app has
focus or whether X is running. Replaces the older xbindkeys-
based `recovery-keystroke` role.

## Why a kernel-level daemon (not xbindkeys)?

Real-world testing exposed that xbindkeys can be silently
preempted: SDL2 with `SDL_VIDEO_X11_XINPUT2=1` (which we use for
PiKVM mouse compatibility) reads keyboard events via XInput2
raw-mode, **which bypasses the classic `XGrabKey` passive grabs
that xbindkeys relies on**. Result: any time the focused
fullscreen app aggressively consumes input (which is exactly what
BasiliskII does), the panic keystroke could be swallowed.

This daemon listens directly to `/dev/input/event*` at the kernel
input layer — *below* X entirely:

```
keyboard hardware
    ↓
kernel evdev (/dev/input/event*)              ← we listen here
    ↓
X server input core
    ↓
XInput2 raw events / classic key events       ← xbindkeys lived here
    ↓
SDL2 / focused window
```

Benefits:

- Sees every keystroke regardless of which app has focus.
- Survives X server hangs.
- Works even before the kiosk session has started.
- Can also fire actions based on input from a future GPIO
  panic button (same code path).

See `docs/v2-panic-button-design.md` for the full diagnosis and
architectural rationale.

## What it builds

| Component | Path | Purpose |
|---|---|---|
| Daemon | `/usr/local/sbin/chimebox-panic-daemon` | Python script using `evdev`; watches all keyboards |
| Config | `/etc/chimebox-panic-daemon.conf` | INI: which combos fire which scripts |
| Systemd unit | `/etc/systemd/system/chimebox-panic-daemon.service` | Supervises the daemon; hardened |
| Force-reset action | `/usr/local/sbin/chimebox-force-reset` | SIGKILLs BasiliskII; supervisor respawns |
| Emergency-stop action | `/usr/local/sbin/chimebox-emergency-stop` | (optional) full kiosk teardown |
| Apt deps | `python3-evdev` | Python evdev bindings |

## Default keystroke

`Ctrl+Alt+Shift+R` — same as the deprecated role. 4-modifier
combo essentially impossible to hit by accident; "R for Reset"
matches Mac convention.

## Why root?

The daemon runs as root because:
- `/dev/input/event*` reads need either root or membership in the
  `input` group; root is simpler than a dedicated user with a
  custom group setup.
- The action scripts need to SIGKILL BasiliskII (which runs as
  the chimebox kiosk user). Cross-UID kill needs root.

The systemd unit hardens this with `NoNewPrivileges=true`,
`ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`,
and a tight `CapabilityBoundingSet=CAP_KILL`. The daemon can
read input + send signals; nothing else.

## Optional: emergency-stop combo

A second combo can be wired to fully tear down the kiosk
(equivalent to `scripts/bedtime.sh 0`). Off by default; enable
in host_vars:

```yaml
chimebox_panic_button_emergency_stop_enabled: true
chimebox_panic_button_emergency_stop_modifiers: [ctrl, alt, shift]
chimebox_panic_button_emergency_stop_trigger: q
```

After that combo is pressed, the kiosk fully shuts down. Use
`scripts/wake-up.sh` from a workstation to start it again.

## Optional: kid-reset combo (destructive!)

A third combo can be wired to **restore `System.dsk` from the
most recent snapshot** — the kernel-input-layer equivalent of
`scripts/kid-reset.sh latest` from a workstation. Use case: an
adult shoulder-surfing the kid notices the Mac is in a state
where the kid's drawings are at risk, and wants an "undo to last
snapshot" button without fishing out an SSH terminal.

This combo is **destructive**: any state in the running Mac
since the latest snapshot is overwritten. The default trigger is
Ctrl+Alt+Shift+Z ("Z for Undo", matching Mac convention) with a
**1.5-second hold-time gate** so a kid mashing random key
combinations cannot stumble into a destructive rollback.

Off by default; enable in host_vars:

```yaml
chimebox_panic_button_kid_reset_enabled: true
# Optional overrides (defaults are sensible):
chimebox_panic_button_kid_reset_modifiers: [ctrl, alt, shift]
chimebox_panic_button_kid_reset_trigger: z
chimebox_panic_button_kid_reset_hold_seconds: 1.5
```

When the combo fires:

1. Stops the kiosk via `systemctl stop getty@tty1.service` (so
   no in-flight writes corrupt the snapshot restore).
2. Runs `chimebox-reset latest` (the same helper
   `scripts/kid-reset.sh` invokes).
3. Restarts `getty@tty1.service` so the kiosk comes back up on
   the restored disk.

Total cycle ~30 seconds, similar to running kid-reset over SSH.

If no snapshots exist (extremely rare), the helper logs a
clear message and exits cleanly without touching `System.dsk`.

## Modifier-hold gating

For combos that aren't quite as obscure as 4-modifier, the daemon
supports requiring all modifiers and the trigger key be **held
together for N seconds** before the action fires. Set:

```yaml
chimebox_panic_button_hold_seconds: 0.3
```

The user can mash all keys at once; the combo only fires after
they've been held for `hold_seconds`. This makes accidental fires
from rapid typing essentially impossible. The kid-reset combo
uses this with a 1.5s gate so a curious kid can't trigger
rollback by stumbling onto the combo.

## Audit trail

Every fired combo logs to syslog:

```sh
journalctl -t chimebox-panic
journalctl -t chimebox-force-reset
journalctl -t chimebox-emergency-stop
```

Useful for debugging "why did the Mac just restart?" or auditing
panic-button usage.

## How keyboard hot-plug is handled

Currently: the daemon enumerates keyboards at startup and
ignores hot-plug. If a USB keyboard is plugged in *after* the
daemon starts, that keyboard's keys won't fire combos.

Workaround: `sudo systemctl restart chimebox-panic-daemon` after
plugging in a new keyboard. (Or `Restart=always` plus a future
udev rule that triggers the restart on new input devices.)

For the chimebox-dev kiosk this is a non-issue (PiKVM keyboard
+ optional fixed wired keyboard are present at boot).

## Variables

| Var | Default | Effect |
|---|---|---|
| `chimebox_panic_button_enabled` | `true` | Master switch |
| `chimebox_panic_button_modifiers` | `[ctrl, alt, shift]` | Modifier groups for force-reset combo |
| `chimebox_panic_button_trigger` | `r` | Trigger key for force-reset |
| `chimebox_panic_button_hold_seconds` | `0` | Optional modifier-hold gating for the force-reset combo |
| `chimebox_panic_button_emergency_stop_enabled` | `false` | Wire the second combo |
| `chimebox_panic_button_emergency_stop_modifiers` | `[ctrl, alt, shift]` | Modifiers for emergency-stop |
| `chimebox_panic_button_emergency_stop_trigger` | `q` | Trigger for emergency-stop |
| `chimebox_panic_button_kid_reset_enabled` | `false` | Wire the destructive kid-reset combo |
| `chimebox_panic_button_kid_reset_modifiers` | `[ctrl, alt, shift]` | Modifiers for kid-reset |
| `chimebox_panic_button_kid_reset_trigger` | `z` | Trigger for kid-reset |
| `chimebox_panic_button_kid_reset_hold_seconds` | `1.5` | Hold-time gate (seconds) for kid-reset |

## Future enhancements

- **Auto-detect wedged Mac**: same daemon could grow to host
  CPU/input/screen-change monitoring. When BasiliskII has been
  at >90% CPU AND there's been no keystroke or pointer event AND
  the screen hasn't changed for N seconds, fire force-reset
  automatically. Tracked separately as `detect-wedged-mac`.
- **GPIO panic button**: `evdev` can also read GPIO-mapped input
  devices. A physical button wired to the Pi could fire the
  same actions, accessible to a kid who doesn't know the
  keystroke combo.
- **Hot-plug support via udev**: monitor for new input devices
  and dynamically open them.

## See also

- `docs/v2-panic-button-design.md` — architectural rationale.
- `pi/ansible/roles/recovery-keystroke/` — the deprecated
  predecessor (still referenced for diff comparisons; this role
  removes its artifacts at install time).
