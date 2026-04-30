# role: chimebox

Installs the chimebox runtime files into the kiosk user's home:

- `~/chimebox/`              — runtime dir (ROM, disks, snapshots, logs)
- `~/chimebox/start.sh`      — invocation wrapper that execs Basilisk II
- `~/.xinitrc`               — exec's start.sh
- `chimebox.service` (system) — supervises the kiosk; restarts on death

Disk images and the ROM are NOT installed by Ansible — they're large and
user-supplied. Push them separately with `scripts/push-disks.sh` after
running the playbook.
