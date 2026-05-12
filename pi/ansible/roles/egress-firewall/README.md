# role: egress-firewall

Restricts the **kiosk user's** outbound network traffic to the
configured LAN CIDR(s), using nftables `meta skuid` to filter
by originating socket owner. Operator SSH sessions, host
services (DHCP, NTP, apt updates), and any future per-user
bridge daemons are unaffected — only the kiosk user is
gated.

## Why per-user, not host-wide?

A host-wide egress block would also break:

- Operator's SSH outgoing replies (you'd lock yourself out
  if you ever ran `apt update` from the SSH session)
- NTP time sync (the Pi 5 has no RTC; snapshot timestamps
  depend on correct time)
- DHCP renewals
- apt/eeprom updates
- Future bridge daemons (printer bridge, AppleTalk tunnel,
  modern messaging) which each need their own scoped
  network access

Per-user filtering means the kid-facing kiosk (BasiliskII
running as `chimebox`) can never escape to the public
internet — even if the kid somehow breaks out of the
emulator into the host shell — while everything else
operates normally. Future bridges run as their own
dedicated users (`chimebox-bridge-print`, etc.) and get
their own scoped rules in their own roles.

## What it does

Installs nftables (if missing) and a single inet table named
`chimebox_egress` containing one output-hook chain:

- Default policy: `accept` (most users, most packets, pass)
- One rule: if `meta skuid` matches the restricted user,
  jump to a chain that allows loopback + LAN destinations
  and drops (with rate-limited logging) everything else.

Lives in `/etc/nftables.d/chimebox-egress.nft` and is loaded
by a dedicated systemd unit (`chimebox-egress.service`).
Doesn't touch `/etc/nftables.conf`; any other nftables rules
you have continue to work independently.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `chimebox_egress_firewall_enabled` | `true` | Master switch. Set false to skip the firewall on a host. |
| `chimebox_egress_restricted_user` | `{{ chimebox_user }}` | The user whose egress is gated. |
| `chimebox_lan_cidrs` | `[192.168.1.0/24]` | List of CIDRs the user may reach. **Override per your home LAN.** |
| `chimebox_egress_log_level` | `warn` | nftables log level: emerg/alert/crit/err/warn/notice/info/debug or `none` to silence. |
| `chimebox_egress_log_rate` | `10/second` | nftables `limit rate` for drop logs. |
| `chimebox_egress_log_prefix` | `chimebox-egress-drop: ` | Tag prefix in dmesg/journal. Grep on this. |

## Verifying

### Confirm the table is loaded

```bash
sudo nft list table inet chimebox_egress
```

You should see the `allowed_cidrs_v4` set, the
`restrict_user` chain, and the `output` chain.

### Smoke-test the rule from the operator side

Run a sentinel command as the restricted user and watch the
journal for the drop log:

```bash
# Should succeed (LAN destination -- adjust IP to your router)
sudo -u chimebox curl --max-time 5 -sI http://192.168.1.1/ ; echo "rc=$?"

# Should fail (internet destination); produces a drop log
sudo -u chimebox curl --max-time 5 -sI http://1.1.1.1/ ; echo "rc=$?"

# See the drop in the kernel log
sudo journalctl -k --since '1 minute ago' | grep chimebox-egress-drop
```

Expected: the LAN curl returns rc=0 (or whatever the server
gives), the internet curl fails (rc=28 = timeout), and you
see a log line like:

```
kernel: chimebox-egress-drop: IN= OUT=wlan0 SRC=192.168.1.50 DST=1.1.1.1 ...
```

### Confirm operator and host services are unaffected

```bash
# As the admin user (whatever your operator login is): full network
curl --max-time 5 -sI https://example.org/ ; echo "rc=$?"  # rc=0
```

## Disabling

Set `chimebox_egress_firewall_enabled: false` in host_vars
and re-run the role. The systemd unit is stopped, the table
is deleted, the host returns to its prior (unrestricted)
posture. The ruleset file remains on disk for inspection.

## What this role does NOT do

- It doesn't filter inbound traffic. SSH from anywhere on
  the LAN remains reachable; if you want inbound filtering,
  add a separate role/table.
- It doesn't audit DNS queries. The kiosk user is blocked
  from reaching off-LAN DNS resolvers, but if your LAN
  router proxies DNS to the public internet, the kiosk
  user *could* still resolve names via the router. (In
  practice the kiosk user doesn't make DNS queries; this is
  a theoretical concern only.)
- It doesn't filter IPv6 deliberately: the host has no v6
  default route, so v6 has no escape path anyway. The drop
  chain implicitly blocks v6 from the kiosk user too,
  belt-and-suspenders.
- It doesn't manage `/etc/nftables.conf` or interact with
  any other nftables rules you may have.

## Related

- `man 8 nft` — nftables command reference
- `man 5 nftables` — ruleset syntax
- `chimebox_user` defined in `group_vars/all.yml`
