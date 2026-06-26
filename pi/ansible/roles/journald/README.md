# role: journald

Makes the systemd journal **persistent across reboots**.

## Why this role exists

Raspberry Pi OS ships a vendor drop-in
(`/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf`) that
forces `Storage=volatile` — the journal lives only in tmpfs and is
**wiped on every reboot**. That's the opposite of what a chimebox needs:
the failure modes you most need to debug (the kiosk goes network-silent,
the panic-daemon strands itself, a power brownout) are exactly the ones
you can only investigate *after* a reboot. Without persistence the
evidence is gone.

This role overrides the vendor default so the trail survives. It's the
foundation the `net-watchdog`, `pmic-watchdog`, and panic-daemon
logging all rely on (they `logger -t` to the journal precisely so there
*is* a post-mortem trail). Tracked as issue #20.

chimebox runs on NVMe, so the on-disk journal is cheap; size and
retention are capped so it can't grow unbounded.

## What it builds

| Path | Purpose |
|---|---|
| `/etc/systemd/journald.conf.d/50-chimebox-persistent-storage.conf` | overrides the Pi's volatile default (`Storage=persistent` + size/retention caps) |
| `/var/log/journal/` | the persistent journal directory (created explicitly so the first post-provision boot is already persistent) |

## Settings

```yaml
# Defaults (roles/journald/defaults/main.yml):
chimebox_journald_persistent: true      # false = leave volatile (Pi default)
chimebox_journald_system_max_use: 200M  # on-disk cap
chimebox_journald_max_retention: 30d    # time-based retention
```

## Verifying

```sh
# Effective storage (want: persistent):
journalctl --header 2>/dev/null | grep -i 'storage\|persistent' || \
  systemctl show systemd-journald -p Storage 2>/dev/null

# The persistent dir exists and has boots in it:
ls -d /var/log/journal && journalctl --list-boots | tail

# Across a reboot, prior boots remain visible:
journalctl --list-boots        # should show more than just boot 0
```

## Ordering

Runs early (right after `base`) so the persistent journal exists before
the watchdog roles whose whole value is leaving a forensic trail.
