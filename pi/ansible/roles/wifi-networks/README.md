# role: wifi-networks

Lets one chimebox image roam between Wi-Fi networks — typically a
**build-site** network (where you provision it) and a **deployment**
network (where it lives). Raspberry Pi Imager only bakes in a single
network; this role adds the rest so NetworkManager can auto-connect to
whichever known SSID is in range, with no go-time fiddling.

## Why

A chimebox is built and tested on the operator's Wi-Fi, then handed off
to live on someone else's. Rather than re-flashing or hand-editing
config at delivery, list both networks here and the same image connects
to the operator's network at home and the recipient's network at theirs.

NetworkManager natively keeps multiple saved profiles and connects to
the strongest/highest-priority one available — this role just makes
those profiles **reproducible** (they survive the from-scratch rebuild)
and keeps the secrets out of the public repo.

## What it builds

For each entry in `chimebox_wifi_networks`, a NetworkManager keyfile at
`/etc/NetworkManager/system-connections/chimebox-<ssid>.nmconnection`
(mode `0600`, root). Global reliability tuning (power-save off, infinite
autoconnect retries) comes from the `wifi-tuning` role's conf.d drop-in,
so it is not repeated per network.

## Settings

```yaml
# Defaults: empty (role is a no-op unless a host provides networks).
chimebox_wifi_networks: []
```

Define the real list in the host's **gitignored** `local.yml` (the
`psk` values are secret and must not enter this public repo):

```yaml
# host_vars/<host>/local.yml   (gitignored)
chimebox_wifi_networks:
  - ssid: "Build Site Wi-Fi"
    psk:  "<operator wifi password>"
    priority: 10
  - ssid: "Recipient Home Wi-Fi"
    psk:  "<recipient wifi password>"
    priority: 20          # prefer the deployment network if both seen
  # - ssid: "Hidden Net"
  #   psk:  "..."
  #   hidden: true
```

| Key | Required | Meaning |
|---|---|---|
| `ssid` | yes | network name |
| `psk` | yes | WPA2 pre-shared key (secret) |
| `priority` | no | autoconnect priority; higher wins when several are visible (default 0) |
| `hidden` | no | `true` for a non-broadcast SSID (default false) |

## Recommended pattern

- **Raspberry Pi Imager**: bake in the *build-site* network only — just
  enough for first boot + SSH so Ansible can run.
- **This role**: list the *deployment* network (and any others). Avoid
  also listing the exact network already baked by the Imager, or NM
  would hold two profiles for the same SSID. (If you'd rather this role
  own every network, configure no Wi-Fi in the Imager and instead first-
  boot on Ethernet, then list all networks here.)

## Verifying

```sh
# Profiles NM now knows (look for chimebox-<ssid>):
nmcli -t -f NAME,TYPE,AUTOCONNECT connection show | grep wireless

# Which one is active / signal of visible known networks:
nmcli -f IN-USE,SSID,SIGNAL,SECURITY device wifi
```

## Notes / limitations

- Secrets: `psk` lives in the keyfile (root-only `0600`, NM's standard)
  and in the gitignored `local.yml`. The Ansible task uses `no_log` so
  the PSK never reaches console or logs.
- Removing a network: delete its
  `chimebox-<ssid>.nmconnection` keyfile and run `nmcli connection
  reload`. The role adds/updates listed networks; it does not prune
  ones you remove from the list.
