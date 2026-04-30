# role: kiosk-user

Creates the unprivileged `chimebox` user that runs the X session and the
emulator. Separation from the admin user (`bryan`) keeps the kiosk
session sandboxed:

- No sudo
- No SSH access
- Required group memberships only (audio, video, input, tty)
- Configured for autologin on tty1 (which then triggers `startx` from
  `~/.bash_profile`)

The autologin part is achieved via a systemd drop-in for
`getty@tty1.service`.
