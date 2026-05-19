# chimebox

> A locked-down, internet-free, period-correct retro computing experience on a
> Raspberry Pi — designed as a young person's first real computer.

## Status

**v1 complete.** On the dev Pi 5
kiosk, chimebox boots directly into Mac OS 8.1 with a curated
kid-shortlist Desktop, respawns the emulator after guest
shutdown, auto-mounts USB sticks as Mac volumes, routes audio
to a per-host configured device at a sensible default volume,
blocks the kiosk user from reaching the public internet, and
has bedtime / panic-button / snapshot / factory-bless machinery
all installed and exercised through real-world use.

See [Status & rough edges](#status--rough-edges) below for an
honest read on what's tested vs not, and the known limitations
documented in role READMEs.

## What is chimebox?

Chimebox turns a Raspberry Pi into a single-purpose retro computer kiosk.
It boots straight into a classic operating system running in an emulator,
fullscreen, with no visible host OS. From the user's perspective, it's
just an old computer. From an administrator's perspective, it's a normal
Linux box you can SSH into to maintain.

The first supported environment is **Mac OS 8.1** running in **Basilisk
II** on a Pi 5 — chosen for its sweet spot of color graphics, a
well-known kid-friendly software catalog (Kid Pix, MacPaint, HyperCard,
Oregon Trail, Lemmings, etc.), and mature native emulation on `aarch64`.
The architecture is emulator-agnostic; future configurations (early
Windows in DOSBox, Amiga in FS-UAE, Apple II in MAME) are on the roadmap.

## Who is this for?

- **Parents / aunts / uncles** who want to give a young child a real
  first computer instead of yet another tablet, with full adult
  oversight and no internet exposure.
- **Retro computing tinkerers** who want a turnkey kiosk built on
  reproducible Ansible bones, where the Pi-and-emulator integration
  work is already done.
- **Kiosk-pattern enthusiasts** who'd like a clean, well-documented
  Ansible+systemd+X11 reference for headless single-app appliances.

If you're looking for a one-click consumer product, this isn't it (and
might never be). If you're comfortable on a Linux command line and
willing to flash a Pi from scratch, it's well within reach.

## Quickstart

**You'll need:**

- A Raspberry Pi 5 with active cooling, a microSD or NVMe drive, and a
  display + USB keyboard/mouse for first boot.
- A workstation with `ansible` installed and `git`.
- **macOS for v1 disk preparation.** Linux disk-prep is on the roadmap.
- A legally obtained **Quadra 650 ROM** placed at
  `disks/Quadra-650.rom`.
- The `third_party/infinite-mac` submodule initialized (see step 1).

**End-to-end setup has five steps; the longest two have dedicated
walkthroughs.**

1. **Clone with submodules**:
   ```sh
   git clone --recurse-submodules https://github.com/bryanwintermute/chimebox.git
   ```

2. **Pi first-boot setup** — flash Pi OS Trixie Lite, configure SSH,
   reach the Pi from your workstation. See [`pi/SETUP.md`](./pi/SETUP.md).

3. **Disk preparation** — builds/fetches `System.dsk` (Mac OS 8.1 boot
   disk) and `InfiniteHD.dsk` (curated library) on your workstation.
   The fast path uses prebuilt chunks from the infinitemac.org CDN and
   completes in ~90 seconds. You provide the ROM. See
   [`disk-prep/README.md`](./disk-prep/README.md).

4. **Provision the Pi** — from `pi/ansible/`, copy
   `inventory.example.ini` to `inventory.ini`, edit for your Pi, and
   run `ansible-playbook -i inventory.ini playbook.yml`.

5. **Push disks to the Pi** — `cd scripts && cp config.example.sh
   config.sh` (edit for your Pi), then `./push-disks.sh`. Reboot the Pi.
   It comes up as a chimebox.

Day-2 ops scripts (bedtime, snapshot, kid-reset, service-mode) live in
[`scripts/`](./scripts/). See
[`scripts/README.md`](./scripts/README.md) for the full list.

## Highlights

What makes chimebox distinct from "just run an emulator on a Pi":

- **Pi provisioning in one idempotent Ansible playbook** — so rebuilding
  a Pi is boring instead of artisanal.
- **Calm boot experience** — a custom Plymouth theme replaces the
  rainbow-firmware-splash + scrolling-kernel-text + login-flicker chain
  with a single quiet image, so the kid never sees Linux boot noise.
- **Smooth in-place restart** — when the emulated guest shuts down, X
  stays up and the supervisor respawns the emulator within ~1.5s. No
  teardown, no flicker. Crash-loop protection prevents runaway
  respawns.
- **Bedtime / wake-up cycle** — `scripts/bedtime.sh` with a
  configurable warning period sends a SIGTERM the guest receives as a
  shutdown dialog, so the kid retains agency over a graceful exit.
- **Below-X evdev panic button** — Ctrl+Alt+Shift+R force-resets the
  emulator from a small daemon that reads `/dev/input/event*` directly.
  Works even when the guest app aggressively grabs input. Audit log
  for every fire. Optional opt-in combos for kid-reset (rollback)
  and emergency-stop.
- **Snapshot + factory baseline** — nightly cron-driven rotating
  snapshots of the user disk, plus a separate operator-blessed
  factory baseline captured via clean Mac OS shutdown.
  `scripts/kid-reset.sh` restores from a chosen rotating snapshot;
  `scripts/factory-reset.sh` rolls back to the curated baseline.
- **"Outside World" host folder** — a host directory appears on the
  guest desktop as a network volume; USB sticks auto-mount as
  sub-folders on insertion, so adults can move files in/out without
  giving the guest internet.
- **Audio routing + safe default volume** — per-host ALSA card
  selection (USB DAC, HDMI, etc.) by stable card name (not index, so
  USB hot-plug doesn't shift routing); boot-time volume cap so the
  Mac chime at 100% never surprises anyone. Ships a discovery helper
  (`sudo chimebox-audio-list`) that prints copy-paste-ready host_vars
  for whatever audio hardware the operator actually has.
- **Per-user egress firewall** — guest networking is disabled in
  Basilisk II as the primary defense; an nftables `meta skuid` rule
  is the belt-and-suspenders second layer, blocking the kiosk user
  from reaching off-LAN destinations even if anything were to escape
  the emulator. Operator SSH, host updates, NTP, etc. are unaffected.

## Why?

Modern computing experiences hide everything interesting behind glossy,
locked-down app stores and walled gardens. They also come with cameras,
microphones, trackers, ads, and a one-click bridge to the entire
internet — none of which a small child should have to navigate to learn
what a computer *is*.

A retro Mac, in this configuration:

- has a real, visible file system
- ships with guest networking disabled
- has no advertising, no autoplay, no notifications
- has a curated catalog of decades-old software, much of it educational
  and delightful, all of which works offline
- breaks gracefully — there's no "this app needs an update" loop

For the design rationale and trade-offs (era choice, hardware, distro,
emulator, period-correct exception policy, when-to-revisit triggers),
see [`docs/era-decisions.md`](./docs/era-decisions.md).

## Status & rough edges

**Implemented and working on the dev kiosk:**

- Automatic boot directly into Mac OS 8.1 with a curated kid-shortlist
  Desktop (factory-blessed via clean Mac OS shutdown).
- Emulator respawn after guest shutdown.
- Below-X panic-button reset (validated under Mac OS error trap loops,
  plus opt-in kid-reset combo with 1.5s hold-time gate).
- USB Outside World mounting (validated end-to-end).
- Bedtime / wake-up script flow (validated through several real
  bedtime cycles).
- Snapshot machinery running on cron; rotating-snapshot rollback
  exercised against deliberate HFS-level damage.
- Factory bless + factory reset round-trip exercised; captured
  baseline has the HFS clean-unmount flag set.
- Audio routing + 60% boot-volume default via per-host ALSA card
  selection.
- Per-user egress firewall (nftables `meta skuid` against the kiosk
  user) verified blocking off-LAN destinations while operator
  remains fully unrestricted.
- Power-yank survival: the Pi recovers cleanly from sudden power-cycle
  (validated accidentally during testing — see
  [`docs/recovery.md`](./docs/recovery.md)).

**Still ahead before broader adoption:**

- First handoff to the real intended user.
- Documentation iteration after a non-author tries to set one up.
- Optional polish items: USB safe-eject hotkey, custom "Outside
  World" volume name + icon (requires BasiliskII source patch),
  fresh-install workflow refactor. All filed in the project's
  internal tracker; none are kid-handoff blockers.

**Known limitations (documented in role READMEs):**

- Some Mac apps (e.g., SimpleText) silently fail saves into the
  Outside World extfs volume; others (Kid Pix) work fine. Workaround:
  save to Macintosh HD first, then drag into Outside World.
- Cross-mount drag-within-Unix-volume returns EXDEV → Mac shows "disk
  error". Workaround: hold Option to force copy semantics.
- The Outside World extfs volume's name is hardcoded by BasiliskII to
  "Unix" and is not currently overridable from chimebox without
  patching BasiliskII source.
- Disk-prep's fast path (`4-fetch-cdn.sh`) works on Linux and
  macOS; the full local-build pipeline (`prep.sh`) still requires
  macOS for the GUI-emulator desktop-database rebuild. Linux
  full-pipeline support is on the roadmap.
- `chimebox.service` (systemd) is installed but disabled in v1; the
  active supervisor is the autologin → startx → start.sh chain.

## Repository layout

```
chimebox/
├── docs/                 ← Architecture, era decisions, design docs, runbooks
├── disk-prep/            ← Tools that run on a workstation to build the disk image
├── pi/
│   ├── SETUP.md          ← Pi first-boot walkthrough
│   └── ansible/          ← Provisioning playbook + roles (one role per concern)
├── scripts/              ← Operational scripts (push disks, snapshot, reset, bedtime, …)
├── third_party/
│   └── infinite-mac/     ← Submodule; init with `git submodule update --init --recursive`
├── disks/                ← .gitignored — local-only ROMs and disk images
├── LICENSE               ← Apache 2.0
├── LICENSING.md          ← Per-component licensing, including upstream projects
└── NOTICE                ← Apache 2.0 attribution to upstream projects
```

## Documentation

The `docs/` tree has the substantive thinking behind chimebox.
Different docs serve different audiences:

**If you want to build one:**

- [`pi/SETUP.md`](./pi/SETUP.md) — Pi first-boot walkthrough.
- [`disk-prep/README.md`](./disk-prep/README.md) — Building the disk
  images on your workstation.
- [`pi/ansible/README.md`](./pi/ansible/README.md) — Playbook overview
  and tunables.
- [`scripts/README.md`](./scripts/README.md) — Day-2 operational
  scripts.

**If you want to run one (day-2 ops and recovery):**

- [`docs/operations.md`](./docs/operations.md) — Day-2 runbook:
  bedtime/wake-up rhythm, snapshot management, system updates,
  inspection commands, "I want to..." workflows.
- [`docs/recovery.md`](./docs/recovery.md) — Symptom-first triage
  for failure modes (Mac wedged, black screen, kiosk crash-loop,
  audio dead, USB won't appear, SSH does not work, etc.).

**If you want the design rationale:**

- [`docs/era-decisions.md`](./docs/era-decisions.md) — *Why* of every
  major design choice (era, OS, ROM, hardware, distro, network
  posture, kid-experience principles, exception policy).
- [`docs/architecture.md`](./docs/architecture.md) — *How* the live
  system fits together.
- [`docs/architecture-patterns.md`](./docs/architecture-patterns.md) —
  Reusable design patterns abstracted from the Mac-specific
  implementation; the "if I were forking this for a different
  emulator stack" reference.
- [`docs/shortlist.md`](./docs/shortlist.md) — Tier-ranked guide to the
  Mac OS software library.
- [`docs/ROADMAP.md`](./docs/ROADMAP.md) — What's next; current state
  per area.
- Future design docs under `docs/`:
  [v2 inter-chimebox AppleTalk](./docs/v2-appletalk-design.md),
  [v2 printer bridge](./docs/v2-printer-bridge-design.md),
  [v2 panic-button](./docs/v2-panic-button-design.md),
  [v3 modern-protocol bridge appliance](./docs/v3-bridge-appliance-design.md).

Per-role READMEs under `pi/ansible/roles/<role>/README.md` document
each component in depth.

## Acknowledgements

Chimebox stands on the shoulders of years of work by the retro
computing community. Most directly, it draws on:

- **[Infinite Mac](https://github.com/mihaip/infinite-mac)** by Mihai
  Parparita (Apache 2.0) — the disk-build pipeline, machine and disk
  definitions, and curated Macintosh Garden manifests are invaluable
  starting points.
- **[Basilisk II](https://basilisk.cebix.net/)** and the **macemu**
  family of emulators (GPL v2).
- **[Macintosh Garden](https://macintoshgarden.org/)** — without their
  abandonware preservation work, there would be no software to load.

See [`NOTICE`](./NOTICE) for full attributions and
[`LICENSING.md`](./LICENSING.md) for the layered licensing situation
around code, ROMs, and disk images.

## License

Source code in this repository is licensed under the **Apache License
2.0**. See [`LICENSE`](./LICENSE).

ROMs, system disk images, and other Apple-copyrighted material are
**not** part of this repository and must be obtained by the user. See
[`LICENSING.md`](./LICENSING.md) and
[`disks/README.md`](./disks/README.md).
