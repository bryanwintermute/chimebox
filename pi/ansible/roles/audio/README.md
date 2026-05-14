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

> **Pi 5 has no 3.5mm jack.** The Pi 5 board dropped the
> 3.5mm combo audio/composite jack present on earlier models.
> Stock audio options are HDMI (either port) or USB. If you
> want analog audio out, add a USB DAC, an I2S DAC HAT, or a
> case-specific audio add-on (e.g., Argon ONE V3's audio
> board). The `chimebox-audio-list` helper categorizes USB
> audio devices as "USB Audio" and I2S/codec cards as "Other";
> the `auto` mode picks the first USB card if any, else HDMI 0.

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

After the first playbook run, the role installs a helper that
inventories your audio hardware and prints **ready-to-paste**
host_vars:

```bash
ssh <admin>@<your-chimebox> sudo chimebox-audio-list
```

Sample output:

```
=== ALSA audio cards on chimebox ===

Card 0: vc4hdmi0
  Type:        HDMI
  Description: vc4-hdmi - vc4-hdmi-0
  Mixer controls: (none -- volume set on the device or downstream)

Card 1: vc4hdmi1
  Type:        HDMI
  Description: vc4-hdmi - vc4-hdmi-1
  Mixer controls: (none -- volume set on the device or downstream)

Card 2: MyUSBDAC
  Type:        USB Audio
  Description: USB-Audio - My USB Speaker
  Mixer controls:
    Simple mixer control 'PCM',0

=== Current routing ===
/etc/asound.conf points to:
    slave.pcm "hw:MyUSBDAC,0"
    card "MyUSBDAC"

=== Suggested host_vars for this hardware ===

Edit pi/ansible/host_vars/<your-host>/main.yml and set:

  # USB card detected
  chimebox_audio_card: MyUSBDAC
  chimebox_audio_master_control: PCM
  chimebox_audio_default_volume_percent: 60

Then re-run: ansible-playbook playbook.yml --tags audio

Or accept the default 'auto' (prefer USB, fall back to HDMI 0)
and skip the host_vars step entirely.
```

### If you haven't run the playbook yet

The helper is installed by the audio role, so for the very
first run you have three options:

1. **Accept the default.** `chimebox_audio_card: auto` is
   the role default. Just run the playbook; the audio-init
   service will pick the first USB audio card if present
   (otherwise HDMI 0). For most setups this is correct.

2. **Inspect by hand first.** SSH in and run:
   ```bash
   cat /proc/asound/cards    # card index + bracketed name
   aplay -l                   # same info, formatted
   amixer -c <N> scontrols    # mixer controls on card N
   ```

3. **Run the playbook with auto, then re-tune.** Run once with
   the default, SSH in, run `sudo chimebox-audio-list`, set
   host_vars, re-run with `--tags audio`. (This is the usual
   flow.)

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
