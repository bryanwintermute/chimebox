# Design: chimebox-bridge appliance (modern world ↔ old world)

**Status:** design sketch (not yet implemented). v3 feature; depends
on v2 inter-chimebox AppleTalk being shipped first (see
`v2-appletalk-design.md`). This doc is the answer to "how does
someone on a modern phone send a drawing to / receive a drawing
from a chimebox?"

**One-line vision:** a small headless appliance joins the chimebox
family AppleTalk network as just another peer in Chooser ("Family
Mailbox"). Files dropped onto it are translated to / from a chosen
modern protocol (Matrix, email, custom app), so adults on phones
and laptops can communicate with chimeboxes in a way that feels
period-correct on the chimebox side and modern on the phone side.

---

## Why a separate doc from v2

v2-appletalk-design.md is about chimeboxes talking to each other.
This doc is about *modern devices* (phones, laptops, things that
don't and can't run AppleTalk) joining that conversation. The
abstraction is different enough — "another Mac in Chooser, but
backed by something else" — that mixing them muddied the v2
discussion.

The bridge appliance is also tactically separable: v2 ships first,
v3 ships when there's demand for "but how does the parent on a
phone reply?"

---

## State of modern AppleTalk (as of 2026)

| Platform | Native AppleTalk? | Practical path |
|---|---|---|
| Modern macOS (≥ 10.6, 2009) | No | None — Apple removed the stack |
| Linux | Yes via `netatalk` 2.x | Active community keeps it compiling |
| BSD | Same — `netatalk` 2.x | Same story |
| Windows | Effectively no | A few abandoned tools, not worth it |
| iOS / Android | No | No native stack, no maintained AFP client |

**Key fact:** modern macOS deprecated AFP-over-TCP in 10.13 and
removed the AppleTalk stack much earlier (10.6, 2009). There is
no path to "native AppleTalk on a current MacBook." Modern Mac
participation requires either:

1. A side-of-network helper (this doc), OR
2. Running an old macOS in a VM (out of scope; impractical for the
   kind of person we want to enable here — grandparents, etc.).

### Existing modern AppleTalk projects worth knowing about

A small but active community keeps AppleTalk alive:

- **`netatalk` 2.x** — the classic. Linux/BSD service that appears
  as a Mac in Chooser, serves AFP-over-AppleTalk. v2.x is the
  last version with AppleTalk support; v3.x dropped it for
  AFP-over-TCP only. **This is the foundation of the bridge
  appliance.**
- **`abridge` (Colin Leroy)** — modern userspace AppleTalk-over-IP
  bridge daemon. Useful as reference for our `chimebox-atalk-bridge`
  design and may be directly usable.
- **`tashtalk` (also Leroy)** — microcontroller bridging modern
  serial to LocalTalk. Not relevant for emulators (no LocalTalk
  hardware) but evidence the community is active.
- **AURP** (AppleTalk Update-Based Routing Protocol) — Apple's
  official AppleTalk-over-IP encapsulation. Could in principle
  obviate our custom bridge daemon.

The fact that *new* projects like `abridge` exist in 2026 is the
encouraging signal — this isn't a dead protocol, it's a quietly-
maintained one.

---

## Architecture

```
                        ┌─────────────────────────────┐
                        │   chimebox-bridge           │
                        │   (any small Pi or VM)      │
                        │   no display, no emulator   │
                        │  ┌───────────────────────┐  │
                        │  │ chimebox-atalk-bridge │  │  ← same daemon
                        │  │ daemon                │  │    as v2 chimeboxes
                        │  └─────────┬─────────────┘  │
                        │            │                │
                        │  ┌─────────▼─────────────┐  │
                        │  │ netatalk 2.x          │  │  ← appears in Chooser
                        │  │  (AFP-over-AppleTalk  │  │    as e.g.
                        │  │   AppleShare host)    │  │    "Family Mailbox"
                        │  └─────────┬─────────────┘  │
                        │            │                │
                        │  ┌─────────▼─────────────┐  │
                        │  │ inotify folder-watch  │  │  ← when files land,
                        │  │  + protocol adapter   │  │    forward via...
                        │  └─────────┬─────────────┘  │
                        └────────────┼────────────────┘
                                     │
                       ┌─────────────┼─────────────┐
                       │             │             │
                  ┌────▼────┐  ┌─────▼─────┐  ┌────▼────┐
                  │ Matrix  │  │   email   │  │ custom  │
                  │  bot    │  │   IMAP    │  │  app    │
                  └────┬────┘  └─────┬─────┘  └────┬────┘
                       │             │             │
                  ┌────▼────────────────────────────▼────┐
                  │ Phones / laptops / modern devices    │
                  └──────────────────────────────────────┘
```

### Components

1. **`chimebox-atalk-bridge` daemon** — the same daemon a real
   chimebox runs (per v2 design). Joins the family AppleTalk
   network via Tailscale.
2. **`netatalk` 2.x** — the *only* component the bridge appliance
   has that a real chimebox doesn't. Provides AFP-over-AppleTalk
   so a chimebox's Mac OS Chooser sees the bridge as a Mac.
   Configured to expose a single share, e.g., `Family Mailbox`,
   with two folders: `inbox/` (chimeboxes write here) and
   `outbox/` (chimeboxes read here).
3. **inotify-driven folder watcher** — Linux service that watches
   `Family Mailbox/inbox/`. New files trigger a callback into the
   protocol adapter.
4. **Protocol adapter** — pluggable layer that translates between
   netatalk's filesystem view and a chosen modern transport. One
   adapter per protocol: `adapter-matrix`, `adapter-email`,
   `adapter-app`, etc.
5. **Tailscale** — same as v2; bridge appliance is a tailnet member.

### Hardware

- Pi Zero 2 W, Pi 4, or a small VM. No GPU needed, no audio, no
  display. Can run on whatever hardware is convenient.
- Disk: a few hundred MB for the OS, a few GB for queued files.
- Network: just Tailscale connectivity.

---

## Protocol-adapter recommendations

When choosing what modern protocol the bridge speaks:

### Matrix (recommended)

- **Pros:** federated, end-to-end-encrypted, room-based ACLs
  perfect for a "family" room, open-source server (Synapse,
  Conduit, Dendrite), bots are first-class, audit trail built in,
  no walled-garden risk.
- **Cons:** requires a Matrix homeserver (could be self-hosted
  or matrix.org); adults need a Matrix client (Element on phone
  is excellent; not as ubiquitous as Discord).
- **Best for:** the actual primary use case — a family that
  wants safe two-way messaging.

### Email (IMAP/SMTP)

- **Pros:** dead-simple, every adult has it, bridge code is ~50
  lines, asynchronous-by-design (fits the chimebox vibe).
- **Cons:** no audit-friendly thread structure; adults' replies
  go to one shared mailbox unless you give each chimebox-recipient
  a separate email alias.
- **Best for:** "send a drawing to a relative" one-way flows; less
  ideal for ongoing conversation.

### Custom app

- **Pros:** tunes the UX to the use case (e.g., a "send back"
  button optimized for grandparents); branding/integration
  freedom.
- **Cons:** real software project, maintenance burden, app-store
  hassle for iOS especially.
- **Best for:** later, after Matrix or email validates the
  primary use case.

### Discord

- **Pros:** convenient, everyone's already there, easy bot.
- **Cons:** walled garden, kid-unaligned platform values, bot
  accounts need maintenance, easy to leak content beyond the
  family unintentionally.
- **Recommendation:** avoid for the primary feature; possibly
  acceptable as a one-off for adult-only audit notifications.

### Signal / iMessage / WhatsApp

- **Recommendation:** avoid. Restrictive APIs, would be fighting
  platform limits constantly.

---

## Implementation phases

### Phase 0: AppleShare-only "mailbox" (no protocol bridge yet)

**Goal:** validate that the bridge appliance can join the
chimebox AppleTalk network and present as a Mac in Chooser.

- Pi Zero 2 W or similar runs Debian.
- Install netatalk 2.x, configure single AppleShare volume.
- Run the same `chimebox-atalk-bridge` daemon (from v2) so it
  joins the AppleTalk network alongside real chimeboxes.
- Pair it with the dev chimebox via host_vars.
- Verify: Chooser on the chimebox shows "Family Mailbox" alongside
  other chimeboxes; user can drag a file onto its Drop Box and
  see it appear on the Linux side at
  `/srv/family-mailbox/inbox/`.

**Validates:** the bridge appliance is just-another-peer to the
chimebox AppleTalk network, with no special-case handling needed.

### Phase 1: email adapter (smallest useful adapter)

**Goal:** "drop a Kid Pix drawing on Family Mailbox → an adult
gets an email with the drawing attached as a PNG."

- inotify watcher fires on new files in `inbox/`.
- Adapter:
  - Convert MacBinary / AppleSingle / etc. to standard formats
    (Mac OS adds resource forks; we want the raw data fork).
  - Convert Mac PICT to PNG if the drawing is in PICT format.
  - Compose email with the file as attachment.
  - Send via SMTP to a configured family address.
- Reverse: poll IMAP for incoming family replies, drop attachments
  into `outbox/` so they appear on the chimebox the next time
  someone connects.

**Validates:** the protocol-adapter pattern. Email is the simplest
adapter and the most universally accessible.

### Phase 2: Matrix adapter

**Goal:** real two-way conversation between chimeboxes and family
on phones.

- Replace email adapter with Matrix bot.
- Bot joins a designated family room.
- New files in `inbox/` → bot uploads as Matrix media + posts in
  the room with attribution ("from \[chimebox name]").
- Replies in the room (text or media) → bot writes them as files
  in `outbox/` with sender metadata in the file name.
- Optional: per-chimebox sub-folders so each chimebox has its own
  `outbox/<chimebox-name>/` and only sees replies addressed to it.
- Optional: text replies become Stickies (`.txt` files Mac OS
  recognizes as Stickies content).

**Validates:** the long-term primary use case.

### Phase 3: kid-friendly polish on the chimebox side

(Carries through from v2-appletalk-design.md Phase 3.)

- "Send to Family Mailbox" Desktop alias on the chimebox.
- Sound effect when reply lands.
- Auto-display Stickies on the desktop when text replies arrive.

### Phase 4 (maybe): custom mobile app

Consider only after Matrix validates the primary use case. App
would wrap the Matrix protocol underneath but present a
chimebox-themed UI for the adults ("New drawing from a relative!").
Probably out of scope until OSS adoption justifies
the maintenance burden.

---

## Security / safety design

| Concern | Mitigation |
|---|---|
| Stranger sends to chimebox | Adapter has an allowlist of permitted senders (Matrix user IDs, email From addresses, etc.). Anything outside the list is dropped to a quarantine folder for parental review. |
| Stranger receives from chimebox | Same allowlist; only allowlisted recipients receive forwarded files. |
| Bridge appliance compromise | Bridge appliance has no chimebox credentials beyond its AppleTalk membership; worst case is "stranger sees files until allowlist breach is detected." |
| Inappropriate content from family | Audit log on the bridge; parental-review folder; adapter-side image moderation if desired (out of scope for v3 MVP). |
| File-type abuse (executables, etc.) | File-type allowlist in the adapter (PNG, JPEG, GIF, TXT, RTF, simple Mac formats only). |
| File-size DoS | Per-sender rate-limiting and max file size in the adapter. |
| Bridge appliance internet exposure | Tailscale-only access from the chimebox AppleTalk side; outbound connections to chosen modern protocol only (no inbound from public internet). |

---

## Open questions

1. **MacBinary / resource fork handling.** Mac OS files often
   carry resource forks. When forwarding to email/Matrix, do we
   preserve them (using AppleSingle / MacBinary encoding) or strip
   them? **Lean:** strip for outgoing (simpler for adults to open
   on phones); preserve for incoming (chimebox kid expects native
   Mac files). Need adapter logic.

2. **Format conversion.** Kid Pix saves in PICT or its own format;
   modern phones expect PNG/JPEG. Adapter should auto-convert
   common Mac formats to modern equivalents on the way out.
   Reverse direction probably doesn't need conversion (Mac OS
   8.1 can open JPEG via QuickTime).

