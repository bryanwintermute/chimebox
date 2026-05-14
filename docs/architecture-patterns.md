# Architecture patterns

This document captures the **reusable design patterns** that
chimebox uses, separately from the specific Mac OS 8.1 / BasiliskII
implementation. It's the doc to read if you're considering forking
chimebox for a different emulator stack (chimebox-windows running
DOSBox + Win 3.1, chimebox-amiga running FS-UAE, chimebox-apple-ii
running MAME, etc.) — or just to understand the shape of how
chimebox holds together.

For the specific Mac-emulator architecture see
[`architecture.md`](./architecture.md). For day-2 operations see
[`operations.md`](./operations.md). For recovery see
[`recovery.md`](./recovery.md).

## What chimebox is and isn't, structurally

**Chimebox is** a *category* of single-purpose retro-computing
kiosk:

- Boot directly into a chosen retro OS
- No host-OS UI ever visible to the end user
- Persistent, snapshot-able state
- Remote operator access via SSH; never via sitting at the kiosk
- Built declaratively from an Ansible playbook so anyone can
  reproduce the setup

The specific Mac OS 8.1 / BasiliskII implementation is one
*instance* of this category. The rest of this doc names the
reusable shapes — patterns that any chimebox-flavored project
benefits from, regardless of what emulator is at the center.

## Pattern 1: Boot chain to a single foreground app

The kid sees the emulator's screen as if it were a real
retro computer. To get there, chimebox uses a deliberately
unfashionable boot chain — no display manager, no desktop
environment, just the minimum to get one fullscreen X
application running.

```
systemd
  └── getty@tty1.service
        └── /sbin/agetty (autologin chimebox user)
              └── login → bash
                    └── ~/.bash_profile: exec startx
                          └── ~/.xinitrc: exec ~/chimebox/start.sh
                                └── start.sh: supervisor loop
                                      └── BasiliskII -fullscreen ...
```

Each link is the simplest tool that does its job:

| Link | Why this and not X |
|---|---|
| `getty@tty1.service` + autologin | One systemd-managed entry point. Killing the service tears down everything downstream. No need for the emulator to know about systemd. |
| `~/.bash_profile: exec startx` | Replaces the shell with X; no chance of the kid escaping to a Bash prompt via Ctrl+C. |
| `~/.xinitrc: exec start.sh` | Replaces X's session with our supervisor; no window manager, no desktop, nothing to break out to. |
| `start.sh` supervisor loop | Owns the lifecycle of the emulator — restart on crash, log per-launch, honor a sentinel file for clean pauses. |
| `BasiliskII -fullscreen` | The kid sees only the emulator. |

The pattern generalizes to **any single-app kiosk**, retro or
not. The same chain works for a video-wall slideshow, a
museum-exhibit information display, a digital signage panel.
The emulator is just one possible "foreground app."

Forking for chimebox-amiga? Replace `BasiliskII` in start.sh
with `fs-uae` (or `mame -arcade`, or `dosbox-staging`, etc.).
The rest of the chain is unchanged.

See [`pi/ansible/roles/kiosk-user/README.md`](../pi/ansible/roles/kiosk-user/README.md)
and [`pi/ansible/roles/chimebox/README.md`](../pi/ansible/roles/chimebox/README.md)
for the implementation.

## Pattern 2: Supervisor loop with sentinel-file pause

`start.sh` doesn't just `exec` the emulator — it wraps the
emulator in a `while`-loop supervisor that re-launches on
crash. This is critical for kid-friendly UX: a normal Mac OS
crash (Type 10 error etc.) becomes "Mac chimes, you're back
at the Desktop in 2 seconds" rather than "kiosk dies, kid
sits looking at a black screen until an adult shows up."

```sh
while true; do
    if [ -f /run/chimebox-bedtime ]; then
        sleep 5     # sentinel armed -- idle, don't respawn
        continue
    fi
    BasiliskII <args>     # blocks until BasiliskII exits
    sleep 1               # avoid hot-loop on instant crash
done
```

