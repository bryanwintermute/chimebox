# chimebox roadmap

> **Last meaningful sweep:** 2026-05-14. v1 is functionally
> complete; this doc retains historical items as evidence/audit
> trail with `[x]` markers. For *current* todo state see the
> commit log + role READMEs.

This document tracks known follow-up work, organized by phase. The
session that brought up the basic case (Mac OS 8.1 booting on a Pi 5
through Ansible-managed kiosk) flushed a lot of items into the "we
should do that next time" pile; this is where they live now.

Items here are intent. Code is truth — when something on this list is
done, link the commit and move it to the "done" section at the bottom.

## v1 polish — get to "kid-ready"

Things that should land before any actual handoff to a young user.

### Display

- [ ] **Pin HDMI mode at firmware level**: today `start.sh` calls
      `xrandr` after X starts, so the pre-X console (Pi rainbow splash,
      systemd boot output) still uses the EDID-preferred mode (4K on
      modern monitors) and looks weird. Add config to
      `/boot/firmware/config.txt` (or `cmdline.txt` `video=` for KMS)
      to lock the kernel mode at 1080p too. New Ansible task in the
      `base` or a new `display` role.
- [ ] **Verify SDL window centering**: `SDL_VIDEO_CENTERED=1` is set in
      `start.sh`. Confirm visually that the 1440x1080 window is
      actually centered in the 1920x1080 X canvas (vs. pinned to
      top-left).

### Audio

- [x] **Validate audio output**. ✅ Confirmed working when a USB
      speaker is plugged in at boot time. (User's earlier "no sound"
      observation was a hot-plug issue, not a config problem.)
- [ ] **HDMI vs. analog routing**. If audio doesn't work out of the
      box, configure ALSA / PipeWire defaults to route to HDMI
      (assuming the monitor has speakers) or to a USB DAC.
- [ ] **Default volume level**. Boot chime at 100% can be loud. Set a
      sane default (50–70%) via Ansible.
- [ ] **Hot-plug audio devices**. Today, BasiliskII picks the
      default audio sink at start. Plugging a USB speaker after the
      kiosk has launched does nothing. Decide whether to handle this
      (PipeWire migration on hot-plug) or document the constraint
      ("plug audio in before powering on").

### Shutdown / power

- [ ] **Decide Mac-OS-shutdown semantics.** When the user picks
      `Special > Shut Down` in Mac OS 8.1, BasiliskII exits, then
      `start.sh` ends, then the X session ends, then the chimebox
      `.bash_profile` returns, then getty respawns and immediately
      autologs back in. The Mac restarts. Possible behaviors:
        - Current: silent restart of the Mac (probably fine for v1).
        - Show a "powered off" screen until the Pi is actually
          rebooted.
        - Trigger `sudo systemctl poweroff` (kid has to ask the
          adult to power back on). Probably too restrictive.
- [ ] **Restart vs. Shut Down**: today both do the same thing.
      Restart should snapshot first (cheap insurance).
- [ ] **Power-yank handling**. The kid will yank power. Verify that
      System.dsk survives a yank cleanly (HFS robustness depends on
      what BasiliskII flushed). Add a snapshot-on-restart hook so
      every clean Mac shutdown produces a snapshot.

### Disks / library

- [ ] **Run full `disk-prep` on the M5 Mac** to produce a populated
      `InfiniteHD.dsk` (curated Macintosh Garden library: KidPix,
      MacPaint, HyperCard, Oregon Trail, Lemmings, Number Munchers,
      etc.). Push via `scripts/push-disks.sh`.
- [ ] **Kill the "missing Infinite HD" dialog** at boot. Either:
        - Push a real `InfiniteHD.dsk` (above), or
        - Customize `System.dsk` (HFS edit) to remove the desktop
          alias to Infinite HD.
- [x] **Decide on kid-shortlist Desktop**. Done 2026-05-14 — curated
      Tier S on Desktop, factory-blessed via polite Mac shutdown.

### Hardware

- [x] **Active cooler** (Argon One V3 case installed). Sustained-load
      temps ~47°C; cron-fan via the role's daemon.
- [x] **NVMe SSD** (256GB; validated real via 100GiB pattern test).
- [ ] **Final keyboard/mouse**. Wired, full-size keyboard (no
      chiclet); 2-button optical mouse.

## v1.5 reliability — validate the safety nets actually work

(Status: all items below validated; section retained as evidence.)

