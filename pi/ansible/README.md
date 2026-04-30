# pi/ansible

Ansible playbook that provisions a Raspberry Pi as a chimebox. Run from
your workstation, targets the Pi over SSH.

## Prerequisites

- Pi already set up per [`../SETUP.md`](../SETUP.md) (OS flashed, SSH
  working, on the network).
- Ansible installed on your workstation:
  ```sh
  brew install ansible        # macOS
  pipx install ansible        # any platform
  ```

## Quickstart

```sh
cd pi/ansible
cp inventory.example.ini inventory.ini
# Edit inventory.ini -- set ansible_host to your Pi's hostname or IP.

# Sanity-check connectivity:
ansible -i inventory.ini chimebox -m ping

# Run the playbook:
ansible-playbook -i inventory.ini playbook.yml
```

The playbook is idempotent — re-running on an already-provisioned Pi is
safe and a quick no-op.

## What it does

The playbook orchestrates these roles in order:

| Role | Purpose |
|---|---|
| `base` | apt update/upgrade, set timezone, ensure aarch64 + Bookworm |
| `kiosk-user` | Create the unprivileged `chimebox` user that runs the kiosk |
| `basiliskii` | Install Basilisk II (apt or build-from-source fallback) |
| `kiosk-x` | Install minimal X server, no desktop environment |
| `chimebox` | Install runtime files: start.sh, .xinitrc, systemd unit |
| `persistence` | Install snapshot cron, reset/service-mode helpers |
| `lockdown` | Disable screen blanking, host cursor, USB autoboot, etc. |

Each role is documented in `roles/<name>/README.md`.

## Configuration

All tunables live in `group_vars/all.yml`. Most users won't need to edit
them. Key ones:

| Variable | Default | What it controls |
|---|---|---|
| `chimebox_user` | `chimebox` | Unprivileged user that owns the kiosk session |
| `chimebox_home` | `/home/{{ chimebox_user }}` | That user's home dir |
| `chimebox_runtime_dir` | `{{ chimebox_home }}/chimebox` | Where ROM and disks live |
| `chimebox_screen_width` | `1024` | Emulator screen width |
| `chimebox_screen_height` | `768` | Emulator screen height |
| `chimebox_ram_mb` | `128` | RAM allocated to the emulated Mac |
| `chimebox_rom_filename` | `Quadra-650.rom` | ROM filename in runtime dir |
| `chimebox_modelid` | `14` | Basilisk II model id (14 = Quadra 650) |
| `chimebox_cpu` | `4` | Basilisk II CPU id (4 = 68040) |
| `chimebox_snapshot_keep_daily` | `7` | Daily System.dsk snapshots to retain |
| `chimebox_snapshot_keep_weekly` | `4` | Weekly snapshots to retain |

Override any of these by editing `group_vars/all.yml` or by passing
`-e var=value` on the `ansible-playbook` command line.

## Running just one role

For development:
```sh
ansible-playbook -i inventory.ini playbook.yml --tags kiosk-x
ansible-playbook -i inventory.ini playbook.yml --tags chimebox,persistence
```

Or skip a role:
```sh
ansible-playbook -i inventory.ini playbook.yml --skip-tags lockdown
```

## After provisioning

The playbook installs everything *except* the actual disk images and ROM
— those are large, user-supplied, and would slow every Ansible run. Push
them separately:

```sh
cd ../../scripts          # repo's scripts/ dir
./push-disks.sh           # rsyncs ../disks/ to the Pi
```

Then reboot the Pi, and you should land in the chimebox kiosk.

## Why Ansible, not a shell script?

- **Idempotency**: re-running is a quick no-op rather than re-doing work.
- **Drift detection**: Ansible reports what changed on the Pi between
  runs.
- **Structure**: roles map cleanly to concerns (user, X, emulator,
  persistence, etc.) so contributors can find and modify one piece
  without reading the whole.
- **Multi-host ready**: when (if) you provision a second chimebox, the
  same playbook works against multiple targets in parallel.
