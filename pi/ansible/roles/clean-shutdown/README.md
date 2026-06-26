# roles/clean-shutdown

Make a **clean Mac OS shutdown the default on every power path**, so
`System.dsk` keeps the HFS "volume unmounted cleanly" flag and the next boot
never shows *"Mac OS was not shut down properly."*

See issue #18.

## The problem

Any path that tears the system down without first letting the BasiliskII
guest run its own shutdown leaves the disk image dirty:

- `sudo reboot` / `sudo poweroff` over SSH
- the Argon ONE V3 power button (its daemon runs `reboot` / `shutdown now -h`)
- a hard power-cycle for operator recovery

Sending `SIGTERM` to BasiliskII is **not** enough on its own: it makes Mac OS
render its *"Are you sure you want to shut down?"* dialog **inside the
emulator window** and then waits for a human to click **Shut Down**. Verified
on chimebox-bryan (2026-06-26): with the Mac running, `drAtrb` (HFS volume
attributes, byte offset 1034) reads `0000`; after a confirmed clean shutdown
it flips to `0100` (the clean-unmount bit). An unattended hook that only
SIGTERMs would just time out with nobody to click → still dirty.

## The mechanism

`/usr/local/sbin/chimebox-stop-mac`:

1. Arms the supervisor `/run/chimebox-bedtime` sentinel (so the kiosk loop in
   `start.sh` won't respawn the Mac during teardown).
2. `SIGTERM`s BasiliskII → Mac OS shows its shutdown dialog.
3. **Auto-confirms** it by synthesizing the dialog's default button (Return)
   into the focused BasiliskII window via `xdotool`'s XTEST path. (XTEST
   injects at the X server input layer; SDL2/BasiliskII receives a real
   keystroke. A synthetic `XSendEvent` would be ignored.)
4. Polls for BasiliskII to exit (Mac OS flushes + unmounts → clean `drAtrb`).

It is **idempotent** (no BasiliskII → logged no-op) and logs every step via
`logger -t chimebox-stop-mac`.

## The layers

| Layer | Covers | Reliability |
|---|---|---|
| `/usr/local/sbin/{reboot,poweroff,shutdown,halt}` wrappers | Argon button, `sudo reboot`, bare commands | **Reliable** — run while X is alive (verified) |
| `chimebox-clean-shutdown.service` (systemd `ExecStop`) | `systemctl poweroff/reboot`, other absolute-path callers | **Best-effort safety net** — usually loses the race (see below) |

`/usr/local/sbin` is first on `PATH` (including the Argon daemon's PATH and
sudo's `secure_path`), so the wrappers shadow the real commands for
PATH-based callers, run `chimebox-stop-mac` first, then `exec` the real
systemd binary. Friendly aliases `chimebox-reboot` / `chimebox-poweroff` are
installed too.

### Why the systemd unit is only a safety net

Verified on chimebox-bryan (2026-06-26): for `systemctl reboot` /
`systemctl poweroff` (which bypass the PATH wrappers), the unit's `ExecStop`
runs **too late** — `systemd-logind` tears down the kiosk's session scope
(X + BasiliskII) very early in the shutdown, so by the time `ExecStop` runs
BasiliskII is already gone and `chimebox-stop-mac` logs a no-op (the disk was
torn down dirty). Reordering (`After=getty@tty1.service`, `After=user.slice`)
does not change this on a getty-autologin kiosk.

So the unit is kept only as a **harmless best-effort net + shutdown
breadcrumb**: it cleanly stops the Mac in any path where BasiliskII happens
to still be alive when it runs, and no-ops otherwise.

**Operator guidance:** use `reboot` / `poweroff` / `shutdown` (or the
`chimebox-reboot` / `chimebox-poweroff` aliases), **not** `systemctl reboot`
/ `systemctl poweroff` — the former are reliably clean. Truly closing the
`systemctl` gap would require the kiosk to run as a systemd service with
`ExecStopPre` cleanup (a larger change; tracked in #18).

## Key variables

| Variable | Default | Meaning |
|---|---|---|
| `chimebox_clean_shutdown_enabled` | `true` | Master switch |
| `chimebox_clean_shutdown_install_wrappers` | `true` | Install the `/usr/local/sbin` command shadows |
| `chimebox_clean_shutdown_systemd_hook` | `true` | Install the best-effort `ExecStop` unit |
| `chimebox_clean_shutdown_timeout_seconds` | `30` | Max wait for BasiliskII to exit |
| `chimebox_clean_shutdown_return_attempts` | `5` | Dialog-confirm Return tries (while B2 alive) |

## Not covered

Yanking the power cord. Nothing in software can make an instantaneous power
loss clean; HFS self-repairs on the next boot. The factory baseline and
rotating snapshots are the safety net for that case.
