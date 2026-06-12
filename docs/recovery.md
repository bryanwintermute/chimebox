# Recovery

A symptom-first triage guide for when chimebox isn't doing what you want.

## How to use this doc

You're probably reading this because **something is wrong and you
need it working again** — maybe a kid is staring at a frozen
screen, maybe the kiosk has been dark for two minutes, maybe SSH
just stopped responding. The goal here is to give you concrete
commands to run, in escalating order of intervention, so you
can stop the bleeding fast and figure out *why* later.

Each symptom section is structured the same way:

1. **What it looks like** — operator-visible cues
2. **Try first** — non-destructive diagnostics
3. **Recover** — in order of least-to-most destructive
4. **Save before destroying** — what to back up first if you
   know you're about to wipe state

If you're not sure which symptom matches, the
[decision tree](#decision-tree) below maps observable behaviors
to sections.

The doc assumes you can SSH into the Pi as the admin user
(default `admin`) with sudo. If SSH is the thing that's broken,
jump to [SSH does not work](#ssh-does-not-work).

## Decision tree

| What you see / experience | Go to |
|---|---|
| The Mac is showing an error dialog or appears frozen | [Mac is wedged](#mac-is-wedged) |
| The screen is black / nothing on the monitor | [Black screen](#black-screen) |
| The Mac boots, then immediately reboots, in a loop | [Kiosk crash-loop](#kiosk-crash-loop) |
| No sound from the kiosk | [No sound](#no-sound) |
| A USB stick is plugged in but the kid can't see it | [USB stick won't appear](#usb-stick-wont-appear) |
| SSH works but kiosk screen is dead / blank | [Kiosk gone but SSH alive](#kiosk-gone-but-ssh-alive) |
| SSH does not work | [SSH does not work](#ssh-does-not-work) |
| Internet works from the operator's session but not from the Mac | [Kiosk can't reach the internet (this is correct)](#kiosk-cant-reach-the-internet-this-is-correct) |
| A recent action just damaged the Mac | [Undo recent damage](#undo-recent-damage) |
| You've tried everything | [Re-image from scratch](#re-image-from-scratch) |

## Mac is wedged

### What it looks like

- Kid Pix shows "Sorry, a system error occurred" with a Type 10
  (or similar) dialog
- Mac UI frozen — clock stops, mouse doesn't change cursor
- Some app is "thinking" but you can hear the disk thrashing
  through the kiosk speaker
- The screen looks fine but no input does anything

### Try first

Press **`Ctrl + Alt + Shift + R`** on the kiosk keyboard or via
PiKVM virtual keyboard. This fires the panic-button daemon's
force-reset combo: `SIGKILL` to BasiliskII; supervisor respawns
within 1-2 seconds. **Does not touch System.dsk.**

Verify the combo fired (from your operator SSH session):

```sh
journalctl -u chimebox-panic-daemon --since '5 minutes ago' \
    | grep "combo 'force-reset' fired"
```

If you see a "fired" line, the combo worked. The Mac should be
re-launching in BasiliskII.

### If force-reset didn't fire

Check that the daemon currently has a keyboard to watch:

```sh
journalctl -u chimebox-panic-daemon -n 5 --no-pager \
    | grep -E "watching|went away"
```

You should see a recent `change: watching N device(s): eventN=...`
line. If you see `watching 0 device(s)`, no keyboard is reaching
the daemon — likely a USB device just disappeared (cable wiggle,
hub power-glitch, KVM swap). The daemon will auto re-pick-up
within ~1s when the device reappears via its udev hot-plug
monitor; if it doesn't, force a rescan:

```sh
sudo systemctl restart chimebox-panic-daemon
```

If still nothing fires when you press the combo: SSH in and
force-reset by hand:

```sh
# Polite first (gives Mac OS a chance to clean up).
sudo kill -TERM "$(pgrep -x BasiliskII)"
# If still wedged after 10 seconds:
sudo kill -KILL "$(pgrep -x BasiliskII)"
```

start.sh's supervisor loop respawns BasiliskII within 1-2s.

### If the Mac comes back wedged again immediately

It's likely the System.dsk has structural damage. Jump to
[Undo recent damage](#undo-recent-damage).

## Black screen

### What it looks like

The Pi's monitor (or PiKVM) shows nothing — black, or shows the
last-known frame frozen, or the Pi is dark with no HDMI signal.

### Is the Pi actually alive?

Test from your workstation:

```sh
ssh admin@chimebox-dev 'uptime; pgrep -ax BasiliskII'
```

| Result | Diagnosis | Go to |
|---|---|---|
| Uptime + BasiliskII pid | Pi alive, kiosk alive, display side broken | [HDMI / display issues](#hdmi--display-issues) |
| Uptime but no BasiliskII | Pi alive, kiosk dead | [Kiosk gone but SSH alive](#kiosk-gone-but-ssh-alive) |
| SSH connection refused / no route | Pi possibly dead, or network broken | [SSH does not work](#ssh-does-not-work) |

### A note on `boot-splash`

If `chimebox_boot_splash_enabled: true` (default), Linux's boot
text is suppressed — early-boot "Pi is starting" cues are
silenced. A "dark screen" for the first ~10s after power-on is
expected with the splash enabled. Wait at least 20-30 seconds
before assuming the Pi is dead.

### HDMI / display issues

Common causes on Pi 5:

- HDMI cable seated only partially
- Monitor expecting a video mode the Pi isn't producing
- `vc4-kms-v3d` overlay or `dtoverlay` config drift
- Display profile mismatch (e.g. `pillarbox` mode pinned at
  1920x1080 on a 4K monitor that's auto-scaling weirdly)

Check current display config:

```sh
ssh admin@chimebox-dev 'for s in /sys/class/drm/card*-HDMI*/status; do echo "$s: $(cat "$s")"; done'
sudo journalctl -b _COMM=Xorg --no-pager | tail -40
```

Verify the display profile in host_vars:

```sh
grep -h display_profile pi/ansible/host_vars/*/main.yml pi/ansible/group_vars/all.yml 2>/dev/null
```

If you change the profile, run `ansible-playbook --tags kiosk-x`
and restart the kiosk.

Lesson reference: see `~/github/myconfigs/copilot/lessons/pi5-x11-display.md`
for the Pi 5 / Xorg quirks that don't apply to earlier Pi models.

## Kiosk crash-loop

### What it looks like

The Mac chime plays, you see Mac OS partially come up, then it
restarts. Repeats every few seconds. SSH works.

### Diagnose

```sh
ssh admin@chimebox-dev 'sudo journalctl -u getty@tty1.service --since "5 minutes ago" --no-pager | tail -60'
ssh admin@chimebox-dev 'sudo -u chimebox ls -lh ~chimebox/chimebox/logs/'
```

start.sh's supervisor logs each BasiliskII launch and exit to
`~chimebox/chimebox/logs/`. A genuinely-crash-looping BasiliskII
will produce lots of log entries with the same crash signature.

Common causes:

| Cause | What to check |
|---|---|
| `System.dsk` corrupted | Compare SHA to factory: `sha256sum ~chimebox/chimebox/System.dsk ~chimebox/chimebox/factory.dsk` |
| `Quadra-650.rom` missing or wrong | `ls -la ~chimebox/chimebox/Quadra-650.rom` (should be 1.0M; if missing, re-push) |
| BasiliskII prefs corrupted | `cat ~chimebox/.config/BasiliskII/prefs` — should have rom/disk lines and reasonable settings |
| Out of memory / OOM | `dmesg \| grep -i "killed process"` and `free -h` |

If `start.sh` itself has given up after 10 fast failures, you'll
see this in the journal:

```
chimebox: BasiliskII has crashed 10 times in 60 seconds; giving up.
```

The supervisor stops trying. To kick it again after fixing the
underlying cause:

```sh
sudo systemctl restart getty@tty1.service
```

### Recover

If the System.dsk SHA looks suspicious (doesn't match factory,
and you didn't intend to modify it), try the rotating-snapshot
recovery first:

```sh
# from your workstation
./scripts/kid-reset.sh latest
```

If that's also broken, use factory-reset:

```sh
./scripts/factory-reset.sh    # type 'factory'
```

If even factory is gone or the disk images themselves are missing,
re-push from your workstation:

```sh
./scripts/push-disks.sh
```

## No sound

### What it looks like

The Mac chime should play at boot. The kid clicks a Kid Pix
stamp expecting "wackadoodle" and gets silence.

### Diagnose

```sh
ssh admin@chimebox-dev 'sudo chimebox-audio-list'
```

This helper enumerates all detected audio cards and shows the
current `/etc/asound.conf` routing + recent
`chimebox-audio-init` activity. The output suggests a tailored
`chimebox_audio_card` host_vars setting for the actual hardware.

```sh
ssh admin@chimebox-dev 'sudo journalctl -t chimebox-audio-init --since today --no-pager'
```

You'll see lines like:

```
chimebox-audio-init: detected ALSA cards: 0=vc4hdmi0 1=vc4hdmi1 2=MyUSBDAC
chimebox-audio-init: auto: selected USB audio card 2 (MyUSBDAC)
chimebox-audio-init: set MyUSBDAC:PCM to 60%
```

### Common causes

| Cause | Symptom | Fix |
|---|---|---|
| USB speaker plugged in *after* boot | The Mac chime played through HDMI, but the kid expected USB | Restart kiosk: `sudo systemctl restart getty@tty1.service`. Audio routing is established at boot (chimebox-audio-init runs `Before=getty@tty1`). |
| `chimebox_audio_card` set to a card that isn't present | Soft-fail log: `warning: card '...' not present at boot` | Update host_vars; or change to `auto`; re-run `ansible-playbook --tags audio` |
| HDMI card chosen but monitor has no speakers | Configured correctly, monitor's fault | Switch the configured card or attach a speaker |
| Pi 5 has no 3.5mm jack | "Where's the headphone port?" | There isn't one. Use USB DAC, HDMI, or a case audio add-on. |
| Volume at 0% | mute somewhere | `amixer -c <card> sset PCM 60% unmute` |

For more depth see the [audio role README](../pi/ansible/roles/audio/README.md)
and `~/github/myconfigs/copilot/lessons/alsa-route-by-card-name-not-index.md`.

## USB stick won't appear

### What it looks like

You plug a USB stick into the Pi expecting it to show up as a
folder inside the Mac's `Unix` volume. It doesn't.

### Diagnose

```sh
ssh admin@chimebox-dev 'sudo journalctl -t chimebox-usb --since "5 minutes ago" --no-pager'
ssh admin@chimebox-dev 'sudo ls -la /home/chimebox/outside-world/'
```

You should see `chimebox-usb: mounting /dev/sda1 -> ...` lines if
the udev rule fired.

### Common causes

| Cause | Symptom | Fix |
|---|---|---|
| Unsupported filesystem | Log: `unsupported fstype: btrfs` (or similar) | Allowed list is vfat/exfat/ntfs/ntfs3. Reformat the stick on a different machine. |
| Filesystem probe failed | Log: `blkid returned nothing after N retries` | Stick may have a corrupt or absent partition table. Try another machine. |
| Mount path appears but Mac doesn't refresh | sub-folder exists on host but invisible on Mac | Close and reopen the `Unix` window on the Mac, or restart the kiosk |
| `outside-world` role disabled | No sub-folder appears, no journal activity | Check `chimebox_outside_world_enabled` in group_vars/host_vars. |
| `chimebox_outside_world_readonly: true` and the kid tried to write | Stick mounts read-only; save attempts fail with a Mac dialog | Either set readonly=false or accept the constraint |

### Mac-side save failures into the USB sub-folder

Some Mac apps' "Save As..." silently fails when writing to an
extfs-mapped path. Kid Pix works fine. SimpleText, ResEdit, some
others do a write-then-rollback. This is a BasiliskII extfs
limitation, not a chimebox bug. Workaround: save to `Macintosh HD`
first, then drag the file to the USB sub-folder.

See `~/github/myconfigs/copilot/lessons/basiliskii-extfs-app-specific-saves.md`.

### Cross-mount drag errors

If the kid drags a file from one auto-mounted USB stick to another,
or across the `Kid's Drawings` boundary, the Mac may show
"disk error". The kernel returns EXDEV across mountpoints. Workaround:
**hold Option while dragging** to force-copy instead of move.

## Kiosk gone but SSH alive

### What it looks like

SSH works, but the kiosk screen is black / dark / unresponsive.
`pgrep BasiliskII` returns nothing.

### Diagnose

```sh
ssh admin@chimebox-dev 'sudo systemctl status getty@tty1.service'
ssh admin@chimebox-dev 'ls -l /run/chimebox-bedtime 2>&1'
```

### Common causes

| Cause | Telltale | Fix |
|---|---|---|
| `bedtime.sh` finished (kid's "bedtime") | `getty@tty1` stopped or inactive | `./scripts/wake-up.sh` |
| `bedtime.sh` interrupted; sentinel left armed | `/run/chimebox-bedtime` exists | `sudo rm -f /run/chimebox-bedtime && sudo systemctl restart getty@tty1.service` |
| `service-mode.sh` is currently active | A shell session is open elsewhere | Wait for it to close, or kill it |
| Supervisor gave up after 10 crash-loops | `start.sh` exit log in `~chimebox/chimebox/logs/` | Fix the underlying cause then `sudo systemctl restart getty@tty1.service` |
| `factory-bless.sh` interrupted partway | Sentinel armed + possibly stale state | Same as bedtime-interrupted: remove sentinel, restart getty |
| Kiosk was never started after boot | First-time provisioning incomplete | Re-run `ansible-playbook playbook.yml` |

## SSH does not work

### What it looks like

`ssh admin@chimebox-dev` hangs, times out, or returns
"Connection refused" / "No route to host".

### First: wait 3-4 minutes

If `chimebox_net_watchdog_enabled` is on (the default), the
`chimebox-net-watchdog.timer` is checking the gateway every 60s
and will attempt recovery (`nmcli connection up`, then
`systemctl restart NetworkManager`) after 3 consecutive failures.
Most transient wifi flakes self-heal within 3-4 minutes.

You can verify the watchdog is running from another chimebox or
once SSH returns:

```sh
systemctl list-timers chimebox-net-watchdog.timer
journalctl -t chimebox-net-watchdog --since '15 min ago'
```

### Try first

From your workstation:

```sh
ping -c3 chimebox-dev          # is the host reachable at all?
ssh -v admin@chimebox-dev      # verbose SSH; gets you the exact failure point
```

| ping result | Likely cause |
|---|---|
| `Host unreachable` / `No route` | Network layer broken (DNS, ARP, IP routing) |
| Replies but SSH times out | sshd dead or firewall blocking SSH |
| Replies and SSH gets connection-refused | Host up, sshd not listening |

### Recover

For a fully-bricked Pi from a network perspective, you have these
options ranked by least to most disruptive:

1. **The escape-to-tty combo** (if enabled in `host_vars`). If the
   Pi's screen is up (HDMI-attached monitor, JetKVM, or pikvm view)
   and the kiosk is showing the Mac, hold
   **`Ctrl+Alt+Shift+T` for 3 seconds**. This switches the active
   console from tty1 (X + BasiliskII) to tty2, where a getty
   login prompt is waiting. Log in as the admin user and debug
   from there. Return to the Mac with `Ctrl+Alt+F1` (works from a
   plain tty — no X grab to fight). This combo is **off by default
   for kid-handoff chimeboxes** (it puts an admin login one
   keystroke combo away from a kid); enable per-host via
   `chimebox_panic_button_escape_to_tty_enabled: true` on operator
   chimeboxes where the surface is acceptable.

2. **PiKVM / JetKVM / IPMI / out-of-band management.** If you set
   up a KVM for this chimebox, use it to interact with the
   keyboard. Note: without option (1) enabled, the KVM's keyboard
   input is still grabbed by X — you can SEE the Mac, but every
   key you press goes to BasiliskII. The KVM alone is not enough.

3. **Physically swap the boot media** to another machine and edit
   `/etc/wpa_supplicant/` or whatever's broken, then put it back.

4. **Re-image the boot media** and start fresh. See
   [Re-image from scratch](#re-image-from-scratch).

### If you can get a console shell

Common debug:

```sh
ip addr show
systemctl status ssh
systemctl status NetworkManager
journalctl -u NetworkManager --no-pager | tail -30
journalctl -u ssh --no-pager | tail -30
sudo nft list ruleset           # is something blocking inbound SSH?

# Manually retry the watchdog's recovery ladder:
sudo systemctl start chimebox-net-watchdog.service
journalctl -t chimebox-net-watchdog -n 20

# If wifi is just stuck, force a re-associate:
nmcli connection show --active
sudo nmcli connection up <name-from-above>

# Was this a POWER event? (under-voltage destabilises wifi)
vcgencmd get_throttled                       # 0x0 == clean
journalctl -t chimebox-pmic-watchdog --since '1 day ago'
```

If `chimebox-pmic-watchdog` shows under-voltage or `EXT5V_V` dips
around the time connectivity died, suspect the power supply (a
marginal or non-PD-aware adapter, or a multi-port charger sharing
current) before chasing the network stack. Swap to the official
Pi 5 27W PSU. See *Is my power supply actually adequate?* in
[operations.md](operations.md).

The `egress-firewall` role uses output-chain filtering only,
so it never blocks inbound SSH. If `nft list ruleset` shows
anything blocking inbound, that's outside chimebox's standard
config.

## Kiosk can't reach the internet (this is correct)

### What it looks like

Some app, test command, or curious operator tries to reach an
internet host from the kiosk user's perspective and it fails:

```sh
sudo -u chimebox curl --max-time 5 https://example.org/  # rc=28 timeout
```

### This is by design

The `egress-firewall` role uses nftables `meta skuid` to block
the `chimebox` user from reaching off-LAN destinations. The
operator (admin user) is fully unaffected.

Verify it's working as designed:

```sh
sudo journalctl -k --since '10 minutes ago' | grep chimebox-egress-drop
sudo nft list table inet chimebox_egress
```

The "drop log" will show the SRC/DST of each blocked packet —
useful evidence the firewall is doing exactly its job.

If you genuinely want the kiosk user to reach the internet
(unusual, but for testing): set `chimebox_egress_firewall_enabled: false`
in host_vars and re-run `--tags egress-firewall`. Don't do this
on a kid-handoff chimebox.

## Undo recent damage

### Damage spectrum, least to most destructive recovery

1. **App-level crash** (Type 10, frozen Finder, etc.) →
   `Ctrl+Alt+Shift+R` force-reset. No data loss.
2. **Recent unintended file changes the kid made** →
   restore from last good snapshot via
   `Ctrl+Alt+Shift+Z` (hold 1.5s) or `./scripts/kid-reset.sh latest`.
   **Loses any work since the most recent rotating snapshot.**
3. **Snapshots themselves are corrupted or contain the damage** →
   `./scripts/factory-reset.sh` to the operator-blessed baseline.
   **Loses everything since the last factory bless** (unless
   saved to `outside-world/Kid's Drawings/`).
4. **Everything on the Pi is suspect** → re-image. See
   [Re-image from scratch](#re-image-from-scratch).

### Save what you can first

Before any destructive recovery, copy out anything you care
about that isn't on outside-world (which is host-side and
survives even re-image of the Pi OS):

```sh
# Quick "save what's there" before factory-reset or kid-reset
mkdir -p /tmp/chimebox-rescue
scp admin@chimebox-dev:/home/chimebox/chimebox/System.dsk \
    /tmp/chimebox-rescue/System.dsk.$(date +%Y%m%d-%H%M%S).pre-reset
```

Note: copying `System.dsk` while BasiliskII has it open will
capture a "dirty" filesystem (see
`~/github/myconfigs/copilot/lessons/snapshot-disk-image-only-after-clean-unmount.md`).
That's fine for "save in case we need it later"; it's not fine
for "this is my new factory baseline." If you want a clean
copy, run `./scripts/factory-bless.sh` first (which politely
shuts down Mac OS, then snapshots).

## Re-image from scratch

You've exhausted in-place recovery. The boot media (SD or NVMe)
needs to be re-flashed and the Pi re-provisioned.

### Before you wipe

These are the things worth saving off the dying chimebox if you
can still access them:

| Artifact | Path | Why save it |
|---|---|---|
| Factory baseline | `~chimebox/chimebox/factory.dsk` | Your operator-blessed curated state. Re-blessing from a fresh install means re-curating. |
| Rotating snapshots | `~chimebox/chimebox/snapshots/` | If you trust any of them, they're recovery options |
| Outside World contents | `~chimebox/outside-world/` | Kid's Drawings, anything she saved here. **Survives re-image of the Pi OS** because it's just files on the FS, but if the boot media itself is dying, save it anyway. |
| Host config | `pi/ansible/host_vars/<host>/local.yml` | This is gitignored on your workstation; the values inside (LAN CIDR, audio card name, etc.) are needed to re-provision |
| The Pi's hostname + IP | n/a | Note so you can re-add SSH config / DNS entry |

Save them via `scp`:

```sh
scp -r admin@chimebox-dev:/home/chimebox/chimebox/ /tmp/chimebox-rescue/
scp -r admin@chimebox-dev:/home/chimebox/outside-world/ /tmp/chimebox-rescue/
```

### The re-image itself

See [`pi/SETUP.md`](../pi/SETUP.md) for the full step-by-step.
At a high level:

1. Flash fresh Raspberry Pi OS 64-bit Lite to your boot media
   via Pi Imager
2. First-boot config (hostname, admin user, SSH key, Wi-Fi)
3. Clone this repo on your workstation
4. Set host_vars (use the values you saved above)
5. Run `ansible-playbook playbook.yml --limit <host>`
6. `./scripts/push-disks.sh` to install the ROM + System.dsk
7. (Optional) `./scripts/factory-bless.sh` to bless the curated
   state — or do another round of Desktop curation if you want
   to start fresh

### After re-image: restore Outside World

If you saved `outside-world/`, just put it back:

```sh
scp -r /tmp/chimebox-rescue/outside-world/ admin@chimebox-dev:/home/chimebox/
ssh admin@chimebox-dev 'sudo chown -R chimebox:chimebox /home/chimebox/outside-world'
```

Kid's Drawings is back. The kid's session memory is back via
`OpenFolderListDF`. The factory baseline you might re-bless from
the new install, OR scp it back too if you saved it:

```sh
scp /tmp/chimebox-rescue/factory.dsk admin@chimebox-dev:/tmp/
ssh admin@chimebox-dev 'sudo install -o chimebox -g chimebox -m 0440 /tmp/factory.dsk /home/chimebox/chimebox/factory.dsk; sudo rm /tmp/factory.dsk'
```

Then `./scripts/factory-reset.sh` (or wait for the kid to want
a reset) and the new install lands on your old curated state.

## Quick technical reference

### Where logs live

| Component | Journal tag |
|---|---|
| Kiosk supervisor (start.sh) | `~chimebox/chimebox/logs/` (file-based; per-launch) |
| BasiliskII | included in start.sh log |
| Panic-button daemon | `journalctl -u chimebox-panic-daemon` |
| Panic-button action scripts | `journalctl -t chimebox-force-reset -t chimebox-reset-latest -t chimebox-emergency-stop` |
| Snapshot/reset helpers | `journalctl -t chimebox-snapshot -t chimebox-reset` |
| Audio init | `journalctl -t chimebox-audio-init` |
| Outside-world USB mount | `journalctl -t chimebox-usb` |
| Egress firewall drops | `journalctl -k --grep chimebox-egress-drop` |
| Boot splash / Plymouth | `journalctl -u plymouth*` |
| Argon One V3 fan (opt-in) | `systemctl status argononed.service` |

### Key systemd units

| Unit | Role |
|---|---|
| `getty@tty1.service` | Runs the kiosk autologin chain (start.sh → BasiliskII). **This is the v1 kiosk supervisor.** |
| `chimebox-panic-daemon.service` | Below-X evdev keystroke catcher (panic-button) |
| `chimebox-audio-init.service` | Boot-time ALSA routing + volume |
| `chimebox-egress.service` | Per-user nftables egress block |
| `chimebox-mount@<dev>.service` | Per-USB-stick auto-mount instance (template unit, fired by udev) |
| `chimebox.service` | Installed but **disabled**. Scaffold for a future v2 supervisor; ignore in v1. |

### Key files on the Pi

| Path | Purpose |
|---|---|
| `/home/chimebox/chimebox/Quadra-650.rom` | ROM (user-supplied; never in git) |
| `/home/chimebox/chimebox/System.dsk` | Boot disk; chimebox user can write |
| `/home/chimebox/chimebox/InfiniteHD.dsk` | Library; chmod 0440 read-only |
| `/home/chimebox/chimebox/factory.dsk` | Operator-blessed baseline; chmod 0440 |
| `/home/chimebox/chimebox/snapshots/` | Rotating snapshots (cron-driven) |
| `/home/chimebox/chimebox/logs/` | start.sh per-launch logs |
| `/home/chimebox/outside-world/` | extfs root; mounted as "Unix" volume on the Mac |
| `/home/chimebox/.config/BasiliskII/prefs` | BasiliskII config |
| `/etc/asound.conf` | ALSA default sink (managed by chimebox-audio-init) |
| `/etc/nftables.d/chimebox-egress.nft` | Egress firewall ruleset |
| `/run/chimebox-bedtime` | Sentinel file; existence pauses kiosk supervisor |

### One-liner triage commands

```sh
# Big picture: is everything sane?
ssh admin@HOST 'uptime; sudo systemctl is-active getty@tty1 chimebox-panic-daemon chimebox-audio-init chimebox-egress.service; pgrep -ax BasiliskII'

# Recent failures across all chimebox components
ssh admin@HOST 'sudo journalctl --since "1 hour ago" -p err --no-pager | head -40'

# Disk space
ssh admin@HOST 'df -h /'

# Temperatures (Pi 5 throttles around 80°C)
ssh admin@HOST 'vcgencmd measure_temp && vcgencmd get_throttled'

# Mac processes
ssh admin@HOST 'pgrep -af BasiliskII; pgrep -af Xorg; pgrep -af start.sh'
```

## Reporting a bug

If a chimebox failure isn't something you can fix from this
doc, please file a GitHub issue with:

1. **Symptom** — what the operator sees
2. **Pi model + OS version** — `cat /etc/os-release` and
   `pinout` output
3. **Display profile** — `chimebox_display_profile` value
4. **Relevant role state** — output of `systemctl is-active` for
   the units you suspect
5. **Targeted journal output** — `journalctl -t <tag> --since
   '30 minutes ago'` for the relevant tags from the
   [Where logs live](#where-logs-live) table
6. **What you tried already** — kid-reset? factory-reset?
   re-image? Specific recovery sections of this doc?

**Please do not attach:**

- ROM files or copyrighted disk images
- `System.dsk` / `factory.dsk` (large, may contain kid drawings
  or other personal data)
- Photos of children or any kid-identifying info
- Personal home network details (LAN CIDR, real hostnames if
  they reveal location/setup)

Privacy-sensitive details can be redacted before pasting, or
omitted entirely if not relevant.

## What this doc isn't

- **An install guide.** That's [`pi/SETUP.md`](../pi/SETUP.md).
- **A day-to-day operations guide.** That's [`operations.md`](./operations.md).
- **An architecture reference.** That's [`architecture.md`](./architecture.md)
  and [`architecture-patterns.md`](./architecture-patterns.md).
- **A list of every command.** Individual role READMEs go deeper
  on their specific subject; this doc cross-references rather
  than duplicating.

The goal here is **fastest path back to a working kiosk** when
something has gone wrong. Diagnosis depth, design rationale,
and "why does it work this way" belong elsewhere.
