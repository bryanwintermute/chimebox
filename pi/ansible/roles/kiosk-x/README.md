# role: kiosk-x

Installs a minimal X11 environment for the chimebox kiosk:

- `xserver-xorg`, `xinit` — X server and `startx`/`xinit` launchers
- `unclutter` — hides the host cursor (Basilisk II draws the Mac cursor)
- `x11-xserver-utils` — `xset` for disabling screen blanking and DPMS

No window manager, no desktop environment, no display manager. The
chimebox user's `~/.xinitrc` (installed by the `chimebox` role) starts
Basilisk II directly as the only X client.
