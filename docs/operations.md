# Operations

Day-2 operations guide: the routines and workflows for running a
chimebox once it's set up. Audience: the maintainer, and any
contributor running their own chimebox.

For "something is broken" troubleshooting, see
[`recovery.md`](./recovery.md). For initial install,
see [`pi/SETUP.md`](../pi/SETUP.md).

## The daily rhythm

The two most common operations on a working chimebox are
**putting it to bed** at the end of a session and **waking it
up** for the next one. The Pi stays powered between sessions
(~3W idle) so wake-up is fast.

### End of session: `scripts/bedtime.sh`

Gracefully wind down the kiosk. Asks Mac OS to shut down via
its standard "Shut Down?" dialog; if the kid clicks it the
script proceeds immediately, otherwise it waits N minutes then
forces the kiosk down.

```sh
./scripts/bedtime.sh              # default 5-minute warning
./scripts/bedtime.sh 10           # 10-minute warning
./scripts/bedtime.sh 0            # immediate (still graceful)
```

The "graceful" part is important: bedtime sends `SIGTERM` to
BasiliskII, which Mac OS interprets as a Special > Shut Down
request. The kid sees the standard dialog and can click "Shut
Down" to save their state cleanly.

End state: Pi is up, but `getty@tty1` is stopped — screen is
blank, no kiosk processes running. The Pi sits at ~3W until
wake-up.

### Start of session: `scripts/wake-up.sh`

Restarts the kiosk after bedtime. Clears any stale sentinel
file, starts `getty@tty1`, and the autologin chain takes
over from there.

```sh
./scripts/wake-up.sh
```

Within ~5-10 seconds you should see the Mac chime and Desktop
appear on the kiosk screen.

### Why not just power off the Pi at night?

Two reasons:
1. The kiosk user can't run `systemctl poweroff` without a
   sudoers entry we haven't added (avoidable security
   surface).
2. Leaving the Pi up means wake-up is one SSH command away
   rather than a power-button press, which matters if the
   chimebox is somewhere inconvenient.

If you do want full shutdown / power-off, do it manually from
your admin SSH session:

```sh
ssh admin@chimebox-dev 'sudo systemctl poweroff'
```

Then physically power-cycle when you want it back.

## Routine maintenance

### Take a manual snapshot

Before letting the kid try something experimental, capture
current state:

```sh
./scripts/snapshot-now.sh
```

Writes a `manual-YYYY-MM-DD-HHMMSS.dsk` to
`~chimebox/chimebox/snapshots/`. Doesn't disturb the kiosk;
the snapshot is taken via `cp` against the live `System.dsk`
(so it's a "running snapshot" with the HFS dirty bit set, but
that's fine for ad-hoc restore points). For a clean snapshot
that survives factory-reset cycles, use `factory-bless.sh`
instead.

### Restore from a snapshot: `scripts/kid-reset.sh`

When something went wrong and you want to go back:

```sh
./scripts/kid-reset.sh                 # interactive (list + pick)
./scripts/kid-reset.sh latest          # most recent rotating snapshot
./scripts/kid-reset.sh daily-2026-05-12.dsk    # by name
```

Stops the kiosk briefly, copies the chosen snapshot over
System.dsk, restarts the kiosk. ~30 seconds end-to-end.

The kid-reset path is non-destructive to **other** snapshots —
it only overwrites System.dsk. The full snapshot history
remains.

### Restore from a snapshot via on-kiosk keyboard

If you don't have your workstation handy and the kiosk is
visible, the panic-daemon's `kid-reset` combo does the same
thing. Hold **`Ctrl + Alt + Shift + Z`** for 1.5 seconds.

This combo is opt-in per host (set
`chimebox_panic_button_kid_reset_enabled: true` in host_vars).

The hold-time gate exists so a kid randomly mashing the
keyboard can't trigger destructive recovery — see the
[panic-button role README](../pi/ansible/roles/panic-button/README.md).

### Bless the curated state: `scripts/factory-bless.sh`

After a curation milestone (e.g., kid-shortlist Desktop setup
is exactly the way you want long-term), capture it as the
factory baseline:

```sh
./scripts/factory-bless.sh    # type 'bless' to confirm
```

This script does a **polite shutdown** of Mac OS first: SIGTERMs
BasiliskII (which displays the standard shutdown dialog on the
kiosk screen), waits for you to click "Shut Down", then captures
System.dsk with the HFS clean-unmount flag properly set.

**You'll need to be at the kiosk screen** (physical monitor or
PiKVM) to click "Shut Down" when the dialog appears. The script
waits up to 5 minutes. If you don't click in that time the
script aborts cleanly — your existing factory.dsk is untouched.