3. **Identity / attribution.** Chimebox-side files don't carry
   "from whom" metadata reliably. **Options:** (a) infer from
   chimebox host_vars (each chimebox knows its own friendly
   name); (b) add a Mac OS startup script that wraps each saved
   file in metadata; (c) accept loose attribution. **Lean:** (a)
   for MVP; chimebox-side script is overkill for low-traffic
   family use.

4. **Audit log retention.** How long do we keep evidence of every
   file that flowed in/out? **Lean:** 90 days on the bridge
   appliance, configurable.

5. **Multiple bridge appliances.** Could a family run two — one
   for Matrix-talking parents, one for email-talking grandparents?
   Yes; they're just peers in the AppleTalk network with
   different friendly names. No special handling needed.

6. **Bridge appliance kid-mode.** A bridge appliance could itself
   be configured for one-way operation (e.g., only allow incoming
   to chimeboxes, not outgoing) for a more locked-down setup.
   Useful for very young users who shouldn't initiate
   conversations.

---

## Out of scope for this design

- **Voice / video.** Not what AppleTalk is for; no period-correct
  Mac OS app supports it.
- **Real-time chat (typing indicators, etc.).** AFP file polling
  is the channel; expect 5-30 second latency.
- **Chimebox-to-non-AppleTalk-Linux services.** If you want a
  chimebox to talk directly to a Linux box without a "Mac"
  facade, you'd just use AFP-over-TCP via netatalk 3.x. Out of
  scope here because it loses the period-correct Chooser UX.
