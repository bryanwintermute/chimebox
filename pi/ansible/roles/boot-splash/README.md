# roles/boot-splash

Replaces the visible Linux boot (rainbow splash → scrolling kernel
text → login prompt flicker) with a single calm Plymouth splash, so
chimebox feels like a real retro Mac coming up rather than a Linux
box pretending to be one.

## Boot sequence after this role runs

```
Pi firmware       (silent, rainbow disabled)
   ↓
Plymouth splash   (centered image on solid gray, full boot)
   ↓
tty1 login        (~100ms; banner / motd suppressed)
   ↓
X server          (BasiliskII boots inside)
```

## What the role changes

| File | Change |
|---|---|
| `/boot/firmware/cmdline.txt` | `console=tty1` → `console=tty3`; appends `quiet splash plymouth.ignore-serial-consoles loglevel=0 vt.global_cursor_default=0 logo.nologo` |
| `/boot/firmware/config.txt` | `disable_splash=1` (kills Pi firmware rainbow) |
| `/etc/issue`, `/etc/issue.net`, `/etc/motd` | blanked |
| `/etc/update-motd.d/*` | demoted to non-executable |
| `/usr/share/plymouth/themes/chimebox/` | new theme: descriptor, script, `splash.png` |
| initramfs | rebuilt to include the theme (only when something changed) |

All edits are idempotent — running the role twice is a no-op.
The cmdline.txt and config.txt are backed up automatically before
each edit (Ansible's `backup: true`).

## Customizing the splash image

The shipped `files/splash.png` is the **chimebox project icon** — the
cartoon speaker-unit-in-a-box (see the repo's `branding/` directory)
centered on `#cccccc` classic Mac gray. It's safe for OSS distribution:
AI-generated art with no Apple iconography or third-party trademarks
(see `LICENSING.md`, Layer 7).

For a personal chimebox, drop your own splash at:

```
pi/ansible/roles/boot-splash/files/local-splash.png
```

(Files matching `local-*` in role `files/` directories are
gitignored, so your image won't be committed.)

Then in your `host_vars/<host>.yml`:

```yaml
chimebox_boot_splash_image: local-splash.png
```

Re-run the playbook. The new image gets baked into the initramfs.

### Image guidelines

- **Format:** PNG, 8-bit RGB (alpha channel optional).
- **Size:** anything from 256×256 up to your screen resolution. The
  Plymouth script centers it on screen; it does not stretch.
- **Background:** the theme paints the area outside your image
  `#cccccc` (the classic Mac OS background gray). For the cleanest
  look, either match that gray in your image or use an image that
  fills the screen.

## Disabling the role on a host

In `host_vars/<host>.yml`:

```yaml
chimebox_boot_splash_enabled: false
```

The role is skipped entirely. Existing splash settings on the host
are not reverted automatically — to revert, edit `cmdline.txt` and
`config.txt` by hand (a backup is sitting next to each file from the
first run).

## What this role does NOT do

- It doesn't fully eliminate the brief flash between Plymouth
  quitting and X starting. The login takes about 100ms and we
  suppress the banner, but the screen briefly goes black before X
  comes up. v2 of this role may move chimebox to a `graphical.target`
  service so plymouth hands the framebuffer directly to X.
- It doesn't play the Mac startup chime. That's handled by Mac OS
  itself, not by Linux. (Don't worry, you'll hear it.)
- It doesn't touch the Mac OS happy-Mac-icon-on-startup behavior —
  that comes from the Mac OS 8.1 boot ROM and is preserved as-is.