The **sentinel file** is the crucial addition. Without it, any
host-side script trying to do "stop the emulator briefly, then
restart it" fights with the supervisor — `kill BasiliskII`,
supervisor respawns within 1-2 seconds, the script never gets
its window of opportunity. With the sentinel, host-side scripts
have a clean contract:

```sh
# To pause the kiosk:
touch /run/chimebox-bedtime
kill -TERM "$(pgrep -x BasiliskII)"      # emulator exits cleanly
# ... do something requiring the emulator be stopped ...
rm /run/chimebox-bedtime                  # supervisor respawns automatically
```

This pattern shows up in three chimebox scripts:
- `bedtime.sh` (end-of-day shutdown)
- `factory-bless.sh` (capture a clean disk-image snapshot)
- `service-mode.sh` (maintenance window)

A reusable lesson on this exact pattern is at
`~/github/myconfigs/copilot/lessons/supervisor-loop-sentinel-pattern.md`.

For any kiosk where you ever need to "briefly tell the foreground
app to step aside without killing the kiosk" — debugging, backups,
periodic maintenance — the sentinel pattern is the simplest
solution that doesn't require the supervisor to know about
external coordination protocols.

## Pattern 3: Snapshot + restore at the disk-image layer

The emulated machine's "computer" is a disk image file on the
host filesystem. Snapshotting that file gives you a complete
machine-state backup with no emulator cooperation required.

chimebox has two snapshot tiers:

| Tier | Purpose | Trigger | Granularity | Cleanliness |
|---|---|---|---|---|
| **Rotating** (daily/weekly/manual) | Recent recovery points | cron + ad-hoc | One per day/week + ad-hoc manuals | "Live snapshot" — disk image is dirty (HFS clean-unmount bit not set). Restorable but next boot will fsck. |
| **Factory baseline** | The operator-blessed "as-shipped" state | Operator-driven via `factory-bless.sh` | Exactly one, re-bless to update | Clean — the script politely shuts down the emulated OS first, then snapshots |

The architectural point isn't "have backups" — it's that
**the snapshot layer lives below the emulator**, in the host
filesystem. This works regardless of what's running inside:

- Mac OS 8.1 in BasiliskII → System.dsk is HFS, snapshot it
- DOS 6.22 in DOSBox → C: drive image is FAT16, snapshot it
- Windows 95 in QEMU → vhd file, snapshot it
- Amiga Workbench in FS-UAE → adf file, snapshot it

The "clean vs dirty snapshot" distinction is universal too —
any disk-image snapshot taken while the guest OS is running
is dirty (the guest has writes in flight). To get a clean
snapshot, you ask the guest to shut down first. The pattern
is the same; only the "ask politely" mechanism differs per
guest.

For Mac OS / BasiliskII the mechanism is `SIGTERM`, which
BasiliskII forwards as a guest-side "shutdown requested" event,
which Mac OS handles by showing its standard shutdown dialog.
For QEMU the equivalent is `system_powerdown` via the monitor.
For DOSBox there's no analog — DOS doesn't really have "shut
down cleanly"; FAT writes are atomic enough that a SIGKILL is
usually OK.

The full pattern, with bookends:

```
1. Arm sentinel file (so supervisor won't respawn)
2. Send shutdown signal to guest (mechanism varies per emulator)
3. Wait for emulator to exit naturally (with timeout)
4. Capture the now-quiesced disk image
5. Clear sentinel file (supervisor respawns; guest reboots)
```

See `~/github/myconfigs/copilot/lessons/snapshot-disk-image-only-after-clean-unmount.md`
for the full lesson, including the HFS forensic verification
trick (read drAtrb at offset 1024 with `dd | od`).

The split between **rotating snapshots** (cheap, frequent,
may be dirty) and **factory baseline** (deliberate, clean,
single) is also universal. Rotating snapshots are for "kid
deleted something, let's go back 5 minutes." Factory baseline
is for "I've curated the kid's experience exactly the way I
want; this is the version I shipped." Different semantics,
different durability, different audiences for the rollback
decision.

## Pattern 4: Below-X keystroke daemon for panic/recovery combos

Single-app kiosks have a UX challenge: how do you give the
operator escape hatches (force-reset, eject USB, return to
factory) without giving the kid those same hatches in a
discoverable way?

