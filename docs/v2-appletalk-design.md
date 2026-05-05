# Design: Inter-chimebox AppleTalk over IP tunnel

**Status:** design sketch (not yet implemented). v2 feature; reuses
v1 chimebox foundation (BasiliskII / Mac OS 8.1 / Pi 5 kiosk).

**One-line vision:** every chimebox in a household network can see
every other chimebox in **Chooser → AppleShare**, exactly like Macs
on a 1998 office network. Family members drag files between each
other's desktops over a real period-correct protocol — without ever
touching the modern internet.

---

## Why this feature

**Period-correctness preserved.** AppleTalk is the protocol Mac OS
8.1 was designed to network with. There is no Discord-bridge here,
no JSON, no OAuth. The user sees Chooser, picks a Mac, types a
password, drags a file. That's how networking worked in 1998.

**Walled garden by definition.** AppleTalk doesn't reach the
internet. The only Macs visible in Chooser are ones an operator has
explicitly added to the chimebox family network. There is no
possible failure mode where a stranger appears in a chimebox's
Chooser.

**Teachably honest.** "Your Mac sent the file to the other Mac
through the wires" is literally true. Compare to a modern-messenger
bridge where you'd have to either lie ("they're reading your
message on a Mac too") or break the illusion ("there's actually a
modern computer hiding inside your Mac that talks to their phone").

**Kills two birds with one config.** Same machinery enables:

- **Chat-style** workflows: Stickies in shared folders, AppleShare
  drop boxes that show up on the destination Mac's desktop within
  seconds.
- **File-sharing** workflows: one user saves a Kid Pix drawing →
  the other sees it on their Mac → drops back a photo.
- **Multiplayer-game** workflows: Bolo, Marathon co-op, even
  AppleShare-mediated turn games. (Out of scope here, but the same
  network plumbing.)

---

## Vision: what success feels like

> A user finishes a Kid Pix drawing. They pick **File > Save**,
> name it `for-the-other-house`. They open **Chooser** in the
> Apple menu. Under **AppleShare** they see a list of Macs that
> includes the destination chimebox by its friendly name. They
> click it, type the standard family password (the only one ever
> used, written on a sticker), and a folder appears on their
> desktop labeled e.g. `Drop Box`. They drag the drawing onto it.
> The Mac says "Copy complete."
>
> Three seconds later, on a chimebox 1,500 miles away, the drawing
> appears on the destination desktop with a soft *bing* sound. The
> recipient opens it in MacPaint, makes a tiny change, and drops
> it back into the sender's Drop Box.
>
> The next morning, the original sender sees the reply on their
> own desktop when Mac OS finishes booting.

That's the experience to build toward.

---

## Architecture

```
                    House A                                   House B
       ┌──────────────────────────────┐            ┌──────────────────────────────┐
       │                              │            │                              │
       │   chimebox-A                 │            │   chimebox-B                 │
       │  ┌────────────────────────┐  │            │  ┌────────────────────────┐  │
       │  │ BasiliskII             │  │            │  │ BasiliskII             │  │
       │  │  (Mac OS 8.1)          │  │            │  │  (Mac OS 8.1)          │  │
       │  │   AppleTalk stack      │  │            │  │   AppleTalk stack      │  │
       │  │       │                │  │            │  │       │                │  │
       │  │       ▼                │  │            │  │       ▼                │  │
       │  │   ether tap0           │  │            │  │   ether tap0           │  │
       │  └───────┬────────────────┘  │            │  └───────┬────────────────┘  │
       │          │                   │            │          │                   │
       │     ┌────▼────┐              │            │     ┌────▼────┐              │
       │     │  tap0   │ Linux        │            │     │  tap0   │              │
       │     └────┬────┘ kernel       │            │     └────┬────┘              │
       │          │                   │            │          │                   │
       │     ┌────▼────────┐          │            │     ┌────▼────────┐          │
       │     │ chimebox-   │          │            │     │ chimebox-   │          │
       │     │ atalk-bridge│ daemon   │            │     │ atalk-bridge│          │
       │     └────┬────────┘          │            │     └────┬────────┘          │
       │          │                   │            │          │                   │
       │     ┌────▼─────┐             │            │     ┌────▼─────┐             │
       │     │ Tailscale│             │            │     │ Tailscale│             │
       │     └────┬─────┘             │            │     └────┬─────┘             │
       │          │ 100.x.y.z         │            │          │ 100.a.b.c         │
       └──────────┼───────────────────┘            └──────────┼───────────────────┘
                  │                                           │
                  └──────────  Tailscale mesh  ───────────────┘
                              (encrypted, NAT-traversed,
                               no public exposure)
```

