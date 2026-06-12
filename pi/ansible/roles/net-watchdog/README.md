# role: net-watchdog

A small connectivity check + auto-recovery timer. Runs every 60s
(configurable), pings the default gateway, and on sustained
unreachability (default: 3 consecutive failures = ~3 minutes)
attempts recovery via `nmcli connection up` and then
`systemctl restart NetworkManager`. Never reboots; logs loudly
when recovery is exhausted.

## Why this role exists

Chimeboxes that lose networking become **operator-locked-out**:
the kiosk is still showing the Mac, but X grabs every keystroke,
SSH is unreachable, and the operator has no path to a shell
short of a dirty power-cycle. Most network outages on a chimebox
are transient wifi flakes (DHCP renewal hiccup, AP re-associate,
driver glitch), and `nmcli connection up` or a NetworkManager
restart recovers them.

This role handles the recoverable cases automatically. For the
operator-lockout escape hatch when the watchdog can't recover,
see the panic-button role's optional `escape-to-tty` combo
(Ctrl+Alt+Shift+T → switches to a getty on tty2).

## What it builds

| Component | Path | Purpose |
|---|---|---|
| Script | `/usr/local/sbin/chimebox-net-watchdog` | check + recover |
| Service | `/etc/systemd/system/chimebox-net-watchdog.service` | oneshot wrapper |
| Timer | `/etc/systemd/system/chimebox-net-watchdog.timer` | periodic schedule |
| State file | `/run/chimebox-net-watchdog.state` | consecutive failure counter (tmpfs; resets on boot) |

## Recovery ladder

1. **Increment counter** on each failed check. A check fails when
   the gateway is unreachable **or** there is no default route at
   all — the latter is the critical case: a dead wifi uplink leaves
   no gateway to ping, and older logic skipped those ticks and never
   recovered (toggle via `chimebox_net_watchdog_recover_on_no_gateway`).
2. **Reset counter** on a successful check.
3. **At threshold** (`max_consecutive_failures`):
   1. `nmcli connection up <uplink>` — brings the uplink back. The
      uplink is resolved by name (operator-configured, else the
      active connection, else the first wifi profile) so it works
      even when the uplink is fully down and **no** connection is
      active. Usually fixes "DHCP lease expired / association
      dropped and never recovered."
   2. `systemctl restart NetworkManager.service` — handles wifi
      driver hiccups, kernel-side queue jams.
   3. *(opt-in)* **rfkill cycle** — `rfkill block wifi` then
      `unblock`, then nudge the uplink up. Steps 1–2 talk *through*
      NetworkManager; this resets the radio's soft-block / RF state
      *below* NM, for a genuinely wedged radio. Off by default
      (`chimebox_net_watchdog_aggressive_recovery`); uses only the
      rfkill ioctl, so no service-sandbox relaxation is needed.
4. **If all enabled steps fail**: log loudly via `logger -t`, reset
   counter so we don't keep retrying every 60s on a stuck failure mode.

The watchdog **never reboots the Pi**. If recovery fails, the
operator is presumed to want to debug rather than have an unattended
reboot loop muddying journal evidence.

## Tuning

```yaml
# Defaults (in roles/net-watchdog/defaults/main.yml):
chimebox_net_watchdog_enabled: true
chimebox_net_watchdog_interval_seconds: 60
chimebox_net_watchdog_max_consecutive_failures: 3
chimebox_net_watchdog_target: ""   # "" = use current default gateway
chimebox_net_watchdog_recovery_via_nmcli: true
chimebox_net_watchdog_recovery_via_restart: true
chimebox_net_watchdog_aggressive_recovery: false  # opt-in rfkill cycle
chimebox_net_watchdog_rfkill_bin: /usr/sbin/rfkill
```

To enable the last-resort rfkill cycle on a remote wifi box (cheap
insurance for a wedged radio; requires the `rfkill` package):

```yaml
# host_vars/<hostname>/main.yml
chimebox_net_watchdog_aggressive_recovery: true
```

To disable the watchdog entirely on a specific host:

```yaml
# host_vars/<hostname>.yml
chimebox_net_watchdog_enabled: false
```

To target a more authoritative endpoint (e.g., an internal DNS
server that's always up when the LAN is healthy) rather than the
gateway itself:

```yaml
chimebox_net_watchdog_target: 192.168.1.1
```

## Observability

```sh
# All forensic events:
journalctl -t chimebox-net-watchdog --since "1 day ago"

# Timer schedule:
systemctl list-timers chimebox-net-watchdog.timer

# Manual run for testing:
sudo systemctl start chimebox-net-watchdog.service
journalctl -t chimebox-net-watchdog -n 20
```

## Testing the recovery path

Easiest way to simulate failure:

1. `sudo iptables -A OUTPUT -d $(ip route show default | awk '{print $3}') -j DROP`
2. Wait 3-4 minutes; watch `journalctl -ft chimebox-net-watchdog`.
3. Expect: 3 "unreachable" lines, then a "recovery: nmcli..." line.
4. Cleanup: `sudo iptables -D OUTPUT -d ... -j DROP`.

(Recovery won't actually fix iptables-induced failure since
NetworkManager doesn't manage iptables; expect "recovery
exhausted" after both ladder steps. That's correct — recovery
isn't a panacea, only fixes recoverable failure modes.)

## Limitations

- Doesn't recover from **physical-layer** failures: cable yanked,
  router off, AP rebooted. Same `journalctl` entries surface those
  but no automated fix is possible.
- Recovers a **fully-dead uplink** (no default route) by bringing
  the uplink connection back up by name — including the case where
  NetworkManager gave up after a handshake flap and parked the
  connection (`failed (no-secrets)`); `nmcli connection up`
  re-activates it using the stored PSK.
- For a radio wedged *below* NetworkManager, the opt-in rfkill cycle
  (`chimebox_net_watchdog_aggressive_recovery`) can clear a stuck
  soft-block where NM-level steps can't. It is **not** a driver
  reload (that needs relaxing the service sandbox and is riskier on
  the Pi 5 SDIO wifi — deliberately out of scope here).
- Still can't fix an **actually-changed** WPA password or MAC ACL
  (the stored PSK is genuinely wrong) — that needs operator action.
- Doesn't reboot. By design.

For the network-down operator-recovery escape hatch when the
watchdog can't help, enable the panic-button role's
`chimebox_panic_button_escape_to_tty_enabled` flag.