The naive approach is X-layer keystroke catching (xbindkeys,
hotkey scripts running under the X session). It fails on
modern emulators that grab the keyboard via XInput2 raw mode:
SDL2-based emulators (BasiliskII, DOSBox-staging, FS-UAE)
bypass classic XGrabKey grabs entirely. The X-layer hotkey
catcher never sees the combo when the emulator window has
focus.

The fix is to **catch keystrokes at the evdev layer**, below
X. The chimebox `panic-button` Ansible role installs a Python
daemon that reads `/dev/input/event*` directly. The kernel
delivers every key press to every reader, so the daemon sees
modifier+trigger combos regardless of what X (or any emulator)
is doing with them.

The combos are designed to be **operator-friendly,
kid-resistant**:

- 4-modifier minimum (Ctrl+Alt+Shift+key) — impossible to
  hit by accident in normal typing
- Optional hold-time gate (default 1.5s for destructive
  combos like kid-reset) — a kid mashing the keyboard can't
  stumble in
- Each action is `logger -t TAG` audited (forensic trail)
- Opt-in per host (the destructive combos default off)

This pattern generalizes to any kiosk where you want:
- Operator-discoverable escape hatches
- Kid-/user-resistant accidental triggers
- X-grab-immune capture

The evdev approach also works for *non-keyboard* event sources:
foot pedals, USB game controllers, IR remotes. Same daemon
shape; different `/dev/input/event*` devices in scope.

See:
- [`pi/ansible/roles/panic-button/README.md`](../pi/ansible/roles/panic-button/README.md)
- `~/github/myconfigs/copilot/lessons/xbindkeys-vs-evdev-for-sdl2-kiosks.md`
- `~/github/myconfigs/copilot/lessons/evdev-hold-combos-need-autorepeat.md`

## Pattern 5: Prefs-file-as-source-of-truth (and Ansible reasserts it)

Most emulators store configuration in a text file the user (or
emulator GUI) can modify. Without external discipline these
files drift — a user edits one setting in the GUI, then forgets,
then six months later wonders why "their" config is different
from what's in version control.

chimebox's approach: **the prefs file is rendered by Ansible
from a template on every playbook run**. Any drift gets
overwritten. The canonical config lives in the playbook +
host_vars; the file on disk is downstream.

For BasiliskII this is `roles/chimebox/templates/basiliskii-prefs.j2`.
The render path is fully deterministic from the playbook
inputs. If someone edits `~/.config/BasiliskII/prefs` directly
on the Pi, the next playbook run wipes the edit.

This pattern requires:
- A template renderer (Jinja2 via Ansible)
- A definition of "this file is canonically rendered, hands-off
  on the target" — usually a clear comment at the top of the
  rendered file
- Per-host variables for the bits that legitimately differ
  (LAN CIDR, audio card name, display profile, etc.)
- A gitignored "local overrides" file for per-host values that
  shouldn't enter the public repo (chimebox uses
  `host_vars/<host>/local.yml`)

This pattern generalizes to **any service config managed by
Ansible**: nginx.conf, dnsmasq.conf, fail2ban jail.local,
whatever. The structural shape is identical regardless of
what's being templated.

## Pattern 6: Per-user privilege model + host filesystem layout

Chimebox has three distinct "users" in the security sense:

| User | UID | Role | What it can do |
|---|---|---|---|
| Admin user (default `admin`) | 1000 | The operator (you) | sudo, SSH, full network, apt updates |
| Kiosk user (`chimebox`) | 1500 | The kid-facing emulator session | runs X + BasiliskII, no SSH, no sudo, LAN-only egress |
| `root` | 0 | host services (DHCP, NTP, cron, systemd) | full system access; not interactive |

The split serves multiple purposes:

1. **Defense in depth.** If the kid somehow escapes the
   emulator into a host shell, she's `chimebox` with no
   sudo, no SSH, no shell history, locked password.
