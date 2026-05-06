# role: outside-world

Bridges the chimebox kiosk to physical media: a host directory shows up
on the Mac OS desktop as a folder (via BasiliskII's `extfs`), and any
USB stick plugged into the Pi auto-mounts as a sub-folder inside it.
The kid plugs a stick in, walks back to the Mac, and finds new content
already visible.

## What it builds

| Component | Purpose |
|---|---|
| `~chimebox/outside-world/` host directory | Root that BasiliskII's `extfs` exposes to Mac OS |
| extfs entry in `basiliskii-prefs.j2` | Owned by the `chimebox` role; conditional on `chimebox_outside_world_enabled` |
| `/etc/udev/rules.d/99-chimebox-usb.rules` | Fires `chimebox-usb-mount@<dev>.service` for any USB block-device partition |
| `/etc/systemd/system/chimebox-usb-mount@.service` | Templated systemd unit; mounts on start, unmounts on stop (BindsTo to `dev-*.device`) |
| `/usr/local/sbin/chimebox-usb-helper` | Bash script that does probe / sanitize / mount / unmount with retries |
| `ntfs-3g`, `exfatprogs` packages | Filesystem support beyond stock kernel |

## Mount layout

USB sticks land at:

```
~chimebox/outside-world/USB-<safe-label>-<uuid8>/
```

`<safe-label>` is the volume label sanitized to `[A-Za-z0-9._-]`,
collapsed to a max of 24 chars. `<uuid8>` is the first 8 chars of the
partition's UUID, so two unlabeled sticks can't collide. If both label
and UUID are missing (very rare), we fall back to the kernel device
name (`USB-sda1`).

## Allowed filesystems

`vfat`, `exfat`, `ntfs`, `ntfs3`. Anything else is logged and ignored.
This is intentional: a USB stick formatted ext4 or HFS+ on a kid's
emulator-bridge is almost certainly a misconfiguration, not a use
case worth supporting.

## Mount options

Always: `nosuid,nodev,noexec` — defense in depth. Removable media
should never be a vector for setuid binaries or device nodes.

For FAT family: `uid=<chimebox>,gid=<chimebox>,umask=0022,iocharset=utf8,sync,dirsync` —
ownership pinned to the kiosk user so the emulator can read+write,
plus `sync,dirsync` to shrink (NOT eliminate) the corruption window
if the stick gets yanked mid-write.

For exFAT/NTFS: same uid/gid/umask without the sync options (they're
handled differently or are a no-op on those drivers).

When `chimebox_outside_world_readonly: true` is set in host_vars, all
mounts get `ro` appended.

## Variables

| Var | Default | Effect |
|---|---|---|
| `chimebox_outside_world_enabled` | `true` | Master switch |
| `chimebox_outside_world_dir` | `~chimebox/outside-world` | Mount root |
| `chimebox_outside_world_readonly` | `false` | Force USB mounts read-only |
| `chimebox_outside_world_allowed_fstypes` | `[vfat, exfat, ntfs, ntfs3]` | Filesystem allowlist |
| `chimebox_outside_world_mount_prefix` | `USB-` | Sub-directory name prefix |

## Known limitations and gotchas

### Save quirks: some Mac apps work, some don't

**Kid Pix saves fine** into the Outside World volume. **SimpleText
silently fails** — the save dialog dismisses, no error appears, but
the file isn't there afterwards. We have not yet fully classified
which apps fall into each bucket.

Validated on chimebox-dev with `inotifywait` watching the SimpleText
case:

```
CREATE simpletext-test         <- file created
MODIFY simpletext-test (xN)    <- data written
CREATE/MODIFY .finf/simpletext-test
CREATE/MODIFY .rsrc/simpletext-test
DELETE .finf/simpletext-test   <- !!! something rolls back
DELETE .rsrc/simpletext-test
DELETE simpletext-test         <- file removed; no app error shown
```

The full data + finf + rsrc fork files are written to disk, and
then atomically deleted. The chimebox user can write all three
fork files directly via Linux without any error, so this is not
a host-filesystem permission problem. It's a BasiliskII extfs-
layer issue triggered by something specific to certain apps' save
protocols (likely the Translation Manager / Document Save flow
that SimpleText uses, vs. the more direct Open/Write/Close that
apps like Kid Pix use).

Pinpointing the failing syscall and fixing it requires source-level
work on BasiliskII; that's on the backlog as a separate task.

**Workarounds for affected apps:**

- **Save to Macintosh HD first**, then drag/copy the file into
  Outside World. Cross-volume copies use the open+read+write+close
  code path that Kid Pix-style apps already use directly, and that
  path works reliably.
- **Copy files in from the Pi side** (e.g., `scp` to
  `/home/chimebox/outside-world/`) and they show up on the Mac.
- **Edit existing files in place** on the Mac (open existing file,
  edit, save back to same name) appears to work — only fresh
  Save-As-into-extfs is affected.
- For new content, **prefer apps that save reliably**. Kid Pix is
  confirmed working; a comprehensive per-app compatibility matrix
  is tracked as future work.

### Cross-mount move = "disk error"

When the Mac user **drags a file within the Unix volume** from
the Outside World root (Pi-local, ext4) to a USB sub-folder
(exfat/ntfs/etc.), Mac OS reports:

> You cannot move "<file>" to the folder "<folder>", because a
> disk error occurred.

Cause: classic Mac OS treats drag-within-volume as **move**
(rename), and Linux's `rename()` syscall returns `EXDEV` across
mount-point boundaries — which is exactly what's happening here:
the source is on ext4, the destination is on the USB stick's
exfat. BasiliskII surfaces the EXDEV up to the Mac as a generic
"disk error" without falling back to copy-then-delete the way
Linux's `mv` does.

**Workarounds:**

- **Hold Option while dragging** in classic Mac OS to force
  copy-instead-of-move semantics. The Mac uses open+read+write+
  close instead of rename(), which is filesystem-boundary-safe.
- **Cut + Paste** (Cmd-X / Cmd-V) achieves the same effect.

A future v2 enhancement would change the architecture so each USB
stick appears as its own Mac volume (via the supervisor-restart
trick documented in the v2 design notes), making the cross-mount
case implicitly cross-volume = always-copy. Not done in v1
because the cost is the kid losing session state on every plug-in.

### Mac OS 8.1 filename quirks

Classic Mac OS:
- Limits filenames to **31 characters**. Modern long filenames get
  visibly truncated when seen via extfs.
- Doesn't natively understand UTF-8. Files with Unicode in their
  names (e.g., emoji, accented characters) may render as garbled
  MacRoman approximations.
- Treats `:` as a path separator. Files containing `:` look broken
  on the Mac side.
- Reserves a few resource-fork-related Finder hidden files
  (`.DS_Store` from a Mac, `._*` AppleDouble files); these are noise
  on the Pi side but invisible on the Mac side.

### Finder may not auto-refresh

BasiliskII's extfs serves the directory contents on demand when Mac
OS asks, but the **Finder** doesn't always re-poll an open folder
when the underlying directory changes. If you plug a USB stick in
while the Outside World folder is already open on the Mac:

- The USB sub-folder may **not** appear immediately.
- Closing and re-opening the Outside World folder forces a refresh
  and the new sub-folder shows up.
- Alternatively, navigating up to the parent and back down works.

This is a Finder behavior, not a chimebox bug. We could improve UX
in a later phase by triggering a synthetic Finder refresh from the
Pi side (Phase 3 of the design notes); not done in v1.

### Yank-corruption risk

The default RW mount opts include `sync,dirsync` for FAT to shrink
the dirty-data window, but **physically removing a USB stick while
files are open or being written WILL still risk filesystem
corruption on the stick**. There is no software fix for this short
of a "safe to remove" workflow on the Mac side.

For very-young-kid setups where pulling a stick mid-write is likely,
set `chimebox_outside_world_readonly: true` in host_vars. This
trades the "save back to USB" workflow (which is rare in practice)
for guaranteed corruption-immunity.

### Race window between insert and udev event

Cheap or slow USB sticks sometimes complete enumeration after udev
fires its `add` event, and `blkid` returns no filesystem
immediately. The helper script retries `blkid` up to 5 times over
2.5 seconds before giving up. In practice this handles the slowest
sticks I've seen; if a stick fails to appear, check
`journalctl -t chimebox-usb` for the blkid result.

### Whole-disk filesystems

Some Mac-formatted (and old camera) sticks have a filesystem at the
whole-disk level instead of inside a partition. The udev rule
includes a second clause that catches these (`DEVTYPE==disk`,
`ID_FS_TYPE!=""`). They mount the same way as partitioned media.

## Phase 2+ (future)

This is Phase 1 of the "Outside World" design (see
`docs/v3-bridge-appliance-design.md`). Future enhancements:

- **Phase 2 (Disk Copy auto-action):** any `.img` / `.dsk` file on a
  plugged-in stick gets surfaced to the Mac with a Disk-Copy hint so
  it mounts as a real disk icon instead of a folder.
- **Phase 3 (soft hot-plug):** SIGTERM + prefs swap + supervisor
  respawn pattern for HFS-formatted disk images, so they appear as
  full Mac volumes after a polite "shutdown / restart" cycle.
- **Phase 4 (real hot-plug):** port Infinite Mac's patched
  BasiliskII core, which has true runtime SCSI/CD-ROM hot-plug. Big
  project; tracked separately.