### Components per chimebox

1. **BasiliskII** with `ether tap0` and AppleTalk enabled in Mac OS 8.1.
2. **Linux `tap0` interface** in a private bridge namespace.
3. **`chimebox-atalk-bridge` daemon** (new, Python or Go) — captures
   Ethernet frames from `tap0`, replicates AppleTalk multicast/
   broadcast to all configured peers via Tailscale-routed UDP, and
   forwards unicast frames as appropriate.
4. **Tailscale** for the inter-house network layer. Each chimebox
   gets a stable Tailscale IP; mesh handles NAT, encryption, peer
   discovery, ACLs.

### Per-house: nothing extra

No router config, no port forwarding, no public IP. Tailscale
handles all of that. From the operator's standpoint, "joining the
chimebox family network" is one `tailscale up --authkey ...` step
during Ansible provisioning.

---

## Implementation phases

### Phase 0: validate BasiliskII inter-Mac AppleTalk locally

**Goal:** before building any of the cross-internet plumbing,
confirm that two BasiliskII instances on the same physical LAN
can see each other in Chooser.

**Setup:**

1. Run BasiliskII on the Pi (the existing chimebox-dev) with
   `ether slirp` (BasiliskII's built-in NAT mode) — no good for
   inter-Mac, but verifies the Mac OS AppleTalk stack works.
2. Switch to `ether tap0` with the Pi's Linux `tap0` bridged to
   `eth0`. Mac should now appear on the LAN with its own IP/
   AppleTalk address.
3. Run a second BasiliskII on the workstation Mac with the same
   tap-bridge setup, on the same LAN.
4. In one Mac's Chooser → AppleShare → expect to see the other.

**Decision points:**

- Does AppleTalk multicast (NBP, the protocol Chooser uses to find
  Macs) cross a Linux bridge cleanly? Probably yes; bridges pass
  multicast by default.
- Does it cross when the two Macs are on different L2 segments
  (e.g., behind two different routers)? Probably no — multicast
  isn't routed by default. This is what motivates the bridge daemon.

### Phase 1: same-LAN, two real chimeboxes, no internet

**Goal:** two physical chimeboxes on the same home Wi-Fi see each
other in Chooser via simple `ether tap0` + bridge to `eth0`.

**Adds to v1:**

- New Ansible role: `chimebox-network` — installs `bridge-utils`,
  creates `tap0`, adds `tap0` to `br0` bridge, adds `eth0` to
  `br0`. Updates BasiliskII prefs to `ether tap0`.
- Per-chimebox AppleTalk identity in `host_vars` — a friendly name
  per device.
- A small Mac-OS-side setup script (run once during disk-prep) to
  enable File Sharing, create the standard user account, and set
  up the default shared folders (`Drop Box`, `Inbox`).

**Validates:** the basic Chooser-and-drag UX in a controlled
environment before adding internet complexity.

### Phase 2: cross-internet via Tailscale

**Goal:** chimeboxes in different houses see each other.

**Adds:**

- New Ansible role: `tailscale` — installs Tailscale, joins the
  family tailnet, sets ACLs to allow only `tcp+udp` to/from other
  chimeboxes.
- New daemon: `chimebox-atalk-bridge` — a small Python or Go
  service that:
  - Reads Ethernet frames from `tap0` via raw socket.
  - Identifies AppleTalk frames (EtherType `0x809B` for AppleTalk
    Phase 2, or SNAP-encapsulated).
  - For AppleTalk multicast/broadcast (e.g., NBP lookups), replicates
    the frame via UDP to every configured peer's Tailscale IP.
  - For AppleTalk unicast, looks up the destination in a learned
    AppleTalk-address-to-peer-IP table, forwards.
  - Receives UDP from peers, injects frames back into `tap0`.
- Configuration: `peers:` list in host_vars with friendly name +
  Tailscale IP per chimebox. Pairing is intentional (no auto-
  discovery — adding a chimebox is a deliberate operator act).

**Validates:** the full vision works across the internet without
exposing anything to the internet (Tailscale is private mesh).

### Phase 3: kid-friendly polish

**Goal:** the Mac-side experience matches the success vision above.

**Adds:**

- Mac OS startup script that watches the inbox folder for new files
  and copies them to the Desktop with a *bing*. (Either an
  AppleScript droplet or a tiny background app.)
- Sound effect when a file arrives (Mac OS has the system already).
- Optional: an "outbox poller" that retries failed sends.
- Pre-mounted shared folders so the user doesn't have to re-Chooser
  every session. (Mac OS persists AppleShare mounts as aliases.)
- Optional: a "send to <peer>" Finder shortcut on the Desktop
  (alias to peer's Drop Box). Drag onto the alias instead of
  opening Chooser.

### Phase 4 (maybe): admin features

- Web admin UI on the Pi (over Tailscale) for parents to add/
  remove peers, view logs, set time-of-day restrictions ("peer X
  can send 8am–8pm only").
- Per-peer file-size limits, file-type allowlists.
- Audit log: every file flowing in/out of the chimebox is recorded
  (with hash) for parental review.

---

## Mac-side configuration

These changes are made on the **disk-prep** side (i.e., baked into
`System.dsk` once, not Ansible-managed at runtime).

| Setting | Where | Value |
|---|---|---|
| AppleTalk active | Control Panels → AppleTalk | On, via Ethernet |
| File Sharing | Control Panels → File Sharing | On, owner = standard family account, password = chosen |
| Owner Name | File Sharing | per-host friendly name (from host_vars) |
| Default shared folder | Drop Box, Inbox folders | Created at user-data root |
| Sleep | Energy Saver | Disabled |
| Network Name | AppleTalk control panel | matches Owner Name |

These are part of the **chimebox kid-shortlist Tier S** disk-prep
work that already needs to happen — so this design doesn't add a
separate Mac-side workflow, it adds a few clicks to the existing
one.

---

## Security / kid-safety design

| Concern | Mitigation |
|---|---|
| Stranger appears in Chooser | Impossible — no peers added unless operator explicitly pairs via Tailscale + host_vars |
| Stranger sniffs traffic | Tailscale's WireGuard encrypts all inter-chimebox traffic |
| Family member sends inappropriate content | File-type allowlist (Phase 4); audit log so parents can review |
| Family member sends huge file (DoS) | Per-peer rate limit + max file size in atalk-bridge daemon |
| Internet leakage | chimebox firewall already blocks all internet egress except Tailscale; AppleTalk is L3-incompatible with internet anyway |
| Weak File Sharing password | Operator sets it once during disk-prep; user never types it (Chooser remembers) |
| User accidentally connects to wrong family chimebox | All chimeboxes have human-readable names; "wrong Mac" can only be a different family chimebox |

The "wrong family chimebox" failure mode is benign: if a file
goes to the wrong relative's drop box, nobody is harmed.

---

## Open questions

1. **Multicast through Tailscale.** Tailscale routes IP unicast
   reliably; broadcast/multicast typically requires extra config.
   The bridge daemon side-steps this by encapsulating multicast as
   per-peer unicast UDP. **Risk:** confirms the design needs the
   bridge daemon (vs. just Layer-2 over Tailscale). **Test:** in
   Phase 0, attempt `tailscale up` with `--accept-routes` on two
   nodes in different LANs; check whether NBP queries cross.

2. **AppleTalk routing across multiple zones.** If the family grows
   to 5+ chimeboxes, AppleTalk Phase 2 zone routing might be a
   useful organizational feature (e.g., separate zones per
   household). Not needed for MVP but worth noting.

3. **Snapshot/rollback semantics.** Currently `kid-reset` rolls
   back `System.dsk`. If incoming files from family land on the
   Desktop and live inside `System.dsk`, a kid-reset would erase
   them. **Options:** (a) accept it (rare; reset only on real
   damage); (b) write incoming files to a separate disk image
   (`Mail.dsk`) that survives reset; (c) auto-snapshot before
   each incoming-file event. **Lean:** (b), and the same disk can
   hold outgoing-file history for parental review.

4. **Time-of-day restrictions.** Should incoming files be queued
   when a chimebox is asleep (bedtime mode) and delivered on
   wake-up? Probably yes — implement via daemon-side queue + flush
   on wake-up signal.

5. **Pi 5 hardware load.** The bridge daemon adds a small
   per-frame overhead. AppleTalk traffic is low-bandwidth even at
   peak (a few KB/sec for active file transfer). **Risk:** very
   low. Pi 5 will not notice.

6. **Mac OS 8.1 AppleTalk stack quirks.** The 8.1 stack is mature
   but has known issues with very long names, Unicode, and >2GB
   shared volumes. **Mitigation:** keep shared folders modest;
   keep filenames Mac-style.

---

## Out of scope for this design

- **Real-time chat.** No iChat-style typing or instant messaging.
  AppleTalk has no good in-period chat protocol. Workaround:
  Stickies-in-a-shared-folder.
- **Voice/video.** Mac OS 8.1 didn't have it; we don't add it.
- **Multiplayer-game support.** Same plumbing enables it, but
  game-specific tuning (low latency, port-specific firewalling)
  is a separate design.
- **Bridge to non-AppleTalk services** (Discord, iMessage, email).
  See `v3-modern-comm-bridge` in the roadmap. Deliberately
  separate to keep era-correctness for this feature.
- **Cross-emulator compatibility** (Mini vMac, SheepShaver, real
  vintage Mac on a real LocalTalk-Ethernet bridge). Plausible
  later; out of scope for chimebox-to-chimebox MVP.
- **Mobile-device participation** (a "send from a phone" feature).
  That's the modern-bridge story, not this one.

---

## Ordering with other v2 work

Best implementation order if/when this is built:

1. **First:** `v2-extfs-outside-world` (separate roadmap item).
   Same prefs-file mental model; same kind of "host directory
   appears on the Mac" UX. Validates that Mac sees host
   filesystem changes cleanly.
2. **Then:** Phase 0 of this doc (validate AppleTalk between
   two BasiliskII instances on a single LAN).
3. **Then:** Phase 1 (two real chimeboxes, same LAN).
4. **Then:** Phases 2–3 (Tailscale + polish) when there's a
   second physical chimebox to test against (e.g., one for a
   relative). No point building cross-house plumbing until
   there's a second house.

---

## References

- Apple, "Inside AppleTalk" (1989, 2nd ed.) — the canonical
  protocol reference, still useful in 2026 for understanding
  Phase 2 / EtherTalk frame formats.
- BasiliskII source: `BasiliskII/src/Unix/ether_unix.cpp` for
  the Linux Ethernet emulation paths.
- BasiliskII docs: the `ether`, `udptunnel`, `udpport` prefs.
- netatalk project — historical Linux AppleTalk implementation;
  largely abandoned in modern distros but useful as reference
  for what the protocol actually does on the wire.
- Tailscale docs: subnet routes, ACLs, multicast caveats.
