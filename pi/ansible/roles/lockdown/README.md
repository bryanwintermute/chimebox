# role: lockdown

Hardens the chimebox so a curious kid (or a determined one) can't easily
escape the emulator into the host Linux:

- Disables host screen blanking and DPMS (already done in start.sh, but
  belt-and-suspenders).
- Disables Ctrl-Alt-Fn TTY switching while X is active.
- Masks unused getty TTYs (the actual guard against accidental VT
  switching), leaving the escape-to-tty target VT unmasked only when that
  opt-in feature is enabled.
- Neutralizes **Ctrl+Alt+Del** (see below).
- Locks the chimebox user's password (already done in kiosk-user role).
- Ensures sudoers has no NOPASSWD entries pointing at the chimebox user.
- Optionally disables USB autoboot in raspi-config.

Most of these settings are belt-and-suspenders; the main containment is
that Basilisk II in fullscreen X with no window manager has no host UI to
escape to in the first place.

## Ctrl+Alt+Del

Stock systemd aliases `ctrl-alt-del.target` to `reboot.target`, so a
single Ctrl+Alt+Del reboots the Pi. That's an undocumented escape: it
dirties the disk (no polite shutdown) and, caught in the boot window
between kiosk teardown and X coming up, can expose a shell (#19). systemd
*also* force-reboots on **7 presses within 2 seconds**
(`CtrlAltDelBurstAction`), independent of the target — so masking the
target alone is not enough.

`chimebox_lockdown_ctrl_alt_del` controls both vectors:

| Value | Single press | 7×-in-2s burst | Use |
|---|---|---|---|
| `mask` (default) | no-op (target masked) | disabled (`none`) | kid-handoff units |
| `reboot` | reboots (stock) | force-reboots (stock) | dev/operator boxes |

A future `polite-shutdown` value (remap the combo to a clean Mac
shutdown instead of a no-op) is reserved pending the Pi-side
polite-shutdown primitive in #18.

The burst-action setting lives in `/etc/systemd/system.conf.d/` and is
applied live via `systemctl daemon-reexec` (a plain `daemon-reload`
doesn't re-read manager settings); it would otherwise apply on next boot.

## Other escape paths considered

`emergency.target` / `rescue.target` are reachable as systemd targets but
are gated by the **locked root password** — `sulogin` won't hand out a
shell — so they aren't an open path. The unused gettys are masked, and X
runs with `DontVTSwitch` + `DontZap` (no Ctrl+Alt+Backspace). The kiosk
user has a locked password and no sudoers entries.