- **Federation across families.** Each family runs its own bridge
  appliance and its own tailnet. Cross-family communication is
  not a goal.

---

## Comparison to other v2/v3 ideas

| Idea | Era-correct? | Effort | Primary use |
|---|---|---|---|
| `v2-extfs-outside-world` | Yes | 1 evening | USB sticks, cameras, fridge frame |
| `v2-inter-chimebox-appletalk` | Yes | 1-2 weekends | Chimeboxes talking to chimeboxes |
| `v3-bridge-appliance` (this) | Yes on chimebox side, modern on phone side | 2-4 weekends | Phones / laptops talking to chimeboxes |
| `v2-printer-bridge` | Yes | 2-3 evenings | PDF / fridge gallery |
| `v3-modern-comm-bridge` (Discord-on-Mac) | No (modern app behind 1998 mask) | 1-2 weekends | (Deprioritized) |

This bridge-appliance design supersedes the older
`v3-modern-comm-bridge` idea because it preserves period-correctness
on the chimebox side. A drawing showing up on the kid's desktop
came from "the other Mac in Chooser" — which happens to be backed
by Matrix, but the kid never has to know that. The illusion holds.

---

## References

- netatalk 2.x: https://netatalk.io (and the v2 branch
  documentation)
- Colin Leroy's projects: https://github.com/colinleroy/abridge,
  https://github.com/colinleroy/tashtalk
- `v2-appletalk-design.md` — the foundation this design builds on
- Matrix specification: https://spec.matrix.org/
- AppleTalk Phase 2 / EtherTalk reference: Apple, "Inside
  AppleTalk" 2nd ed.
