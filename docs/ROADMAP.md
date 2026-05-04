# chimebox roadmap

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
- [ ] **Decide on kid-shortlist Desktop**. Once the library is
      mounted, the user customization step (deferred from v1) drops
      a shortlist of kid-appropriate apps onto the Desktop and
      hides the Developer / esoteric folders.

### Hardware

- [ ] **Active cooler** (in transit). Replace passive heatsink;
      expected drop from ~56°C idle-load to ~35–45°C.
- [ ] **NVMe SSD** (in transit). Reflash + Ansible re-run; copy
      disks back via push-disks. Reliability win for daily-driver
      use.
- [ ] **Final keyboard/mouse**. Wired, full-size keyboard (no
      chiclet); 2-button optical mouse.

## v1.5 reliability — validate the safety nets actually work

Things we set up but didn't test against real failures.

- [ ] **Snapshot cron**: confirmed installed, never observed firing.
      Wait for 03:17 local OR force `sudo /usr/local/sbin/chimebox-snapshot daily`,
      then verify a snapshot lands in `~/chimebox/snapshots/`.
- [ ] **kid-reset.sh against a real snapshot**: produce damage in
      Mac OS, then `./scripts/kid-reset.sh latest`, verify state is
      restored.
- [ ] **service-mode.sh round-trip**: stop kiosk, do work, exit,
      verify kiosk auto-resumes.
- [ ] **push-disks.sh end-to-end**: this session bypassed the
      script and used `scp` manually. Run the actual script with
      rsync now that rsync is installed. Validate sudo
      handling, file ownership, perms.
- [ ] **Power-yank chaos test**: yank power 10 times in 5 minutes,
      ensure the Pi always comes back into a working kiosk.
- [ ] **Investigate Ansible privilege-escalation timeouts**: the
      pattern of "first run times out, second works" or "sometimes
      30s isn't enough" was reproducible this session. Suspect
      pipelining + SSH multiplexing interaction. Try
      `ANSIBLE_PIPELINING=False`, or pin sudoers ahead of time, or
      use a dedicated SSH connection per Ansible run.

## v1 documentation

Specifically deferred docs from the foundation chunk:

- [ ] `docs/era-decisions.md` — why Mac OS 8.1 + Quadra 650, why
      BasiliskII over Mini vMac/SheepShaver, why Ansible, why X11.
      Citing this thread's reasoning.
- [ ] `docs/operations.md` — day-2 ops runbook: how to push disks,
      snapshot, reset, enter service mode, check health.
- [ ] `docs/recovery.md` — when things go wrong: power-yank
      recovery, corrupted System.dsk, Pi won't boot, kiosk respawn
      loop, etc.
- [ ] `docs/shortlist.md` — curated kid-software list with age
      notes, sourced from Macintosh Garden, organized by category
      (drawing, games, education, utilities).

## v2 features

Bigger-than-v1 items that need design.

- [ ] **Hide the Linux boot, show a Happy-Mac splash instead**.
      Today the user sees the Pi rainbow splash, then scrolling
      systemd boot output, then the X session starts. Goal: from
      power-on to BasiliskII, never expose Linux. Mechanism:
        - `cmdline.txt` flags: `quiet splash logo.nologo console=tty3
          vt.global_cursor_default=0 plymouth.ignore-serial-consoles`
        - Custom plymouth theme rendering a fullscreen image (e.g.
          the classic "Welcome to Macintosh" / Happy Mac)
        - Disable the Pi's rainbow splash via `disable_splash=1` in
          `/boot/firmware/config.txt`
        - Probably a new Ansible role `boot-splash` with a default
          theme but designed to be replaceable by users who want
          different aesthetics.
      Plays well with the existing `hdmi-firmware-pin` work in v1
      polish; both touch `/boot/firmware/config.txt`.

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

- [ ] **PiKVM mouse compatibility (or document its absence)**.
      PiKVM emulates a USB HID device and sends absolute pointer
      coordinates. BasiliskII with `init_grab=true` (relative-mouse
      capture mode, which we set for kiosk-quality interaction)
      interprets those absolute values as relative deltas, producing
      backwards/upside-down/weird cursor behavior. Options:
        - Document the limitation: use SSH for chimebox admin, not
          PiKVM. (Most likely outcome.)
        - Toggle B2 between absolute and relative modes via a
          script ("chimebox-pikvm-mode on/off").
        - Detect PiKVM by USB VID/PID at start.sh time and pick
          the right `init_grab` value.
      Worth a lesson file once we confirm the diagnosis.

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

- [ ] **Verify no internet egress from kiosk**: `tcpdump -i eth0
      not port 22` should be silent under normal use. Add a
      firewall rule or DNS sinkhole as belt-and-suspenders.
- [ ] **Audit mDNS / Bonjour broadcasts**: Pi may be advertising
      services on the LAN. Lock down to `chimebox-dev` only.
- [ ] **Read-only root filesystem**: Pi 5 supports overlayfs /
      `init_resize` patterns to mount `/` read-only with a tmpfs
      overlay. Power-yank-proof at the FS level.

## v3 — open-source release

Items that move chimebox from "personal project" to "publishable".

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
