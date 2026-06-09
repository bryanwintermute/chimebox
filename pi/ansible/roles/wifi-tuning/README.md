# role: wifi-tuning

Bakes in the NetworkManager settings that keep a chimebox from going
**network-silent**. Small, declarative, and safe to re-run.

## Why this role exists

A chimebox that loses its wifi uplink becomes **operator-locked-out**
(the kiosk grabs the screen, there's no SSH path). Forensics on the
dev unit traced the "Pi goes silent" failure (#23) to a chain that
starts at the radio:

1. The AP **band-steers** the Pi onto a 5GHz BSSID that's too weak
   from its location → repeated `assoc-reject` → the Pi thrashes
   between 5GHz and 2.4GHz.
2. **Power-save** (the brcmfmac default) drops beacons and yields
   `reason=34` (LOW_ACK) disconnects on the idle kiosk link.
3. NetworkManager exhausts its **4 autoconnect retries** and parks
   the connection — it stays down until reboot.

This role addresses 2 and 3 for every chimebox, and 1 optionally per
host. The recovery backstop for when an uplink still drops lives in
the **net-watchdog** role.

## What it builds

| Component | Path | Purpose |
|---|---|---|
| NM drop-in | `/etc/NetworkManager/conf.d/10-chimebox-wifi.conf` | global `wifi.powersave` + `connection.autoconnect-retries` defaults |
| (optional) band lock | the wifi connection profile (`nmcli con mod`) | per-host 2.4GHz/5GHz pin for weak-band locations |

The two global settings live in `conf.d` deliberately: on these images
the wifi profile is rendered from netplan into `/run`, so `conf.d`
(read directly by NetworkManager) is the netplan-proof place for
connection defaults that should apply everywhere.

## Settings

```yaml
# Defaults (roles/wifi-tuning/defaults/main.yml):
chimebox_wifi_tuning_enabled: true
chimebox_wifi_powersave: 2          # 2 = disable (kiosk reliability)
chimebox_wifi_autoconnect_retries: 0 # 0 = retry forever
chimebox_wifi_band: ""              # "" = auto; "bg" = 2.4GHz; "a" = 5GHz
chimebox_wifi_connection: ""        # "" = auto-detect first wifi profile
```

### When to set a band lock

Only for a host whose AP steers it onto a too-weak band. It is **not**
a good global default — a unit placed near a strong 5GHz AP would be
penalised by a 2.4GHz lock. Set it per host:

```yaml
# host_vars/<hostname>/main.yml
chimebox_wifi_band: bg   # lock 2.4GHz (nmcli token, not "2.4GHz")
```

`chimebox_wifi_band` is the nmcli band token (`bg`/`a`), not the
netplan spelling (`2.4GHz`/`5GHz`).

## Verifying

```sh
# Effective tuning:
nmcli -f 802-11-wireless.powersave,802-11-wireless.band,connection.autoconnect-retries \
  connection show "<wifi connection>"

# The active link's band/channel:
nmcli -f IN-USE,SSID,CHAN,FREQ,SIGNAL dev wifi
```

## Limitations

- Doesn't create the wifi connection itself (that comes from the base
  image / first-boot setup); it only tunes reliability properties.
- A band lock is a blunt instrument. Prefer fixing placement/antenna
  where practical; use the lock when the AP's band-steering can't be
  worked around.