### Roll back to factory: `scripts/factory-reset.sh`

When even rotating snapshots can't help (or when you want a
true "reset to as-shipped" wipe):

```sh
./scripts/factory-reset.sh    # type 'factory' to confirm
```

Restores System.dsk from `factory.dsk`. **Loses everything**
since the last factory-bless — Tier S layout, drawings on the
kiosk's own filesystem, etc. Drawings saved to the
`outside-world/Kid's Drawings/` folder survive (they live on
the host FS, not in System.dsk).

There is intentionally **no factory-reset hotkey**. Factory
rollback can lose arbitrary state; it requires the deliberate
SSH path with a typed-phrase confirm.

### What snapshots exist right now?

```sh
ssh admin@HOST 'sudo /usr/local/sbin/chimebox-reset list'
```

Output shows the rotating snapshots dir + factory baseline
status.

The retention policy is:
- **Daily** (auto-fired by cron at 03:17 local time): keep last
  `chimebox_snapshot_keep_daily` (default 7)
- **Weekly** (auto-chained by daily on Sunday): keep last
  `chimebox_snapshot_keep_weekly` (default 4)
- **Manual** (`snapshot-now.sh`): retained forever — clean up
  by hand if they accumulate
- **Factory** (`factory-bless.sh`): exactly one, re-blessing
  replaces

## Updating the system

### Update the disks (after disk-prep)

If you re-ran `disk-prep/` on your workstation (new library
contents, new ROM, etc.), push the results to the Pi:

```sh
./scripts/push-disks.sh
```

