# role: pmic-watchdog

A small observability timer that logs the Pi 5's **power-management
signals** — under-voltage, frequency capping, throttling, and a
monitored voltage rail — to the journal, so power events can be
correlated with symptoms after the fact.

## Why this role exists

The Pi 5 exposes `vcgencmd get_throttled`: a bitfield of *current* and
*historical* under-voltage / throttle events. The historical ("since
boot") flags are the only evidence a brief brownout ever happened —
and they're **wiped on the next reboot**. By the time an operator
notices a problem, the proof is usually gone.

Concrete case (chimebox issue #21 / #23): chimebox-bryan logged
`throttled=0x50000` (under-voltage + throttling occurred since boot)
but with no timestamps, we couldn't tell *when* or correlate it with
the wifi flapping. Forensics later found seven distinct under-voltage
events in one boot — one at cold-boot inrush, the rest mid-run — most
likely a marginal multi-port USB charger sagging when sibling ports
drew current. This role would have surfaced all of that live.

It pairs with **net-watchdog** (connectivity recovery): net-watchdog
fixes the network, pmic-watchdog explains *why* it broke when the
cause is power.

## What it builds

| Component | Path | Purpose |
|---|---|---|
| Script | `/usr/local/sbin/chimebox-pmic-watchdog` | sample + log |
| Service | `/etc/systemd/system/chimebox-pmic-watchdog.service` | oneshot wrapper |
| Timer | `/etc/systemd/system/chimebox-pmic-watchdog.timer` | periodic schedule |
| State file | `/run/chimebox-pmic-watchdog.state` | edge-detection + heartbeat state (tmpfs; resets on boot) |

## What it logs (edge-driven, not every tick)

- **Since-boot flags** (bits `0x10000`–`0x80000`): logged **once each**,
  the first tick they're seen set.
- **"Now" flags** (bits `0x1`–`0x8`): logged when the active set
  **changes** — rising edge logs what's active, falling edge logs
  "cleared."
- **Voltage rail** (`EXT5V_V` by default): logged when it first dips
  **below** the warn threshold, and again when it recovers.
- **Heartbeat**: current state once per hour even when clean, so an
  empty `journalctl` search means "nothing wrong," not "wasn't running."

### throttled bitfield decoder

| Bit | Meaning |
|---|---|
| `0x00001` | under-voltage detected (now) |
| `0x00002` | arm frequency capped (now) |
| `0x00004` | currently throttled (now) |
| `0x00008` | soft temperature limit active (now) |
| `0x10000` | under-voltage has occurred (since boot) |
| `0x20000` | arm frequency capping has occurred (since boot) |
| `0x40000` | throttling has occurred (since boot) |
| `0x80000` | soft temperature limit has occurred (since boot) |

## Settings

```yaml
# Defaults (roles/pmic-watchdog/defaults/main.yml):
chimebox_pmic_watchdog_enabled: true
chimebox_pmic_watchdog_interval_seconds: 60      # sample cadence
chimebox_pmic_watchdog_heartbeat_seconds: 3600   # hourly "all clear"
chimebox_pmic_watchdog_volt_rail: EXT5V_V        # PMIC ADC rail to watch
chimebox_pmic_watchdog_volt_warn_below: 4.85     # early-warning volts
```

## Verifying

```sh
# All PMIC events (now persistent across reboots, per #20):
journalctl -t chimebox-pmic-watchdog --since '1 day ago'

# Timer schedule:
systemctl list-timers chimebox-pmic-watchdog.timer

# Force a sample now:
sudo systemctl start chimebox-pmic-watchdog.service
journalctl -t chimebox-pmic-watchdog -n 10
```

A clean box logs only the hourly heartbeat plus a one-time
`since-boot flag` line if the current boot ever dipped.

## Using it to validate a PSU swap

The intended workflow for "is this power supply actually adequate?":

1. Deploy this role and let it run on the **suspect** supply for a day;
   note the under-voltage / dip log lines.
2. Swap to the candidate supply (e.g. the official Pi 5 27W PSU).
3. Compare: a healthy supply should show **no** under-voltage flags and
   `EXT5V_V` comfortably above the warn threshold in every heartbeat.

## Notes / limitations

- Runs as root for unrestricted access to the VideoCore mailbox
  (`/dev/vcio`); the service deliberately does **not** set
  `PrivateDevices=true`, which would hide it and break `vcgencmd`.
- A 60s poll can miss the exact instant of a sub-second dip, but the
  sticky since-boot flags guarantee the *occurrence* is still logged.
- Read-only: it never changes clocks, voltages, or governor settings —
  pure observability.
