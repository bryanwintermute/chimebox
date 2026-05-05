# role: chimebox

Installs the chimebox runtime files into the kiosk user's home:

- `~/chimebox/`              — runtime dir (ROM, disks, snapshots, logs)
- `~/chimebox/start.sh`      — invocation wrapper that supervises BasiliskII
- `~/.xinitrc`               — exec's start.sh
- `chimebox.service` (system) — supervises the kiosk; restarts on death

Disk images and the ROM are NOT installed by Ansible — they're large and
user-supplied. Push them separately with `scripts/push-disks.sh` after
running the playbook.

## Shutdown semantics

When a user picks **Special > Shut Down** in Mac OS 8.1 inside the
emulator, BasiliskII exits cleanly. start.sh wraps the emulator in a
supervised loop, so X stays up across the shutdown and the user sees
a brief black screen (~1.5s) before BasiliskII restarts in place
— no autologin / startx flicker.

Crash-loop protection is built in: any BasiliskII exit shorter than
5 seconds is treated as a failure and we back off exponentially
(1 → 2 → 4 → … → 60s cap). After 10 consecutive short failures,
start.sh exits so getty can take over and leave the operator a tty
for debugging.

The `chimebox_shutdown_action` variable is currently `restart` (the
only supported value). Future v2 modes are scaffolded:

- `restart-with-rollback` — restore System.dsk from a `factory.dsk`
  baseline before each restart, turning Mac shutdown into a "panic
  button" for the kid. Deferred because two correctness hazards
  need solving first:
  1. **Discriminating a genuine Mac shutdown from a BasiliskII
     fatal error.** BasiliskII's `QuitEmulator()` calls `exit(0)`
     from many fatal paths (bad config, missing ROM, etc.), so the
     shell exit code alone cannot key the rollback decision — it
     would trash state every time there's a startup bug. A workable
     v2 approach: combine a runtime-threshold heuristic (rollback
     only if BasiliskII ran for at least N seconds before exiting)
     with an explicit shutdown sentinel (e.g., a host-shared file
     written by a Mac startup item just before shutdown).
  2. **Choosing the right rollback target.** The cron-driven
     `latest` snapshot can capture in-flight state because the
     daily snapshot runs while the kiosk is live. The rollback
     target needs to be a deliberately-captured `factory.dsk`
     baseline taken at `push-disks.sh` time (clean state, kiosk
     stopped). v2 of the persistence role will add this snapshot
     type.
- `poweroff` / `reboot` — would map Mac shutdown to a Pi-level
  power action. Needs a dedicated sudoers entry for the chimebox
  user; out of scope for v1.

