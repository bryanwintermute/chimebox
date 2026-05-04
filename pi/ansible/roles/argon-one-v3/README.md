# role: argon-one-v3

Optional role that installs the Argon One V3 case fan/power-button daemon
on the chimebox. Only needed if the Pi 5 is housed in an
**Argon One V3** case (the version with the I2C-controlled PWM fan + ADC
power button).

Without this role, the V3 case fan stays at its default low/off speed
because the case fan is **not** wired to the Pi 5's standard PWM fan
header — it's driven by the case's own MCU over I2C, which needs a
userspace daemon to control.

## What the role does

- Installs `python3-libgpiod`, `python3-smbus`, and `i2c-tools` from apt.
- Ensures I2C is enabled in raspi-config (Pi 5 default is enabled, but
  this is idempotent and survives images that don't enable it).
- Creates `/etc/argon/`.
- Downloads upstream Argon daemon files (`argononed.py`,
  `argonsysinfo.py`, `argonregister.py`, `argonpowerbutton.py`) from
  Argon's CDN. They're downloaded once and re-used; the role won't
  re-fetch on subsequent runs.
- Installs `/lib/systemd/system/argononed.service` (vendored — we
  control this so it doesn't drift to whatever upstream changes).
- Writes `/etc/argononed.conf` with a fan curve we control via Ansible
  variables (`chimebox_argon_fan_curve`).
- Enables and starts `argononed.service`.

## What the role does NOT do

- Does not install the Argon `argonone-config` interactive menu.
- Does not run any `apt upgrade` (the upstream script does; we don't).
- Does not install desktop icons, IR remote scripts, UPS handling,
  blue-strip DAC support, etc. We use only the fan/power-button bits.
- Does not modify the EEPROM. If you want PSU full-speed mode and other
  Argon EEPROM tweaks, run the upstream `argon-eeprom.sh` once
  (interactive). Documented in `docs/ROADMAP.md`.

## Opt-in

Set `chimebox_argon_one_v3: true` in `group_vars/all.yml` (or override per
host) to enable this role. Default is `false` so non-Argon-One-V3 users
don't have the daemon installed.

## Customizing the fan curve

The defaults are tuned for "quiet at idle, ramp under load":

| Temperature ≥ | Fan speed |
|---|---|
| 55°C | 10% |
| 60°C | 25% |
| 65°C | 55% |
| 70°C | 100% |

Override in `group_vars/all.yml`:

```yaml
chimebox_argon_fan_curve:
  - { temp: 50, speed: 30 }
  - { temp: 60, speed: 60 }
  - { temp: 70, speed: 100 }
```

## Diagnosing

```sh
# Daemon status
systemctl status argononed.service

# Live fan curve in effect
cat /etc/argononed.conf

# Verify I2C bus has the case MCU at the expected address
sudo i2cdetect -y 1   # should show a device at 0x1a
```

## References

- Upstream installer: <https://download.argon40.com/argon1.sh>
- Argon's repo with the Python sources: not officially open-sourced as
  of this writing; files are served from their CDN.
- Pi 5 + Argon One V3 thermal behavior: the V3 case ditches the
  fan-header approach and routes fan PWM through an onboard MCU
  reachable over I2C-1 at 0x1a.