Idempotent rsync. Only changed bytes are sent. Push-disks
does NOT stop the kiosk first — for the safest "fresh install"
flow that includes kiosk stop/restart, see
[issue #7](https://github.com/bryanwintermute/chimebox/issues/7).
For now if you want a clean swap, manually:

```sh
ssh admin@HOST 'sudo systemctl stop getty@tty1.service'
./scripts/push-disks.sh
ssh admin@HOST 'sudo systemctl start getty@tty1.service'
```

### Update Ansible config

After pulling new chimebox commits:

```sh
cd pi/ansible
ansible-playbook playbook.yml --limit <host>
```

The playbook is idempotent — re-running a host that's already
provisioned does nothing unless something has changed (in
which case only the changed bits are applied).

Common per-role re-runs:

```sh
# Audio config change (e.g., new chimebox_audio_card setting)
ansible-playbook playbook.yml --limit <host> --tags audio

# Snapshot retention or related changes
ansible-playbook playbook.yml --limit <host> --tags persistence

# New panic-daemon combo
ansible-playbook playbook.yml --limit <host> --tags panic-button

# Firewall rules
ansible-playbook playbook.yml --limit <host> --tags egress-firewall
```

The full tag list is in `playbook.yml`.

### Add a new app to the library

This requires re-running `disk-prep/` on your workstation
(it's not a runtime operation on the Pi). High-level:

1. Edit `disk-prep/`'s manifest to include the new title
   (or rely on the Infinite Mac upstream having the title)
2. Re-run `disk-prep/prep.sh` (or just `1-build-library.sh`
   if everything else is current)
3. `scripts/push-disks.sh` to push the new `InfiniteHD.dsk`
4. Restart the kiosk
5. (Optional) Drag the new app's icon onto the kid's Desktop
6. (Optional) `scripts/factory-bless.sh` if you want this in
   the factory baseline

## Maintenance windows

### Open a shell on the Pi while the kiosk is stopped

```sh
./scripts/service-mode.sh
```

Stops the kiosk, opens an interactive shell. When you exit the
shell, the kiosk auto-resumes. Use for `apt update`, log
inspection, or hands-on debugging.

### Switch input mode (physical vs PiKVM)

The kiosk's mouse-handling mode depends on whether you're using
a physical mouse (relative motion, BasiliskII captures the
pointer) or a remote pointer like PiKVM/VNC (absolute motion).

```sh
./scripts/mouse-mode.sh grab      # physical mouse mode
./scripts/mouse-mode.sh absolute  # PiKVM / VNC mode
```

The display profile is similarly per-mode:
- `pillarbox` (kid use, physical hardware): 1920x1080 X canvas
  with a centered 1440x1080 Mac window, black bars around
- `matched-stretched` (dev / PiKVM use): X canvas matches the
  Mac window size, full-screen stretched

Switch via `chimebox_display_profile` in host_vars and re-run
`--tags kiosk-x`.

## Inspection and observability

### What's the kiosk been doing today?

```sh
ssh admin@HOST 'sudo journalctl --since today --no-pager' | less
```

The chimebox-specific tags worth grepping:

| Tag | What |
|---|---|
| `chimebox-snapshot` | Daily/weekly/manual snapshot fires and retention |
| `chimebox-reset` | Restore operations (latest, factory, named) |
| `chimebox-panic-daemon` | Combos that fired and to what action |
| `chimebox-force-reset` | Each SIGKILL of BasiliskII via the R combo |
| `chimebox-reset-latest` | Each kid-reset combo fire (Z) |
| `chimebox-emergency-stop` | Each Q combo fire (opt-in) |
| `chimebox-audio-init` | Boot-time audio routing |
| `chimebox-usb` | USB stick mount/unmount |
| `chimebox-egress-drop` | Kiosk user's blocked outbound packets (kernel log; use `journalctl -k`) |

Examples:

```sh
# Did the snapshot cron fire last night?
journalctl -t chimebox-snapshot --since '24 hours ago'

# Has the panic-daemon fired any combos this session?
journalctl -t chimebox-panic-daemon --since today | grep fired

# What got blocked by the egress firewall?
journalctl -k --since today | grep chimebox-egress-drop
```

### Has the daily snapshot been running?

The cron runs at 03:17 local. Check:

```sh
ssh admin@HOST 'journalctl -t chimebox-snapshot --since "8 hours ago" --no-pager | tail -8'
```

You should see entries like:

```
chimebox-snapshot: daily: snapshotting .../System.dsk -> .../daily-2026-05-14.dsk
chimebox-snapshot: daily: wrote .../daily-2026-05-14.dsk (104857600 bytes)
chimebox-snapshot: daily: retention prunes 1 old snapshot(s) (keep=7)
chimebox-snapshot:   prune .../daily-2026-05-07.dsk
```

If you see nothing: the cron isn't firing. Check
`crontab -u root -l` to confirm the entry exists, and
`systemctl status cron` to confirm the daemon is alive.

### What's the kid been saving?

```sh
ssh admin@HOST 'sudo ls -lh /home/chimebox/outside-world/Kid\\'\\''s\\ Drawings/'
```

(The apostrophe escaping is awkward; you can also just enter
the shell with `service-mode.sh` and inspect directly.)

To pull a copy of her drawings to your workstation:

```sh
mkdir -p ~/chimebox-drawings/$(date +%Y-%m-%d)
scp -r admin@HOST:'/home/chimebox/outside-world/Kid\\'\\''s\\ Drawings'/* \
    ~/chimebox-drawings/$(date +%Y-%m-%d)/
```

### Storage check

```sh
ssh admin@HOST 'df -h / && du -sh /home/chimebox/chimebox/{snapshots,logs} /home/chimebox/outside-world/'
```

Useful for noticing if snapshots are taking unexpectedly much
space (cron retention misconfigured? large System.dsk?) or if
the kid has been hoarding things.

### Temperature and throttling (Pi 5)

```sh
ssh admin@HOST 'vcgencmd measure_temp && vcgencmd get_throttled'
```

Healthy looks like:
```
temp=47.0'C
throttled=0x0
```

Throttled flag bits:
- `0x1` = under-voltage right now
- `0x10000` = under-voltage occurred since boot (often
  transient USB-C PD)
- `0x4` = currently throttled
- `0x40000` = throttled since boot

If you consistently see live throttling (`0x4`), the Pi is
running hot or under-powered. Check cooling (Argon One V3 fan
daemon running?), monitor `vcgencmd measure_temp` over time,
or use a better power supply.

## Common workflows ("I want to...")

### I want to add a new app to the kid's Desktop

1. Make sure the app is in `Infinite HD` (re-run disk-prep
   if you need a new title)
2. From the kiosk screen, open `Infinite HD` to find the app
3. Cmd+Option-drag (= Win+Alt+drag on a Windows keyboard) the
   app's icon to the Desktop to create an alias
4. Rename the alias (strip " alias" suffix)
5. (Optional) `scripts/factory-bless.sh` if you want this in
   the rollback baseline

### I want to remove an app from the Desktop

1. Drag the alias to Trash (or select + Cmd+Delete)
2. Empty Trash (Special > Empty Trash)
3. (Optional) `scripts/factory-bless.sh`

### I want to undo something the kid just did

```sh
./scripts/kid-reset.sh latest
```

Or on the kiosk keyboard: `Ctrl+Alt+Shift+Z` (hold 1.5s).

### I want to test something risky without affecting the kid's state

```sh
./scripts/snapshot-now.sh        # capture pre-risk state
# ... do the risky thing ...
./scripts/kid-reset.sh manual-2026-05-14-181542.dsk    # revert
```

### I want to update the OS / apt packages

`apt update && apt upgrade` doesn't run on the kiosk
automatically. Run it manually when you want:

```sh
./scripts/service-mode.sh
# In the opened shell:
sudo apt update && sudo apt upgrade
exit
# Kiosk resumes
```

Re-running the Ansible playbook will also do `apt` updates
on the roles that touch packages (most of them).

### I want to put the chimebox somewhere else / change LANs

The `chimebox_lan_cidrs` host_var controls what LAN the kiosk
user is allowed to reach. If you move the Pi to a different
network:

1. Update `pi/ansible/host_vars/<host>/local.yml` (gitignored)
   to match the new LAN's CIDR
2. Re-run `ansible-playbook playbook.yml --limit <host>
   --tags egress-firewall`
3. The kiosk user can now reach the new LAN; the old CIDR is
   blocked

### I want to physically move the Pi without losing kid drawings

Drawings in `outside-world/Kid's Drawings/` live on the host
filesystem. They survive everything except wiping the SD/NVMe.

If you're moving the Pi to new boot media, save the
`outside-world/` directory first — see the [recovery doc's
re-image section](./recovery.md#re-image-from-scratch) for the
save-then-restore commands.

### I want to disable the egress firewall temporarily

(Unusual; the firewall is part of the kid-handoff posture.
But for one-off testing where you need the kiosk user to reach
the internet:)

```sh
ssh admin@HOST 'sudo systemctl stop chimebox-egress.service'
# Do your testing.
ssh admin@HOST 'sudo systemctl start chimebox-egress.service'
```

Don't `disable` (vs `stop`) it — that'd leave the firewall off
across reboots.

### I want to check what the kid pressed for keyboard combos

```sh
ssh admin@HOST 'sudo journalctl -u chimebox-panic-daemon \
    --since today --no-pager | grep -E "fired|combo"'
```

You'll see every panic-button combo that fired and to what
action. Useful if you suspect she stumbled into a combo
accidentally.

### I'm working on the chimebox and want a local shell on-screen

If the host you're maintaining has
`chimebox_panic_button_escape_to_tty_enabled: true` set,
**hold `Ctrl+Alt+Shift+T` for 3 seconds** on the chimebox keyboard
(or via the KVM's virtual keyboard) to switch the active console
to tty2, where a normal getty login prompt is waiting. The Mac
keeps running on tty1 — return to it with **`Ctrl+Alt+F1`**.

This is the **out-of-band recovery path** for when the Pi's
network is dead but the kiosk is still running: without it, the
JetKVM/HDMI view shows the Mac but X grabs every keystroke,
leaving you no way to reach a shell short of a power-cycle.

The combo is opt-in (`host_vars`) precisely because it puts an
admin login one keystroke away. Default OFF for kid-handoff
chimeboxes; turn ON for dev/operator chimeboxes where the surface
is acceptable.

For the auto-recovery path that fixes most wifi flakes without
operator intervention, see the `net-watchdog` role
(enabled by default).

### I want my chimebox to be more reliable on wifi (or just prefer wired)

For a kid-handoff chimebox, wired Ethernet is strongly
recommended. Wifi is fine for development and the `net-watchdog`
role catches most transient flakes automatically, but a sustained
wifi outage on a wifi-only chimebox leaves you operator-locked-out
unless `escape-to-tty` is enabled. Wired ethernet sidesteps the
whole class of failure.

If wired isn't an option, leave `chimebox_net_watchdog_enabled`
on (the default) and consider enabling `escape-to-tty` so you
have a recovery path when watchdog can't help.

### Is my power supply actually adequate?

The Pi 5 is fussy about power: a marginal or non-PD-aware supply
(or a multi-port charger whose other ports steal current) causes
brief under-voltage dips that destabilise wifi and, in the worst
case, corrupt a disk write. Use the **official 27W USB-C PD
supply** for any kid-handoff chimebox.

The `pmic-watchdog` role (enabled by default) makes this
observable: it logs under-voltage / throttling events and 5V-rail
dips to the journal, with timestamps, so you can tell whether a
supply is healthy instead of guessing.

```sh
# A snapshot right now:
vcgencmd get_throttled          # 0x0 == perfect; bit 16/18 set == UV/throttle has occurred
vcgencmd pmic_read_adc EXT5V_V  # the input rail; should sit comfortably above ~4.9V

# What the watchdog has seen (persists across reboots, per the journal role):
journalctl -t chimebox-pmic-watchdog --since '1 day ago'
```

To validate a supply swap: run on the suspect supply for a day,
note any under-voltage lines, swap to the candidate, and confirm
the warnings stop and every hourly heartbeat reads `clean`.

## Routine cadence I'd suggest

| Cadence | Action |
|---|---|
| End of every session | `bedtime.sh` (let the kid see the proper shutdown dialog) |
| Start of every session | `wake-up.sh` |
| Before any risky experimentation | `snapshot-now.sh` |
| After meaningful curation changes | `factory-bless.sh` |
| Weekly (any time) | Skim `journalctl --since '7 days ago' -p warn` for surprises |
| Monthly | `apt upgrade` via service-mode |
| Quarterly or after big changes | Re-pull drawings to your workstation (backup) |
| Annually | Re-think the Tier S list — kid's taste/abilities have grown |

## What this doc isn't

- **A failure-recovery guide.** See [`recovery.md`](./recovery.md).
- **An install guide.** See [`pi/SETUP.md`](../pi/SETUP.md).
- **Per-role deep dives.** See `pi/ansible/roles/*/README.md`.
- **Architecture reference.** See [`architecture.md`](./architecture.md)
  and [`architecture-patterns.md`](./architecture-patterns.md).

The goal here is **routine operation of a working chimebox**:
the rhythm of running it day-to-day, the workflows that come
up, the inspections worth doing periodically. When something
breaks, jump to recovery.md.
