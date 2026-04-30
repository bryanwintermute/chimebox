# role: lockdown

Hardens the chimebox so a curious kid (or a determined one) can't easily
escape the emulator into the host Linux:

- Disables host screen blanking and DPMS (already done in start.sh, but
  belt-and-suspenders).
- Disables Ctrl-Alt-Fn TTY switching while X is active.
- Locks the chimebox user's password (already done in kiosk-user role).
- Ensures sudoers has no NOPASSWD entries pointing at the chimebox user.
- Optionally disables USB autoboot in raspi-config.

Most of these settings are belt-and-suspenders; the main containment is
that Basilisk II in fullscreen X with no window manager has no host UI to
escape to in the first place.
