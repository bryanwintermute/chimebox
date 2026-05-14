# role: audio

Configures the chimebox's ALSA default sink and sets a sane boot-
time volume for the kiosk. Solves two distinct kid-handoff problems:

1. **Routing.** The Pi 5's bare-ALSA defaults to HDMI port 0, but
   many kid setups use a small powered USB speaker instead. This
   role lets you specify which card to route to (per-host) and
   does so by stable card *name*, not by index — so USB hot-plug
   doesn't shift the routing.
2. **Volume.** Mac OS 8.1's startup chime at 100% volume on a
   real USB speaker is shockingly loud. This role sets a safe
   default (60% out of the box; configurable) at every boot.

## What it does

Installs:

- `/usr/local/sbin/chimebox-audio-init` — bash script that runs
  once per boot and:
  1. Reads `/proc/asound/cards` to discover what's present.
  2. Resolves the configured card name (or auto-detects: prefer
     USB audio card, fall back to HDMI 0).
  3. Writes `/etc/asound.conf` setting `pcm.!default` /
     `ctl.!default` to the chosen card by name (stable across
     USB hot-plug).
  4. Sets the chosen card's master control to the configured
     volume percent (skipped silently if the card has no
     software mixer — typical for Pi 5 HDMI).
  5. Runs `alsactl store` so the alsa-utils-provided restore
     service can replay the state on subsequent boots.
- `/etc/systemd/system/chimebox-audio-init.service` — oneshot
  unit ordered `After=sound.target alsa-state.service` and
  `Before=getty@tty1.service` so the configuration is in place
  before BasiliskII opens its audio device.

The script writes detailed forensic output to the journal:

```bash
journalctl -t chimebox-audio-init --since today
```

## Variables

All variables are sensible defaults; override **at least
`chimebox_audio_card`** in host_vars to match your hardware.

| Variable | Default | Notes |
|---|---|---|
| `chimebox_audio_enabled` | `true` | Master switch |
| `chimebox_audio_card` | `auto` | Card identifier or `auto` (prefer USB) |
| `chimebox_audio_master_control` | `PCM` | Mixer control name for volume |
| `chimebox_audio_default_volume_percent` | `60` | 0–100 |

### `chimebox_audio_card` values

| Value | Meaning |
|---|---|
| `auto` | Prefer the first USB audio card (driven by `snd_usb_audio`); fall back to card 0 (HDMI 0) if no USB present at boot |
| Card NAME (e.g. `vc4hdmi0`, `vc4hdmi1`, `MyUSBDAC`) | Use that specific card. Discovered via `aplay -l` or `/proc/asound/cards`. Stable across USB hot-plug. |
| Card INDEX (e.g. `0`, `2`) | Use that index. Works but less stable — USB plug/unplug shifts indices. Prefer the name form. |

### `chimebox_audio_master_control` values

| Card type | Typical control name |
|---|---|
| USB DACs and external audio interfaces | `PCM` |
| Pi 5 HDMI (vc4hdmi0/1) | none — set to `""` (volume is controlled by the monitor/TV's hardware) |
| Onboard audio chips on PCs/laptops | usually `Master` |

If the chosen card doesn't have the configured control, the
script logs a clear warning and continues without erroring —
the kiosk keeps booting, just without a software-set volume.

## Discovering your hardware

On the Pi after boot:

```bash
# Card names (the bracketed identifier in the second column)
$ cat /proc/asound/cards
 0 [vc4hdmi0       ]: vc4-hdmi - vc4-hdmi-0
                      vc4-hdmi-0
 1 [vc4hdmi1       ]: vc4-hdmi - vc4-hdmi-1
                      vc4-hdmi-1
 2 [MyUSBDAC       ]: USB-Audio - My USB Speaker
                      Generic USB audio device

# Mixer controls per card
$ amixer -c 0 scontrols    # HDMI 0: often empty
$ amixer -c 2 scontrols    # USB DAC: typically 'PCM'
```

Then set host_vars:

```yaml
# host_vars/<host>/main.yml (or local.yml if privacy-sensitive)
chimebox_audio_card: MyUSBDAC
chimebox_audio_master_control: PCM
chimebox_audio_default_volume_percent: 60
```

## Verifying

After running the playbook:

```bash
# Confirm the unit ran and the config is in place
sudo systemctl status chimebox-audio-init
sudo cat /etc/asound.conf
journalctl -t chimebox-audio-init --since today

# Confirm current volume
amixer -c <card> get <control>

# Confirm the kiosk uses the new sink (after restart)
sudo systemctl restart getty@tty1.service
# BasiliskII restarts via the supervisor; Mac chime should now
# play through the configured device at the configured volume.
```

## Failure modes

| Scenario | Behavior |
|---|---|
| Configured card not present at boot (USB unplugged) | Logs a clear warning; `/etc/asound.conf` is NOT rewritten — ALSA's built-in default applies. The kid may hear audio via card 0 (HDMI) if the monitor has speakers, or nothing if it doesn't. |
| Card present but mixer control name wrong | Routing applied; volume set is skipped with a warning. |
| `auto` with no USB card | Falls back to card 0 (HDMI 0). |
| `alsactl store` fails (rare) | Logged; state isn't persisted, but the boot's configuration still applies. Next boot re-applies via the same script. |

The role explicitly does NOT prevent boot or fail the playbook
for any of these — the kiosk should always come up regardless
of audio state. The kid not hearing audio is a degraded but
recoverable state; the kiosk being unbootable because audio
isn't perfect is not.

## Related

- `man 8 amixer`, `man 8 alsactl`
- `pi/ansible/group_vars/all.yml` — `chimebox_user` (already in
  the `audio` group via kiosk-user role)
- `pi/ansible/roles/chimebox/templates/basiliskii-prefs.j2` —
  `nosound false` (BasiliskII reads ALSA via SDL2; no extra
  config needed there)