2. **Filesystem ownership tells the story.** `0640
   chimebox:chimebox` on `System.dsk` means "the emulator
   reads/writes this; nothing else does." `0440
   chimebox:chimebox` on `factory.dsk` means "read-only,
   even to the emulator user." `0750 chimebox:chimebox`
   on the snapshots dir means "only root and chimebox can
   list / read."
3. **Egress firewall scopes naturally to the kiosk user.**
   `nftables meta skuid chimebox jump restrict_user` —
   operator and host services are unaffected by the
   kid-facing restrictions.
4. **Future bridges run as their own users.** The pattern
   extends: `chimebox-bridge-print` (for an eventual CUPS
   bridge), `chimebox-bridge-atalk` (for AppleTalk-over-UDP),
   `chimebox-bridge-msg` (for modern messaging). Each gets
   their own scoped network rules via the same `meta skuid`
   mechanism.

For any forker considering a chimebox-flavored project:
think about your three-user model upfront. "The thing the
end user sees" should be its own UID, distinct from "the
operator" and "host services." The egress firewall and
filesystem perms fall out naturally from that decision.

See:
- [`pi/ansible/roles/kiosk-user/README.md`](../pi/ansible/roles/kiosk-user/README.md)
- [`pi/ansible/roles/egress-firewall/README.md`](../pi/ansible/roles/egress-firewall/README.md)
- `~/github/myconfigs/copilot/lessons/nftables-meta-skuid-per-user-egress.md`

## Pattern 7: Per-host config via directory-style host_vars

For variables that genuinely differ per chimebox install
(LAN CIDR, audio card name, display profile, hostname-
specific tweaks), Ansible's `host_vars/<host>/` directory
gets merged at runtime. Chimebox uses this with two files
per host:

```
pi/ansible/host_vars/
  <hostname>/
    main.yml          ← committed, generic per-host overrides
    local.yml         ← gitignored, privacy-sensitive values
