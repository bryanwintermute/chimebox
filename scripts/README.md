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

All four scripts:

- Read shared config from `config.sh` (or `config.example.sh` defaults).
- Connect to the Pi as the admin user (`bryan` by default).
- Use `sudo` on the Pi for privileged operations -- you'll be prompted
  for the admin user's sudo password.
- Fail loudly with helpful messages if something is off.

## Common usage

```sh
# After disk-prep finishes:
./push-disks.sh

# Before letting the kid try a fresh app for the first time:
./snapshot-now.sh

# Oh no, she deleted the System Folder somehow:
./kid-reset.sh             # interactive: lists snapshots, asks which one

# You want to apt-update or fix something on the Pi:
./service-mode.sh          # opens a shell on the Pi with the kiosk paused
                           # exit the shell -> kiosk resumes
```

## Why scripts AND Ansible?

- **Ansible** handles configuration that should be the same on every
  chimebox: packages installed, users created, systemd units in place.
- **scripts/** handles ongoing per-device operations: pushing disks,
  taking snapshots, restoring, maintenance windows. None of that is
  configuration; it's just SSH-and-do-a-thing.

Could you do all of this with Ansible playbooks too? Yes. But for ad-hoc
operational tasks, plain shell over SSH is simpler, faster, and easier
to read in a hurry.
