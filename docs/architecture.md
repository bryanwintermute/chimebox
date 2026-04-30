# Architecture

This document describes how the pieces of chimebox fit together at a high
level. Detail-level implementation lives in code and per-component READMEs.

## Goals

1. **Single-purpose appliance**: the device boots straight into a retro OS
   and never exposes its host (Linux) to the end user.
2. **Offline-first**: no internet dependency at runtime. The device may
   briefly connect during administrator maintenance windows.
3. **Recoverable**: power yanks, accidental file deletions, and general kid
   chaos are all expected and gracefully handled.
4. **Observable from outside**: the responsible adult administers the device
   over SSH, never by sitting down in front of it.
5. **Reproducible**: any contributor can stand up a chimebox from scratch
   following documented steps.

## High-level layout

```
┌─────────────────────────────────────────────────────────────────────┐
│ Workstation (e.g. an Apple Silicon Mac)                             │
│                                                                     │
│  disk-prep/  ─────►  ROMs (user-supplied)                           │
│                  ─►  Curated System.dsk (writable, kid's profile)   │
│                  ─►  InfiniteHD.dsk     (read-only, software lib)   │
│                                                                     │
│  scripts/push-disks.sh  ────────► (rsync over SSH) ──────►          │
└─────────────────────────────────────────────────────────────────────┘
                                                            │
                                                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Raspberry Pi (chimebox device)                                      │
│                                                                     │
│  /home/pi/chimebox/                                                 │
│    ├── Quadra-650.rom         (user-supplied, never in git)         │
│    ├── System.dsk             (writable, snapshotted nightly)       │
│    ├── InfiniteHD.dsk         (read-only)                           │
│    └── snapshots/             (rolling daily + weekly)              │
│                                                                     │
│  systemd: chimebox.service                                          │
│    └── X (rootless, single-app)                                     │
│        └── BasiliskII -fullscreen ...                               │
│                                                                     │
│  SSH on management interface (Ethernet / VLAN)                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

### `disk-prep/` (workstation-side)

Runs on a separate workstation, not on the Pi. Produces the disk images
the Pi will boot from. v1 is macOS-native because it leans on the Infinite
Mac project's `import-disks` pipeline, which itself drives native Mini vMac
and Basilisk II to rebuild the desktop database on the produced disks.

Outputs (none committed to this repo):

- `disks/Quadra-650.rom` — user-supplied (see `disks/README.md`)
- `disks/System.dsk` — Mac OS 8.1 boot disk, customized with kid-friendly
  defaults
- `disks/InfiniteHD.dsk` — large library disk, populated from Macintosh
  Garden manifests

### `pi/ansible/` (provisioning)

Idempotent Ansible playbook. Run from the workstation, targets the Pi over
SSH. Roles:

- `base` — apt updates, hostname, timezone, sshd hardening
- `kiosk-user` — creates the unprivileged user that the kiosk runs as
- `basiliskii` — installs Basilisk II (apt or build-from-source)
- `kiosk-x` — minimal X server, no DE, no window manager
- `chimebox` — installs chimebox runtime files: `start.sh`, ROM, disks,
  systemd unit
- `persistence` — snapshot cron and reset scripts
- `lockdown` — disables screen blanking, host cursor, USB autoboot, etc.

### `scripts/` (operational)

Run from the workstation over SSH for day-2 ops:

- `push-disks.sh` — rsync prepared disks → Pi
- `snapshot-now.sh` — trigger a manual snapshot of `System.dsk`
- `kid-reset.sh` — restore `System.dsk` from a chosen snapshot
- `service-mode.sh` — stop the kiosk for maintenance, restart it after

### Runtime on the Pi

- `getty@tty1` autologins the kiosk user.
- The user's shell profile execs `startx` only on `tty1`.
- `~/.xinitrc` disables screen blanking, hides the host cursor, and execs
  Basilisk II in fullscreen.
- `chimebox.service` (systemd, `Restart=always`) supervises the kiosk
  session. If anything dies, it comes back.

## Design choices and tradeoffs

### Why Basilisk II + Quadra 650 ROM?

- Best-supported native aarch64 emulator in the classic Mac space.
- Color, large screens, modern audio.
- Quadra 650 ROM is the reference target for Mac OS 7.5–8.1 in this
  community.
- Mature, well-debugged.

Cost: it's an emulator, not the real thing. We accept this — the
nostalgia and educational value are intact, the fragility and expense of
real hardware are not.

### Why native, not the Infinite Mac browser app?

- A Pi 5 in a browser running WebAssembly is workable but not snappy, and
  the browser footprint adds attack surface and maintenance burden.
- Infinite Mac fetches disk chunks from Cloudflare R2 lazily, so it isn't
  truly offline even after first load.
- Native Basilisk II is fast, fully offline, and minimal.

We still owe Infinite Mac significant credit: the curated library, the
machine/ROM/disk catalog, and the `import-disks` pipeline come from there.

### Why full Finder, not At Ease?

The point is to expose how a real computer works: file system, menus,
icons. At Ease was Apple's actual kid-shell from this era and may appear
later as an opt-in role, but the default experience is the real Finder.

### Why writable System.dsk + read-only InfiniteHD.dsk?

- The kid's data (drawings, saved games, preferences) lives on
  `System.dsk`. Snapshotting protects against accidents.
- The library is read-only — it can't be corrupted by misclicks or power
  yanks, and it doesn't need to be backed up.

## Non-goals (for now)

- Multi-user / multi-profile support.
- Multiple OS images at boot time.
- AppleTalk between two chimeboxes.
- Internet access of any kind from the kiosk session.
- A graphical admin UI. Admin is SSH and shell scripts.

These may move into scope later. See the parking lot in
[`docs/era-decisions.md`](./era-decisions.md).
