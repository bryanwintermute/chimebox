# scripts/

Workstation-side scripts for managing a chimebox after it's been
provisioned. Run from your workstation; they SSH into the Pi.

## Setup (one-time)

```sh
cd scripts
cp config.example.sh config.sh
# Edit config.sh -- set CHIMEBOX_SSH_HOST etc. for your Pi.
chmod +x config.sh
```

`config.sh` is gitignored. It encodes only your local environment.

## The scripts

| Script | Purpose | Frequency |
|---|---|---|
| `push-disks.sh` | Rsync prepared disks (`../disks/`) to the Pi | Once after disk-prep, or any time disks change |
| `snapshot-now.sh` | Trigger a manual snapshot of `System.dsk` | Before risky changes; ad hoc |
| `kid-reset.sh` | Restore `System.dsk` from a chosen snapshot | When something goes wrong on the Pi side |
| `service-mode.sh` | Stop the kiosk for maintenance, give you a shell, restart on exit | Whenever you need to poke at the Pi while it's running |
| `mouse-mode.sh` | Toggle BasiliskII between relative-mouse (kiosk default) and absolute mode (PiKVM/VNC/tablet) | When switching between physical and remote input setups |
| `bedtime.sh` | Politely ask the Mac to shut down (`SIGTERM` triggers the Mac OS shutdown dialog), wait N minutes, then stop the kiosk | End of day |
| `wake-up.sh` | Restart the kiosk after `bedtime.sh` (inverse: starts getty, autologin chain takes over) | Start of day |

All scripts:

- Read shared config from `config.sh` (or `config.example.sh` defaults).
- Connect to the Pi as the admin user (`admin` by default).
- Use `sudo` on the Pi for privileged operations -- you'll be prompted
  for the admin user's sudo password.
- Fail loudly with helpful messages if something is off.

## Common usage

```sh
# After disk-prep finishes:
./push-disks.sh

# Before letting the kid try a fresh app for the first time:
./snapshot-now.sh

# Oh no, the kid deleted the System Folder somehow:
./kid-reset.sh             # interactive: lists snapshots, asks which one

# You want to apt-update or fix something on the Pi:
./service-mode.sh          # opens a shell on the Pi with the kiosk paused
                           # exit the shell -> kiosk resumes

# End of day, with a 5-minute wrap-up warning:
./bedtime.sh               # default 5-minute SIGTERM warning, then stops kiosk
./bedtime.sh 10            # 10-minute warning instead
./bedtime.sh 0             # immediate (still graceful via Mac OS dialog)

# Start of day:
./wake-up.sh
```

## Recovery triggers — three paths

There are three distinct ways to recover from a chimebox in
trouble, each suited to a different situation. They overlap in
some cases on purpose.

### 1. Workstation SSH (`scripts/kid-reset.sh`) — adult, has a laptop nearby

The classic path documented above: run `./kid-reset.sh latest`
(or interactive) from your workstation. Stops the kiosk, restores
`System.dsk` from the chosen snapshot, restarts the kiosk. Works
for both "kid damaged the disk" and "kid did something benign that
the adult wants to undo." ~30 seconds end-to-end.

### 2. Kiosk keyboard hotkey (panic-button daemon) — adult shoulder-surfing the kid

The `panic-button` Ansible role installs a kernel-input-layer
daemon that catches specific key combinations regardless of which
window has focus or whether X is responsive. Three combos are
supported, each off-or-on independently:

| Combo | Action | When to use |
|---|---|---|
| `Ctrl+Alt+Shift+R` | Force-reset the emulator (SIGKILL BasiliskII; supervisor respawns) | Mac OS is wedged in a system-error trap loop; doesn't touch `System.dsk` |
| `Ctrl+Alt+Shift+Q` (opt-in) | Full kiosk teardown (equivalent to `bedtime.sh 0`) | "I really want it OFF now" |
| `Ctrl+Alt+Shift+Z` (opt-in, hold 1.5s) | **Restore `System.dsk` from the latest snapshot.** Same effect as `kid-reset.sh latest`, just from the kiosk keyboard | Adult notices the kid is about to do something irreversible; wants to roll back without grabbing a laptop |

The hold-time gate on the destructive combo (`Z`) is the safety
mechanism — a kid mashing random key combinations can't stumble
into a rollback.

Enable the opt-in combos in your host_vars (see
[`pi/ansible/roles/panic-button/README.md`](../pi/ansible/roles/panic-button/README.md)
for full details).

### 3. Auto-detection (planned, not yet implemented)

A future enhancement to the panic-button daemon: detect a wedged
Mac (BasiliskII at >90% CPU + no input received + screen
unchanged for N seconds) and auto-fire the force-reset action.
Tracked as `detect-wedged-mac` in the backlog. **Note this is
distinct from kid-reset:** auto-detection handles the
"emulator wedged" case, not the "kid damaged the disk" case.
Disk damage requires explicit human judgment to invoke
(an auto-rollback could lose work the kid wanted to keep).

## Why scripts AND Ansible?

- **Ansible** handles configuration that should be the same on every
  chimebox: packages installed, users created, systemd units in place.
- **scripts/** handles ongoing per-device operations: pushing disks,
  taking snapshots, restoring, maintenance windows. None of that is
  configuration; it's just SSH-and-do-a-thing.

Could you do all of this with Ansible playbooks too? Yes. But for ad-hoc
operational tasks, plain shell over SSH is simpler, faster, and easier
to read in a hurry.