- [x] **Snapshot cron**: validated 2026-05-07; cron has fired daily
      May 4 through current, plus Sunday-weekly auto-chain.
- [x] **kid-reset.sh against a real snapshot**: done 2026-05-07 via
      HFS Volume Header zeroing; post-reset System.dsk byte-perfect
      to baseline.
- [x] **service-mode.sh round-trip**: stop kiosk, do work, exit,
      verify kiosk auto-resumes. Validated.
- [x] **push-disks.sh end-to-end**: rsync path validated.
- [x] **Power-yank chaos test**: validated 2026-05-08 (accidentally
      power-cycled the Pi during testing; recovered cleanly, all
      snapshots intact, daemon auto-started, supervisor loop
      resumed).
- [ ] **Investigate Ansible privilege-escalation timeouts**: the
      pattern of "first run times out, second works" or "sometimes
      30s isn't enough" was reproducible this session. Suspect
      pipelining + SSH multiplexing interaction. Try
      `ANSIBLE_PIPELINING=False`, or pin sudoers ahead of time, or
      use a dedicated SSH connection per Ansible run.

## v1 documentation

(Status: all v1 docs landed; this section retained as a milestone marker.)

- [x] `docs/era-decisions.md` — done 2026-05-06 (commit f78987a).
- [x] `docs/operations.md` — done 2026-05-14 (commit b595ced).
- [x] `docs/recovery.md` — done 2026-05-14 (commit 05a246e).
- [x] `docs/shortlist.md` — done long ago.
- [x] `docs/architecture-patterns.md` — done 2026-05-14 (commit
      c5c1b42); added during the Tier B docs trio for public release.

## v2 features

Bigger-than-v1 items that need design.

- [x] **Hide the Linux boot, show a Happy-Mac splash instead**.
      Done via the `boot-splash` Ansible role (Plymouth-based);
      pillarbox-friendly defaults, replaceable by users who want
      different aesthetics.

- [ ] **Boot-time selector for which environment to launch**. A
      small selector shown briefly before the kiosk locks in,
      letting the user pick: Mac OS 7.5.5, Mac OS 8.1, Mac OS 9
      (SheepShaver), NeXTSTEP (Previous), Apple II (MAME), etc.
      Driven by a `chimebox_profiles` list in group_vars; each
      profile names an emulator role + ROM + disk set. UI options:
      curses TUI on tty1, or SDL-rendered menu before BasiliskII.
      Prerequisite: Ansible roles for multi-emulator support
      (`chimebox` role would split into `chimebox-runtime` +
      one emulator role per supported emulator).

- [x] **PiKVM mouse compatibility** — Resolved via the
      `chimebox_display_profile` abstraction (per-host config) plus
      `scripts/mouse-mode.sh` for runtime toggling between
      `grab`/relative (physical mouse) and `absolute`/PiKVM/VNC
      modes. The `matched-stretched` profile is the PiKVM-friendly
      default.

- [ ] **At Ease overlay** as opt-in role. Apple's actual kid-shell
      from this era. Fully period-correct alternative to "raw
      Finder". Toggle via `chimebox_use_at_ease: true` in
      group_vars.
- [ ] **Multi-OS bootpicker**: System 7.5.5 / Mac OS 8.1 / Mac OS 9
      selectable at startup. May want SheepShaver + Mac OS 9 path.
- [ ] **Multi-profile support**: separate `System.dsk` per kid
      (siblings, cousins). Selectable at boot.
- [ ] **Time-machine browser**: tiny web UI on a sidecar device
      showing daily snapshots so kid can revisit drawings from any
      past day.
- [ ] **Emulated AppleTalk between two chimeboxes**: native B2
      supports real LAN AppleTalk; needs router config or VLAN.
      Bolo, Marathon co-op, file sharing.
- [ ] **AT Ease for Workgroups / network printer emulation** for
      when the kid wants to "print" their drawings (capture to
      PDF on the host).

## v2 reliability + security

- [x] **Verify no internet egress from kiosk**: Done 2026-05-12 via
      the `egress-firewall` Ansible role (commit 84a5a50). Per-user
      nftables `meta skuid` rule blocks the kiosk user from
      reaching off-LAN destinations; operator + host services
      unaffected. Validated: 1.1.1.1 timeouts from kiosk user,
      drops logged with full packet detail, operator's curl
      reaches example.org as normal.
- [ ] **Audit mDNS / Bonjour broadcasts**: Pi may be advertising
      services on the LAN. Lock down to `chimebox-dev` only.