```

Examples of "generic enough to commit":
- `chimebox_argon_one_v3: true`
- `chimebox_display_profile: matched-stretched`
- `chimebox_panic_button_kid_reset_enabled: true`

Examples of "privacy-sensitive, gitignored":
- `chimebox_lan_cidrs: ["192.168.1.0/24"]` (reveals home network range)
- `chimebox_audio_card: SpecificDeviceName` (reveals specific hardware)

The pattern: **Ansible merges all .yml files in
`host_vars/<host>/`**, so committed overrides + local
overrides combine cleanly without requiring one file with
two posture/audiences.

The `.gitignore` entry that makes this work:

```gitignore
pi/ansible/host_vars/*/local.yml
```

For any Ansible project where some per-host overrides should
be public (for OSS readability) and others should stay
private (for the maintainer's actual environment), this
two-file directory-style host_vars is the cleanest split.

## Pattern 8: Discovery helpers for per-host config

Per-host config knobs have a UX problem: when the operator
first runs the playbook, they don't know what to set the knob
to. "Which audio card should chimebox_audio_card point at?"
requires they SSH in, run `aplay -l`, run `amixer scontrols`
per card, decide.

The mitigation: **for any per-host config knob, ship a small
helper script** that probes the host and prints copy-paste-
ready host_vars. Chimebox has:

- `/usr/local/sbin/chimebox-audio-list` — enumerates ALSA cards,
  shows mixer controls per card, shows current routing,
  suggests `chimebox_audio_card` + `chimebox_audio_master_control`
  values tailored to the actually-present hardware

A future chimebox-windows fork that exposes a
`chimebox_display_card` knob would similarly want a
`chimebox-display-list` helper that probes connected
monitors + their resolutions + recommends the display
profile.

The full lesson, with anti-patterns:
`~/github/myconfigs/copilot/lessons/discovery-helpers-for-per-host-config.md`.

## Pattern 9: "Outside world" extfs + USB auto-mount

The kid's session can't reach the host filesystem directly,
but she does need to:
- Save her drawings somewhere persistent (survives factory-reset)
- Receive photos / files from a USB stick the operator plugs in

Chimebox solves this with BasiliskII's `extfs` feature: one
host directory is exposed to the guest Mac as a "Unix" volume.
The volume's root holds:
- A "Kid's Drawings" sub-folder for persistent saves
- Auto-mounted sub-folders per USB stick (via udev + systemd
  template units)

The pattern generalizes if your emulator has anything like
extfs. DOSBox has `mount c:` host-folder support; FS-UAE has
host-directory drives; QEMU has `virtfs`/9P. Each has its
own quirks (the BasiliskII extfs has a per-app save-success
gotcha — see `basiliskii-extfs-app-specific-saves.md`) but
the architectural pattern is the same: **one host directory =
one guest volume + udev auto-mounting USB sticks into
sub-folders**.

See:
- [`pi/ansible/roles/outside-world/README.md`](../pi/ansible/roles/outside-world/README.md)
- `~/github/myconfigs/copilot/lessons/udev-systemd-mount-template-pattern.md`
- `~/github/myconfigs/copilot/lessons/basiliskii-extfs-app-specific-saves.md`
- `~/github/myconfigs/copilot/lessons/exdev-in-emulator-virtual-volumes.md`

## Pattern 10: Forensic logging via `logger -t TAG`

Operations on a kiosk happen mostly without an interactive
observer. Cron-fired snapshots, panic-button combos, USB
mount/unmounts, audio re-routings — these run silently. To
debug "did this actually happen last night?" you need a
journal trail.

Chimebox's convention: **every script that does something
non-trivial calls `logger -t TAG`** with a stable tag. Then
`journalctl -t TAG` shows the forensic record at any later
time.

The double-log pattern in chimebox scripts:

```bash
LOG_TAG="chimebox-foo"
log() {
    logger -t "${LOG_TAG}" -- "$*"
    echo "${LOG_TAG}: $*" >&2
}
```

The `logger -t` writes to the journal (queryable later); the
`echo >&2` keeps live output useful for interactive runs.
Both at the same time.

Tags in use:
- `chimebox-snapshot`, `chimebox-reset` (persistence)
- `chimebox-panic`, `chimebox-force-reset`, `chimebox-reset-latest`, `chimebox-emergency-stop` (panic-button)
- `chimebox-audio-init` (audio)
- `chimebox-usb` (outside-world auto-mount)
- `chimebox-egress-drop` (egress firewall, via nftables kernel log)

Cron's wrapper line (`CRON[pid]: (root) CMD (...)`) is
*invocation only* — your script's actual outcome goes to local
mail by default, which is `/dev/null` on most kiosks. Without
`logger -t TAG` in your script, you'll have no record of
*what happened* after a cron run.

See `~/github/myconfigs/copilot/lessons/cron-output-invisible-without-logger.md`.

## Pattern 11: Three-tier recovery layering

Recovery options in chimebox aren't a single mechanism; they
stack:

| Tier | Mechanism | Granularity | Trigger | Data lost |
|---|---|---|---|---|
| **1: Force-reset** | `Ctrl+Alt+Shift+R` (panic-daemon) | Emulator process only | Operator combo or `kill -KILL` | Nothing on disk; in-memory only |
| **2: Rotating snapshot rollback** | `kid-reset.sh latest`, `Ctrl+Alt+Shift+Z` (hold 1.5s) | The whole system disk | Operator | Anything since the last cron snapshot |
| **3: Factory rollback** | `factory-reset.sh` | The whole system disk | Operator | Anything since the last factory-bless |
| **4: Re-image** | Pi Imager + ansible re-run | Everything except `outside-world/` | Operator | Snapshots; possibly factory.dsk; recent host config |

Each tier solves the previous tier's "edge case." Force-reset
doesn't help if the disk is damaged. Rotating snapshot doesn't
help if the damage was captured in the snapshots. Factory
rollback doesn't help if the factory.dsk is wrong. Re-image
doesn't help if the boot media is dying.

For any kiosk where "the user might break it" is a real
concern, designing in this layering up front (and giving the
operator escape hatches at each layer) is much cheaper than
adding it later.

## Pattern 12: The privacy / OSS-readiness layering

Chimebox is built for a specific kid in a specific home but
intended for public release. That tension shows up at every
documentation and config decision. The patterns chimebox uses:

| Where | Pattern |
|---|---|
| Repo-committed configs (group_vars) | Use generic examples (`192.168.1.0/24`, `MyUSBDAC`, "admin" user) — readers' defaults will be similar to these |
| Per-host privacy-sensitive overrides | Live in gitignored `host_vars/<host>/local.yml` |
| Docs that reference the maintainer's setup | Sanitize (replace real names/IPs with generic placeholders); the maintainer's real values stay in local.yml |
| The end user's identifying details (name, age) | **Never committed anywhere.** Plan-mode docs in session state only. |
| ROMs, disk images, photos | Excluded via `.gitignore` patterns |
| Snapshot artifacts (`*.dsk`) | Same — gitignored, never in repo |

For any OSS project that's also someone's personal infrastructure,
the principle is: **the public repo should be useful to a stranger
without revealing the maintainer's environment**. The
local-overrides pattern is the smallest disruption to the Ansible
workflow that achieves it.

## How forking would actually work

Suppose you wanted **chimebox-amiga**: same architectural shape,
but FS-UAE running AmigaOS instead of BasiliskII running Mac OS.
The minimum changes:

| Component | What changes |
|---|---|
| `pi/ansible/roles/basiliskii/` → `roles/fs-uae/` | Different package, different binary, different prefs file |
| `pi/ansible/roles/chimebox/templates/basiliskii-prefs.j2` | Replace with FS-UAE config template |
| `start.sh` | Replace `BasiliskII` exec line with `fs-uae` |
| `disk-prep/` | Replace Infinite Mac integration with whatever produces AmigaOS .adf files |
| `docs/shortlist.md` | Different curated software list (Amiga titles) |
| The "polite shutdown" mechanism in `factory-bless.sh` and `bedtime.sh` | FS-UAE accepts a different signal/IPC for "guest shutdown"; adapt |
| `docs/era-decisions.md` | A whole new doc justifying AmigaOS + FS-UAE + Workbench version |

What stays the same:

- Boot chain (getty → autologin → startx → start.sh → emulator)
- Supervisor loop + sentinel
- Snapshot/restore at the disk-image layer
- Panic-button daemon (works regardless of emulator)
- Audio role (ALSA below the emulator)
- Egress firewall (UID-based, emulator-agnostic)
- Outside world extfs pattern (if FS-UAE supports a host-folder
  mount, the shape is the same; if not, replace with shared-
  directory equivalent)
- Per-host config + discovery helper pattern
- Logging conventions
- Recovery layering

Most of chimebox is in the second category. The actual
emulator-specific bits are a small fraction of the codebase.

## What this doc isn't

- **The Mac-emulator architecture reference.** That's
  [`architecture.md`](./architecture.md).
- **A step-by-step "how to fork chimebox" guide.** This doc
  describes the *patterns* a forker should recognize and
  preserve; the actual fork is engineering work the forker
  does.
- **A complete list of every reusable bit.** It's the
  high-leverage patterns. Smaller utilities (the
  `chimebox_check_reachable` SSH helper, the `logger -t`
  double-log macro, the typed-phrase confirmation prompt
  in factory-bless) are equally reusable but documented in
  their own contexts.

The goal here is to make the *structure* of chimebox
legible enough that "do chimebox but for X" can be done
deliberately rather than re-invented from scratch.

## Related lessons

The myconfigs lessons folder has cross-project notes on
patterns chimebox uses. Particularly relevant for forkers:

- `supervisor-loop-sentinel-pattern.md` — pattern 2 in full
- `snapshot-disk-image-only-after-clean-unmount.md` — pattern 3
- `xbindkeys-vs-evdev-for-sdl2-kiosks.md` — pattern 4 motivation
- `nftables-meta-skuid-per-user-egress.md` — pattern 6 mechanism
- `discovery-helpers-for-per-host-config.md` — pattern 8 methodology
- `udev-systemd-mount-template-pattern.md` — pattern 9 plumbing
- `cron-output-invisible-without-logger.md` — pattern 10
- `evdev-hold-combos-need-autorepeat.md` — pattern 4 gotcha
- `ai-prose-fact-anchoring.md` — meta-note on writing this kind of
  doc with AI assistance

The full index is at `~/github/myconfigs/copilot/lessons/README.md`.
