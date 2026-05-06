# role: recovery-keystroke

Binds a deliberately-obscure keystroke combo inside the kiosk X
session. When pressed, the magic combo force-resets the emulated
Mac without needing SSH access. The supervisor loop in start.sh
catches BasiliskII's exit and respawns it within ~1.5 seconds, so
the user sees a brief black screen and then a fresh Mac OS boot.

This is the manual "panic button" for the situation where a Mac
OS app crashes the entire OS into a system-error trap loop
(e.g., a Type 10 memory error from a buggy era game) and the
classic "press Restart" button on the dialog is also unresponsive.

## What it builds

| Component | Purpose |
|---|---|
| `xbindkeys` package | Listens for the magic key combo inside X |
| `~chimebox/.xbindkeysrc` | Configuration: which combo fires which command |
| `/usr/local/sbin/chimebox-force-reset` | SIGKILLs BasiliskII; supervisor respawns it |
| `/usr/local/sbin/chimebox-emergency-stop` | (optional) full kiosk teardown via bedtime sentinel |
| `/etc/sudoers.d/chimebox-recovery` | Tightly-scoped passwordless sudo for the helpers |
| Hook in `start.sh` | Starts xbindkeys at session launch |

## Default keystroke

`Ctrl+Alt+Shift+R` — chosen because:

- A 4-modifier combo is essentially impossible to hit by accident
- 'R for Reset' matches Mac's classic `Cmd+Ctrl+Power = restart`
  convention
- None of the Tier-S kid apps from `docs/shortlist.md` use it

If you want to change it, set `chimebox_recovery_keystroke` in
`host_vars/<host>.yml`. Format follows xbindkeys conventions:
`Modifier+Modifier+Key`. Run `xbindkeys -k` on the Pi (in an X
session) to interactively probe a combo and get its exact name.

## Optional: emergency-stop combo

A second combo can be bound to fully tear down the kiosk
(equivalent to `scripts/bedtime.sh 0` from a workstation). Off
by default; enable in host_vars:

```yaml
chimebox_recovery_emergency_stop_enabled: true
chimebox_recovery_emergency_stop_keystroke: "Control+Alt+Shift+q"
```

After the kiosk is stopped this way, run `scripts/wake-up.sh`
from a workstation to bring it back.

## Audit log

Both helpers log every invocation via `logger -t chimebox-...`.
Check with:

```sh
journalctl -t chimebox-force-reset
journalctl -t chimebox-emergency-stop
```

Useful when debugging "why did the Mac just restart?" later or
when your kid swears they didn't press the magic combo.

## Why xbindkeys (not xdotool / direct Xlib / a custom daemon)?

- `xbindkeys`: small, packaged in Debian, well-tested, single
  binary. The `~/.xbindkeysrc` config format is dead-simple.
- `xdotool`: more general but solves the wrong problem — it's
  for synthesizing input, not catching it.
- Custom Xlib script: overkill for one keystroke binding.

## Future enhancement: auto-detection

A future role (tracked as `detect-wedged-mac` in the backlog)
will add a small daemon that watches three conditions in concert:

- BasiliskII CPU sustained at 100% for >N seconds
- No keyboard/mouse input received for >N seconds
- Optional: pixel hash of screen unchanged

If all three are true, the daemon fires the same
`chimebox-force-reset` helper this role installs. The keystroke
will remain as the manual override.

## Why an opt-out master switch (default ON)?

The role is inert when nothing's wrong: xbindkeys runs as a
background process consuming a few MB, no visible effect. The
sudoers entry is tightly scoped (only the two specific helper
scripts, only as root, no argument options). The cost is minimal
and the panic-button capability is high-value, so default ON is
correct.

To disable, set `chimebox_recovery_keystroke_enabled: false` in
host_vars.

## Variables

| Var | Default | Effect |
|---|---|---|
| `chimebox_recovery_keystroke_enabled` | `true` | Master switch |
| `chimebox_recovery_keystroke` | `Control+Alt+Shift+r` | The force-reset combo |
| `chimebox_recovery_emergency_stop_enabled` | `false` | Bind the second combo too |
| `chimebox_recovery_emergency_stop_keystroke` | `Control+Alt+Shift+q` | Emergency-stop combo |