- [ ] **Read-only root filesystem**: Pi 5 supports overlayfs /
      `init_resize` patterns to mount `/` read-only with a tmpfs
      overlay. Power-yank-proof at the FS level.

## v3 — open-source release

Items that move chimebox from "personal project" to "publishable".

- [ ] **Vendor or self-host disk-image chunks**: `disk-prep/4-fetch-cdn.sh`
      currently fetches chunks from `infinitemac.org`. Fine for a
      personal project; for the public OSS release we should not
      implicitly pin every chimebox user to Mihai's R2 bandwidth.
      Three approaches:
        - Vendor a snapshot of chunks into our own GitHub releases
          (~1-2GB, doable). Pin to a specific upstream commit.
        - Build our own scope-able pipeline that produces only what
          we want (subset of system disks + customizable Infinite HD).
          More work; gives full control.
        - Document the dependency clearly and let users opt in to
          either upstream-fetch or self-build.
      Probably the right answer is option 3 default with option 1
      as a CI-built fallback.

- [ ] **Linux/Docker disk-prep path**: remove macOS dependency in
      `disk-prep/`. The hard part is the desktop-DB rebuild step
      that currently calls native `MiniVMac.app`/`BasiliskII.app`.
- [ ] **GitHub Actions CI**: at least YAML lint, shellcheck,
      `ansible-playbook --syntax-check`. Optionally a Vagrant /
      QEMU-arm64 target so playbook changes get validated without
      a physical Pi.
- [ ] **Generalize beyond Mac**: same kiosk pattern could host
      DOSBox + Win 3.1, an Apple II via MAME, an Amiga via FS-UAE,
      etc. Refactor `chimebox` role to be emulator-agnostic;
      `basiliskii` is one of several emulator roles.
- [ ] **Hardware variants doc**: ADB-USB keyboard via tinkerBOY,
      real CRT recommendation, period-correct case options.
- [ ] **Public README polish**: a "what is this and how do I get
      one" walkthrough that doesn't assume reading commits.

## Done

A non-exhaustive trail of major milestones:

- ✅ Foundation scaffold and licensing (`b4e3dc9`)
- ✅ disk-prep tooling validated on real macOS (`98469ca`,
  `93119c6`, `1a1959e`)
- ✅ Ansible playbook with 7 roles, validated against real Pi 5
  (`5590149`, `774bd89`)
- ✅ Trixie default (`97a7f75`)
- ✅ Workstation-side ops scripts (`82cd38d`)
- ✅ Mac OS 8.1 booting on Pi 5 (`a126ea2`)
- ✅ Display + mouse polish for the dev display: 1024x768 host,
  init_grab capture mode (`5f068f5`, `25afe22`, `99051d9`)
- ✅ Pi Imager APFS-on-target gotcha documented in pi/SETUP.md
  (`8462da5`)
- ✅ Display profile configurable; pillarbox 4:3 is the new default,
  with stretched-fullscreen and native-sharp as documented
  alternatives (`43557b7`)
- ✅ NVMe migration: re-flashed, re-provisioned via the same Ansible
  playbook (37 tasks, 0 failed), disks pushed via real
  push-disks.sh (first end-to-end run), Mac OS 8.1 booted cleanly.
  Active cooler also validated: 56°C → 43°C under load.
- ✅ Argon One V3 role with sha256-pinned upstream sources, opt-in via
  `chimebox_argon_one_v3`, fan curve via `chimebox_argon_fan_curve`,
  validated audibly via i2cset A/B/C test (`2b1913a`)
- ✅ EEPROM config tweaks for Argon One V3 applied idempotently
  (`6d1098d`): POWER_OFF_ON_HALT=1, WAKE_ON_GPIO=0, BOOT_ORDER=0xf416,
  PCIE_PROBE=1. Validated post-reboot.
- ✅ PiKVM remote-pointer support fixed (`96d87ed`): replaced classic
  unclutter with unclutter-xfixes (the polling unclutter interferes
  with SDL2 motion-event delivery), added SDL2 hints
  (SDL_MOUSE_FOCUS_CLICKTHROUGH=1, SDL_VIDEO_X11_XINPUT2=1), added
  matchbox-window-manager. Display profile abstracted into
  chimebox_display_profile var with three named profiles
  (pillarbox / matched-stretched / native-sharp). chimebox-dev's
  host_vars overrides to matched-stretched for PiKVM compatibility.
