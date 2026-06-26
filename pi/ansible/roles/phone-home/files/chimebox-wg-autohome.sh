#!/bin/bash
# chimebox-wg-autohome -- keep a WireGuard "phone-home" management tunnel
# alive on a chimebox that lives at someone else's house.
#
# The kiosk is offline for the kid, but the operator (remote, at the WG
# server's home) needs a way back in for admin/updates/fixes. This box
# is a WG *client* that dials the operator's home WG server; nothing is
# opened inbound at the kid's house. wg0 carries ONLY the operator's
# home subnet (AllowedIPs scoped in wg0.conf), so it is a management
# path, not a general internet gateway -- it cannot undermine the kid's
# isolation.
#
# Behaviour, driven by a 60s systemd timer:
#   - On the operator's home LAN (any iface has a HOME_LAN_PREFIX addr):
#     keep wg0 DOWN. During the build/test phase the box sits on the
#     operator's own LAN; tunnelling it back to the same LAN risks a
#     routing hairpin / lockout. Reach it directly there.
#   - Offsite (the kid's house): bring wg0 UP and keep it up. If the
#     handshake goes stale, bounce the tunnel to re-establish.
#   - Optional edge-triggered ntfy alerts on reachable/unreachable
#     transitions, so the operator learns when a box they can't see
#     drops off. Off unless configured.
#
# Ported from the planetbackup wg-autohome watchdog. Config is sourced
# from /etc/default/chimebox-wg-autohome (templated by the phone-home
# Ansible role). PREREQUISITE (manual bootstrap, NOT managed by Ansible
# -- it is a per-host secret): /etc/wireguard/wg0.conf must already
# exist (private key + peer/endpoint + PersistentKeepalive=25).
set -uo pipefail

WG_IF=wg0
HOME_LAN_PREFIX=""             # e.g. "10.0.0." ; empty => always treat as offsite
HOTSPOT_CON=""                 # optional NM connection name for cellular failover
HANDSHAKE_MAX=180
WG_NOTIFY=false
NTFY_SERVER=""                 # home ntfy (in-band; only reachable once wg0 is up)
NTFY_TOPIC=""
OOB_SERVER="https://ntfy.sh"   # out-of-band (independent of home)
OOB_TOPIC=""
NODE_NAME="chimebox"
STATE_FILE=/run/chimebox-wg-autohome.state
[ -r /etc/default/chimebox-wg-autohome ] && . /etc/default/chimebox-wg-autohome

log() { logger -t chimebox-wg-autohome "$*"; }
wg_is_up() { wg show "$WG_IF" >/dev/null 2>&1; }
# On the operator's home LAN if ANY interface holds a HOME_LAN_PREFIX
# address. Scanning all interfaces (not a fixed WAN_IF) makes this
# robust whether the box is on eth0 during build or wlan0 in the field.
# Empty prefix => never "home" => always offsite (wg0 stays up).
on_home_lan() {
  [ -n "$HOME_LAN_PREFIX" ] && \
    ip -4 addr show 2>/dev/null | grep -q "inet ${HOME_LAN_PREFIX//./\\.}"
}
handshake_fresh() {
  local t; t=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')
  [ -n "$t" ] && [ "$t" -ne 0 ] && [ $(( $(date +%s) - t )) -lt "$HANDSHAKE_MAX" ]
}
on_hotspot() {
  [ -n "$HOTSPOT_CON" ] && command -v nmcli >/dev/null 2>&1 \
    && nmcli -t -f NAME con show --active 2>/dev/null | grep -qx "$HOTSPOT_CON"
}
# ntfy helpers: $1 url, $2 title, $3 priority, $4 tags, $5 message. Never fail.
post() { curl -fsS -m 10 -o /dev/null -H "Title: $2" -H "Priority: $3" -H "Tags: $4" -d "$5" "$1" || true; }
notify_home() { [ "$WG_NOTIFY" = true ] && [ -n "$NTFY_SERVER" ] && [ -n "$NTFY_TOPIC" ] && post "$NTFY_SERVER/$NTFY_TOPIC" "$@" || true; }
notify_oob()  { [ "$WG_NOTIFY" = true ] && [ -n "$OOB_SERVER" ]  && [ -n "$OOB_TOPIC" ]  && post "$OOB_SERVER/$OOB_TOPIC" "$@" || true; }

# --- bring the tunnel up/down per location, then classify the state ----------
if on_home_lan; then
  if wg_is_up; then log "on home LAN; bringing $WG_IF down"; wg-quick down "$WG_IF" 2>/dev/null; fi
  state=on-lan
else
  if ! wg_is_up; then log "offsite; bringing $WG_IF up"; wg-quick up "$WG_IF" 2>/dev/null; sleep 5; fi
  # Home unreachable over wg0? Bounce it; optionally escalate to a hotspot.
  if ! handshake_fresh; then
    log "home unreachable over $WG_IF (stale/no handshake); bouncing tunnel"
    if [ -n "$HOTSPOT_CON" ] && command -v nmcli >/dev/null 2>&1; then
      log "escalating to hotspot '$HOTSPOT_CON'"
      nmcli con up "$HOTSPOT_CON" >/dev/null 2>&1; sleep 5
    fi
    wg-quick down "$WG_IF" 2>/dev/null; wg-quick up "$WG_IF" 2>/dev/null; sleep 5
  fi
  if handshake_fresh; then
    if on_hotspot; then state=home-ok-hotspot; else state=home-ok; fi
  else
    state=unreachable
  fi
fi

# --- edge-triggered notify on state change -----------------------------------
last=""; [ -r "$STATE_FILE" ] && last=$(cat "$STATE_FILE" 2>/dev/null)
if [ "$state" != "$last" ]; then
  log "connectivity state: ${last:-none} -> $state"
  case "$state" in
    on-lan)
      notify_home "$NODE_NAME: on home LAN" min house "Direct on the home LAN; tunnel down." ;;
    home-ok)
      notify_home "$NODE_NAME: home reachable" default white_check_mark "Offsite, WG tunnel up, home reachable."
      notify_oob  "$NODE_NAME: home reachable" default white_check_mark "Offsite, WG tunnel up, home reachable." ;;
    home-ok-hotspot)
      notify_home "$NODE_NAME: FAILOVER to hotspot" high signal_strength "Primary uplink down -> on hotspot. Home reachable via cellular."
      notify_oob  "$NODE_NAME: FAILOVER to hotspot" high signal_strength "Primary uplink down -> on hotspot. Home reachable via cellular." ;;
    unreachable)
      notify_oob  "$NODE_NAME: CANNOT reach home" urgent rotating_light "Box is alive but can't reach home over WG. Remote admin is down until it recovers." ;;
  esac
  echo "$state" > "$STATE_FILE" 2>/dev/null || true
fi
exit 0
