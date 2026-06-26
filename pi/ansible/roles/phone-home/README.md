# role: phone-home

A WireGuard **management tunnel** so an operator can remotely administer
a chimebox that lives at someone else's house — apply updates, fix
issues, pull logs — even though the kiosk itself is offline for the kid.

Default **off**. Enable per-host (e.g. the kid-handoff unit).

## Model

The chimebox is a WireGuard **client** that dials the operator's home WG
server. **Nothing is opened inbound** at the kid's house (no port
forward, no dynamic DNS). The tunnel carries **only the operator's home
subnet** (`AllowedIPs` in `wg0.conf`), so it is a management path, not a
general internet gateway — it cannot give the kiosk internet access or
undermine the kid's isolation.

This composes cleanly with the `egress-firewall` role, which restricts
only the **kiosk user's** traffic (by socket UID). WireGuard runs as
root, so the tunnel is unaffected, and the kiosk user stays LAN-confined
regardless of whether the tunnel is up.

## What it installs

| Path | Purpose |
|---|---|
| `/usr/local/sbin/chimebox-wg-autohome` | keepalive watchdog (up offsite, down on the operator's home LAN, bounce on stale handshake) |
| `/etc/default/chimebox-wg-autohome` | watchdog config (templated; home-LAN prefix / ntfy come from the host's gitignored `local.yml`) |
| `chimebox-wg-autohome.service` + `.timer` | run the watchdog every 60 s |

The watchdog is the **sole manager** of `wg0` (it brings the tunnel up;
`wg-quick@wg0` is intentionally *not* enabled at boot, to avoid double
management).

## SECRET — manual bootstrap (NOT managed by Ansible)

The tunnel config `/etc/wireguard/wg0.conf` holds the box's **private
key** and the operator's **endpoint** — per-host secrets that must never
land in this (public) repo. This role deliberately does not template,
copy, or vault it. You bootstrap it by hand, once, per box:

1. **On the home WG server** (e.g. OPNsense): add a new peer for this
   chimebox. Generate a keypair; record the chimebox's public key as the
   peer, and note the server's public key + endpoint.

2. **On the chimebox**, create `/etc/wireguard/wg0.conf` (mode `0600`,
   root):

   ```ini
   [Interface]
   PrivateKey = <chimebox private key>
   Address    = <this box's tunnel IP>/32

   [Peer]
   PublicKey           = <home server public key>
   Endpoint            = <home endpoint host>:51820
   # Home subnet only -- a management path, NOT a default route:
   AllowedIPs          = 10.0.0.0/24
   # Keep the NAT pinhole open from behind the kid's router so the
   # operator can initiate connections inbound over the tunnel:
   PersistentKeepalive = 25
   ```

   Lock it down: `chmod 600 /etc/wireguard/wg0.conf`.

3. **Scope the peer least-privilege** on the home firewall: allow the
   chimebox tunnel IP to reach only what the operator needs (typically
   just SSH to/from the admin workstation). On theft/loss, **revoke the
   peer** on the server — the box can no longer reach home.

The watchdog brings the tunnel up automatically once `wg0.conf` exists
and the box is offsite.

## Settings

```yaml
# Defaults (roles/phone-home/defaults/main.yml):
chimebox_phone_home_enabled: false
chimebox_phone_home_wg_interface: wg0
chimebox_phone_home_interval_seconds: 60
chimebox_phone_home_handshake_max: 180     # bounce tunnel if handshake older
chimebox_phone_home_home_lan_prefix: ""    # set in local.yml, e.g. "10.0.0."
chimebox_phone_home_notify: false          # optional edge-triggered ntfy alerts
```

`chimebox_phone_home_home_lan_prefix` reveals the operator's LAN, so set
it in the host's **gitignored** `local.yml`, not committed `main.yml`.
When set, the box keeps the tunnel **down** while it's on the operator's
own LAN (during build/test) and only dials home once it's offsite —
which avoids a routing hairpin on the home LAN. Left blank, the tunnel
is always up (fine for a box that is only ever remote).

## Verifying

```sh
# Tunnel up + recent handshake (the proof the operator can get back in):
sudo wg show wg0
sudo wg show wg0 latest-handshakes

# Watchdog decisions:
journalctl -t chimebox-wg-autohome --since '1 hour ago'

# From the operator's workstation, over the tunnel:
ssh <chimebox tunnel IP>
```

## Why "autohome" (down on the home LAN)

A chimebox is built and tested on the operator's own LAN, then shipped
to the kid's house. Bringing `wg0` up while still on the operator's LAN
would tunnel home-subnet traffic back to the same LAN it's already on —
a hairpin that can blackhole the box mid-build. The watchdog keeps the
tunnel down whenever it sees a home-LAN address, and brings it up only
once the box is somewhere else.
