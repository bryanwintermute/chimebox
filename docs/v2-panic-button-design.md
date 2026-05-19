# Discovery: recovery keystroke fails when Mac OS has a focused input

**Date discovered:** 2026-05-06 (the Kid Pix Type 10 retest)
**Status:** Partial fix shipped (`SDL_GRAB_KEYBOARD=0`); full fix
deferred to evdev-based architecture.

This doc captures what we learned investigating why
`Ctrl+Alt+Shift+R` (the recovery keystroke) sometimes does and
sometimes doesn't fire from the keyboard at the kiosk.

## Symptom

User reproduced a Mac OS system error (Kid Pix 2 Type 10 trap)
to test the panic button. The keystroke didn't fire.

After deploying `SDL_GRAB_KEYBOARD=0`:

- Pressed at the **Mac OS Desktop** with no window focused
  → fires correctly, Mac restarts in ~1.5s.
- Pressed with a **Finder window focused** → does NOT fire;
  instead Mac OS interprets the combo (selects window contents,
  or whatever its key-mapped behavior is for that combo).

## Diagnosis arc

### Initial guess (wrong-ish)

First hypothesis: SDL2 in fullscreen mode calls `XGrabKeyboard`,
an exclusive global grab that preempts xbindkeys' `XGrabKey`
passive grab.

Fix attempted: set `SDL_GRAB_KEYBOARD=0` and
`SDL_HINT_KEYBOARD_GRAB=0` in start.sh before BasiliskII launches.

Result: helped some cases (Desktop-focused) but not all
(window-focused). Diagnosis was incomplete.

### Refined diagnosis (correct)

The kiosk also sets `SDL_VIDEO_X11_XINPUT2=1` (which we
deliberately enabled for PiKVM mouse compatibility — see the
sdl2-x11-remote-pointer-unclutter.md lesson). XInput2 lets SDL2
read **raw keyboard events** via `XISelectEvents` on the device
hierarchy.

**Raw events bypass classic X event delivery — including
classic `XGrabKey` passive grabs.** xbindkeys uses the classic
path; SDL2 with XInput2 reads the input ahead of it.

The Desktop-vs-Finder behavior is consistent with this: when Mac
OS has no input-consuming target, BasiliskII / SDL2 still
processes the key but doesn't act on it; the *unhandled* key
falls through to classic event delivery, where xbindkeys can
catch it. When Mac OS does have an active input target, the key
is consumed in-emulator before xbindkeys sees anything.

We can't disable XInput2 because we need it for PiKVM cursor
behavior. So the env-variable workaround can't fully fix this.

## The architectural lesson

xbindkeys is the wrong primitive for a kiosk panic button. It
sits at the X classic-event layer, **above** SDL's XInput2 raw
reads. Any time the focused fullscreen app aggressively consumes
input (which is exactly what BasiliskII does), xbindkeys becomes
unreliable.

The right primitive is **the kernel input layer** —
`/dev/input/event*` — which sits **below** X entirely. Events
flow:

```
keyboard hardware
    ↓
kernel evdev layer (/dev/input/event*)        ← the right place to listen
    ↓
X server input core
    ↓
XInput2 raw events / classic key events       ← xbindkeys lives here
    ↓
SDL2 / focused window
```

A panic button at the evdev layer:

- Bypasses every X-layer grab (classic, XInput2, SDL, WM).
- Survives X server hangs (a real failure mode for a kiosk
  that's been up for weeks).
- Doesn't care which window is focused.
- Doesn't care if the kiosk is running at all.

That's what a "panic button" should mean. xbindkeys is a "polite
hotkey daemon," not a panic button.

## Implementation plan (next session)

Replace `roles/recovery-keystroke` (xbindkeys-based) with a new
role `roles/panic-button` that uses an evdev daemon:

1. **Apt install `python3-evdev`** (already in Bookworm/Trixie).
2. **Add `chimebox` user to the `input` group** — gives read
   access to `/dev/input/event*` without needing root.
   (Alternative: run the daemon as a dedicated `chimebox-panic`
   system user. Probably cleaner.)
3. **Write `chimebox-panic-daemon.py`** — short Python script:
   - Open all `/dev/input/event*` keyboard-class devices
     (use `evdev.list_devices()` + capability filtering).
   - Watch for the configured key combo (default
     Ctrl+Alt+Shift+R; configurable via systemd EnvironmentFile).
   - On match: invoke `/usr/local/sbin/chimebox-force-reset`
     (which already exists and works).
   - Log every fire via `syslog`/`logger` for the audit trail.
4. **Install systemd unit** `chimebox-panic-daemon.service`:
   - `After=multi-user.target`, not tied to X session.
   - `Restart=always`, restart-on-failure.
   - Runs as a system service, not the kiosk user.
5. **Deprecate `roles/recovery-keystroke`** — keep its
   `chimebox-force-reset` helper (the daemon uses it), remove
   the xbindkeys piece.

Estimated effort: ~1 hour for the role; ~15 min for testing.

## Defense-in-depth bonus

Once we have the evdev daemon, we can give it more useful
behaviors that xbindkeys couldn't do:

- **Multi-key combos with timing** ("hold Ctrl+Alt+Shift+R for
  3 seconds before firing"). Reduces false-positive risk.
- **Mode awareness** ("only fire if BasiliskII is at >90% CPU
  for the last 30s") — overlaps with the auto-detect-wedged-Mac
  todo and could be the same daemon.
- **A physical GPIO-button equivalent** if we ever wire one up —
  same daemon process can handle both.

These are post-MVP enhancements; the v1 daemon should just do
"detect combo, run force-reset," nothing more.

## What to keep from the xbindkeys attempt

Useful artifacts that survive the architecture switch:

- `/usr/local/sbin/chimebox-force-reset` — does the actual work;
  the new daemon will invoke it.
- `/usr/local/sbin/chimebox-emergency-stop` — same; can be
  invoked by a second key combo on the daemon.
- The audit logging convention (`logger -t chimebox-...`).
- The configuration variables (combo, master switch).

What goes away:

- `xbindkeys` package install.
- `~chimebox/.xbindkeysrc`.
- The xbindkeys hook in `start.sh`.
- The sudoers rule (the daemon runs with appropriate
  privileges already; sudo not needed).

## See also

- `roles/recovery-keystroke/` — the xbindkeys-based first attempt.
- `sdl2-x11-remote-pointer-unclutter.md` (myconfigs lessons) —
  why we set `SDL_VIDEO_X11_XINPUT2=1` in the first place.
- The "auto-detect wedged Mac" idea in `roles/panic-button/README.md`'s
  Future enhancements — natural sibling to this daemon; same
  input-monitoring infrastructure.
