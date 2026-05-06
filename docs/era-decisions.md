# Era decisions

This document captures the major design choices behind chimebox and
the reasoning for each. Most of these decisions were made early in
the project's first week and held up through subsequent
implementation; a few are deliberate work-in-progress positions.
The point of writing them down is so anyone reading the project
later — including future-me — can see the *why* and challenge it on
first principles, not just infer it from the code.

The high-level design philosophy: **build a real first computer,
not a polished modern abstraction**. Hide nothing; expose
fundamentals; preserve the period faithfully unless there's a
specific reason not to. Everything below is downstream of that
posture.

---

## Era choice

### Why classic Mac OS, not Windows / DOS / Linux / iPad?

The intended audience is a young kid encountering "a computer" for
the first time. The differentiating goal is **showing how
computers actually work** — file system, applications, menus,
windows, keyboard, mouse — not "let them tap on something." A
modern touch tablet is excellent at content consumption and
app-mediated experiences, but is optimized away from the
visible-files / local-state / direct-manipulation metaphors that
chimebox wants to expose.

Within "real desktop OS in an emulator," the candidates were:

- **Modern Linux desktop** (Raspberry Pi OS desktop variant): too
  busy, too configurable, too internet-aware for a kid kiosk; hard
  to lock down. A great desktop OS, just optimized for different
  goals.
- **Windows 9x in DOSBox/Win3.1+ emulator**: a strong contender,
  and explicitly on the roadmap as a future second platform. Lost
  the first-platform race because:
  1. The classic Mac UI is famously kid-friendly: visible
     metaphors (folders look like folders, apps live on the
     desktop), forgiving error messages, and a "real" menubar.
  2. The classic-Mac software library has more curated
     kid-content (Kid Pix, MacPaint, HyperCard, Cosmic Osmo,
     Lemmings, Glider, etc.) than any other era.
  3. The chime is iconic.
- **DOS straight**: too text-heavy for first impressions; saved
  for later when the kid is ready for "text is a real interface."
- **Apple II / Commodore 64 / etc.**: also great computers in
  their own right. Set aside for the first target experience
  because they have more typing, fewer direct-manipulation
  desktop metaphors, and a larger gap from what a young child
  recognizes as "a computer."

Mac OS won the "first impression" battle. Windows-era machines
are explicitly on the roadmap as a sibling configuration; the
project is designed to support multiple emulator targets even
though v1 ships Mac-only.

### Why Mac OS 8.1 specifically?

Within classic Mac OS the candidates were System 7.5.5, Mac OS 8.1,
and Mac OS 9.x. Each was considered:

- **System 7.5.5 / 7.6**: lighter; the early-Mac aesthetic many
  retro fans love. Skipped for first-platform because some kid-
  era apps target 8.x specifically and 8.1's UI affordances
  (contextual menus, Platinum theme) feel a bit more polished
  for a first encounter.
- **Mac OS 8.1**: the sweet spot for this project. Late enough
  for Platinum UI, contextual menus, HFS+ and broad 68k
  application compatibility; early enough to remain firmly
  classic Mac OS without OS 9's complexity creep.
- **Mac OS 9.x**: more mature in places but also begins to expose
  the seams where Mac OS was sliding toward OSX. Heavier;
  introduces Sherlock and other features that don't fit a
  no-internet kiosk; asks for more host CPU.

Mac OS 8.1 maximized the value of the period without compromising
the era feel. A future multi-OS bootpicker (roadmap) would let the
same chimebox boot 7.5.5, 8.1, or 9.x selectively; until then 8.1
is the default.

### Why the Quadra 650 ROM?

Quadra 650 is a 68040 Mac from 1993 — the apex of the 68k era,
just before the PowerPC transition. The ROM and BasiliskII model/
CPU settings together define the emulated machine identity, and
this combination gives broad late-68k compatibility while clearly
excluding PowerPC-only software.

We picked it because:

- **Infinite Mac uses the same combination** for its 8.1-on-Quadra-650
  configuration. We piggyback on their proven combination rather
  than blaze a new path.
- **Quadra-class 68040 is the "standard target"** for late-period
  68k apps; everything that runs on this emulator sees a
  consistent machine.
- **The era pacing is right.** Fast enough that nothing feels slow
  for a kid; not so fast that it stops feeling vintage.

Trade-off: PowerPC software is excluded. Some classic apps
(later HyperCard variants, some games) are PowerPC-native and
won't run. The shortlist (`docs/shortlist.md`) is curated around
this constraint and finds plenty of kid-relevant 68k titles.

PowerPC support would require switching to SheepShaver (a
different emulator with different quirks); not planned for v1
because the 68k library is more than sufficient.

---

## Hardware choices

### Why Raspberry Pi 5?

We considered three categories:

1. **Real vintage Mac hardware** (an actual Performa or Quadra).
   Pros: maximally authentic; the kid is touching the real thing.
   Cons: fragile (>30 years old, capacitors fail, hard drives
   die), expensive on the secondary market, hard to maintain or
   replace, can't be snapshotted/reset, ROM/disk imaging is
   one-way, no good "kid breaks it" recovery path.
2. **Other SBCs** (Pi 4, Pi 400, Orange Pi, Rock 5, etc.). Pros:
   similar trade-offs to Pi 5. Cons: smaller community, less
   well-tested at the BasiliskII level, fewer accessory ecosystems.
3. **Raspberry Pi 5**. Pros: enough horsepower for our workload
   (4× Cortex-A76 @ 2.4GHz; emulator uses 1 core saturated, ~75%
   total CPU headroom remaining), a great accessory ecosystem
   (Argon One V3 case, NVMe HAT, official active cooler, PiKVM
   compatibility), big community, mature Bookworm/Trixie OS,
   easy to image / clone / restore.

Pi 5 was the obvious choice as the **required target** for v1.
The **validated daily-driver configuration** is Pi 5 + Argon One V3
+ NVMe + active cooling — that's what the dev kiosk runs and what
the docs recommend, but the project's Ansible roles work against
any Pi 5 (with or without the Argon case; the role is opt-in).
Real-world thermal validation: during peak load (SimCity 2000
emulation) the SoC stays around 47–48°C — well under any throttle
threshold.

### Why BasiliskII (not Mini vMac, SheepShaver, qemu)?

- **Mini vMac**: targets earlier Mac models (Plus through SE/30
  range, 24-bit memory only). Won't run Mac OS 8.1.
- **SheepShaver**: PowerPC emulator. We don't need PowerPC for
  Mac OS 8.1 at the era we want; SheepShaver is the right tool
  for a future Mac-OS-9.x configuration.
- **qemu**: powerful general emulator but its 68k Mac support is
  weaker than BasiliskII's; the active community, accumulated
  bugfixes, and tooling are all on BasiliskII for this combo.
- **BasiliskII**: the best-supported path we found for this exact
  target — Linux-native, packaged on Debian/Raspberry Pi OS,
  proven with Quadra-class Mac OS 8.1 setups, and familiar in the
  Infinite Mac ecosystem.

BasiliskII has known quirks (extfs save behavior is app-specific;
JIT works on x86 but not aarch64; init_grab semantics interact
oddly with remote pointers) but each is documented and worked
around in this project. The familiarity tax is paid; switching to
a different emulator would re-pay it.

### Why aarch64 / native ARM?

Pi 5 is ARM (aarch64). Two paths exist for emulator binaries on
ARM:

1. **Native aarch64 binary** — `apt install basilisk2` on Pi OS
   gives this. CPU runs the emulator's interpreter loop directly;
   no extra translation. Fast.
2. **Run an x86 BasiliskII under qemu-user**: would let us use
   x86-only features like JIT. Adds ~10x overhead for nominal
   gain.

Native won. JIT was historically x86-only and is not reliable on
aarch64, so for chimebox's workload we lose no user-visible
capability by running the native aarch64 interpreter. Pi 5 has
enough headroom for the curated Mac OS 8.1 use case.

---

## Platform / distro choices

### Why Raspberry Pi OS (not vanilla Debian, not Ubuntu)?

- **Vanilla Debian**: works on Pi 5 but lags on Pi-specific bits
  (firmware, hardware acceleration, kernel patches). The
  out-of-box experience requires extra package work.
- **Ubuntu**: heavier; we don't need any of Ubuntu's user-facing
  desktop polish; Snap is incompatible with the kiosk use case.
- **Raspberry Pi OS**: officially supported by the hardware
  vendor; firmware and kernel are tuned for the Pi; Pi Imager has
  first-class flashing UX; community knowledge is concentrated
  here.

The "Lite" variant (no desktop) is the right starting point — we
build our own X session, we don't want a competing desktop
manager.

### Why Trixie?

We've targeted Debian Trixie (the Pi OS variant, "Lite") from the
start. Bookworm (Debian 12) was the prior stable release when the
project began, but Trixie's security-support window runs further
out (to August 2028 vs. June 2026 for Bookworm), and both ship
`basilisk2` for aarch64. Trixie was the right fit on day one and
hasn't given us a reason to revisit.

### Why Ansible (not shell scripts, not Salt/Chef/Puppet)?

Ansible is the right level of machinery for a single reproducible
Pi appliance:

- **Shell scripts** (existing pattern in `scripts/`): great for
  ad-hoc operations on an existing chimebox; bad for full
  provisioning because there's no idempotency model.
- **Salt / Chef / Puppet**: overkill for a single-Pi kiosk; need
  a master server or daemon component or both.
- **Ansible**: agentless, runs over SSH, declarative, idempotent
  out of the box, single playbook + roles + inventory. Validated
  end-to-end against real Pi 5 hardware.

### Why autologin → startx (not chimebox.service / fully systemd)?

When v1 was being built, the pragmatic question was "how does the
kiosk session start?" Two paths:

- **autologin → bash_profile → exec startx**: classic,
  well-understood, debuggable from a tty, no DBus/X-launcher
  dance. The X session inherits the user's environment naturally.
- **chimebox.service running startx via systemd**: cleaner
  long-term; better integration with systemd journal; restartable
  in place. But: more complex; tty/dbus interactions can be subtle;
  harder to debug from outside.

v1 ships the autologin path. The systemd unit is **also installed
but disabled**; flipping it on is a v2 milestone once the autologin
path's edge cases (boot order, post-update behavior, log
visibility) are well-understood.

### Why prefs file as source of truth (not BasiliskII CLI flags)?

Debian's BasiliskII has a Gtk variant where CLI flags don't
override prefs; the *only* way to set most options (RAM, disk
list, model ID, mouse mode, etc.) is via the prefs file at
`~/.config/BasiliskII/prefs`. Once we discovered that, we
committed: prefs is the One Source of Truth, generated by Ansible,
re-asserted on every provisioning run. Drift is corrected
automatically.

---

## Network / security choices

### Why no internet for the kid?

Two related reasons:

1. **Period-era browsers don't render the modern web.** Mac OS 8.1
   shipped with Internet Explorer 4.x and a contemporaneous
   Netscape. They run, but every site they could reach in 2026
   would be either broken (TLS-only, modern JS, modern HTML) or
   forwarded to a fallback page. The kid would see a "the
   internet doesn't work" experience.
2. **Kid safety.** The internet of 2026 is not a place a young
   child should explore unsupervised. A computer that simply
   *can't* reach the internet (by configuration, not honor
   system) is a stronger guarantee than parental controls layered
   on top of an internet-connected device.

In v1, BasiliskII is configured without guest Ethernet (`ether`
unset, `udptunnel false`). The Pi may have SSH/admin networking,
but the emulated Mac has no TCP/IP route, no DNS, no browser path,
no bridged interface. Future network features (inter-chimebox
AppleTalk, bridge appliance) must be explicit opt-ins through
allowlisted-only paths. Verifying the no-egress invariant
end-to-end (firewall rules + emulator config) is tracked as
`v2-no-internet-egress` in the roadmap.

If the kid asks "where's the internet?" we explain that this
computer comes from an era when the internet existed but was
smaller, slower, less media-heavy, and not the modern web. We're
intentionally not connecting it because today's web is both
technically incompatible with the period browsers AND not
appropriate for unsupervised young use.

### Why allowlist-only for v3 bridge (not Discord/iMessage with parental controls)?

The bridge appliance exposes the Mac to specific people
(matrix user IDs, email From addresses, etc.) and *only* those
people. Parental controls on a general-internet chat platform are
a probabilistic guarantee; an allowlist is a deterministic one.

A general-internet chat platform also asks the kid to perform
"adult internet" mental moves (handle DMs from strangers, deal
with unexpected media, recognize phishing) that we explicitly
defer until they're older. The bridge appliance keeps those
mental moves out of the picture for now.

### Why period-correct on the chimebox side of the bridge appliance?

The whole point of chimebox is that the kid experiences a real
1998 computer. Putting a Discord-shaped icon on the desktop with
modern conversation conventions breaks the period and sends a
mixed signal: "this is honest computing, except sometimes it's
modern when convenient." Routing modern protocols through an
AppleShare-shaped server preserves the chimebox-side experience
("just another Mac on the network") while letting modern devices
participate via their native protocols.

This is the exception policy crystallized: **the chimebox's
front of house is period-correct; the back of house can be
whatever's most useful.**

---

## Software choices

### Why Apache 2.0 license?

- Matches Infinite Mac upstream, which we depend on for some
  build-pipeline tooling. Licenses align cleanly.
- Permissive enough that hobbyists can fork without legal
  friction.
- Includes patent grant, which copyright-only licenses
  (MIT, BSD-3) don't. Useful long-term hygiene.
- Familiar to most contributors; not a surprise.

### Why curated software shortlist (not "everything that runs")?

The Infinite HD library has hundreds of titles. Most of them are
either (a) tools an adult would use (developer, business
productivity, system maintenance), (b) genre-specific to a kid
who's already read the Mac-history books, or (c) age-inappropriate
for our target user.

Putting all of them on the kiosk's Desktop would be visually and
cognitively overwhelming. The kid would default to the first 5
icons they noticed, not because those are best, but because
they're first.

The curated shortlist (`docs/shortlist.md`) is tier-ranked from
"S" (must-have for first session) to "C" (later, when older). A
small Desktop set with great stuff beats a giant Desktop with
random stuff.

### Why no Netscape / Internet Explorer / browsers?

Reflexive answer: no internet, no browser. Deeper answer: even if
the chimebox had internet, period-era browsers can't render the
modern web; the experience would be 100% broken pages.
Pretending would be worse than not having a browser at all.

If the kid asks "where's the internet?" we explain that this
computer comes from an era when the internet existed but was
smaller, slower, less media-heavy, and not the modern web —
honest about what an era is.

---

## Kid-experience principles

### Why "honest computing" (real file system, real protocols, real OS)?

Modern kid-tablet UX teaches "tap things and content appears" but
hides everything underneath. Chimebox teaches:

- Files live in folders. Folders live in disks. Disks live in
  the computer.
- You save with File → Save As. The file goes to a place. You
  can put it in a different place by dragging.
- Apps are programs. Programs are files. (Classic Mac files have
  resource forks, so moving them between old and modern
  filesystems needs care — that's a feature of the era's
  honesty, not a bug.)
- Two computers can talk to each other. The connection is real
  cables (or radio). The protocol is named (AppleTalk, AppleShare).

Each of those is a foundational mental model that a tablet UX
optimizes away. Period-correct Mac OS exposes them naturally.

### Why kid-proof but not dumbed down (full Finder, not At Ease)?

Apple's "At Ease" was a 1990s shell that simplified the Mac for
kids by hiding the Finder behind a launcher of large buttons.
For chimebox, At Ease optimizes away the exact concepts we want
the kid to encounter: disks, folders, files, menus, and ordinary
Finder navigation. That makes it a poor default — though it
remains a period-correct opt-in for users who need a simpler
launcher (`v2-at-ease-role` in the backlog).

The chimebox v1 default is: full Finder + curated content +
adult-operated snapshot/reset path + adult oversight. The kid
can break things, and when they do, an adult restores via
`scripts/kid-reset.sh`. They learn the real interface the way
grown-ups use it.

### Why safe but not isolated?

Three categories of "outside world" feature are designed:

1. **Outside World extfs / USB stick** — physical, supervised
   handoff. An adult plugs a USB stick in; the kid sees the
   contents.
2. **Inter-chimebox AppleTalk** — virtual but allowlisted.
   Family-only network of chimeboxes; period-correct file
   sharing.
3. **Bridge appliance** — modern devices participate via
   AppleShare facade. Adults retain full control over what's
   bridged where.

All three are *additive*: the kiosk works fully without any of
them. None of them changes the fundamental "no general internet"
posture. Each opens a single, supervised channel to the outside.

---

## Period-correct exception policy

The default principle: chimebox's Mac-side experience should be
faithful to 1998. Exceptions are allowed when they fall into
well-defined categories AND pass an explicit test.

### Exception categories

1. **Safety / lockdown** — features that didn't exist in 1998 but
   protect the kid. Examples already in v1: the supervisor
   loop's crash-loop protection, the bedtime-sentinel pattern,
   the snapshot/reset machinery, the boot-splash hiding the
   Linux underlayer. These are invisible to the kid but real.
2. **Outside-world bridges** — the AppleTalk + bridge-appliance
   features (designed; v1 ships only the extfs / USB-mount
   piece). Each preserves period UX on the chimebox side while
   exposing modern protocols underneath.
3. **Accessibility** — accommodations a user needs to engage with
   the period interface at all (zoom, alternative input, screen
   reader). If a user can't comfortably read 1998-era 9pt
   MacRoman text or can't manage a 1998 mouse, accessibility
   helpers are a reasonable exception.

### Exception test

An exception is allowed only if ALL of these are true:

1. **Period-fidelity preserved on the Mac side** — except when
   the exception is explicitly accessibility-related.
2. **Invisible or in-period-explainable to the kid** — the kid
   doesn't need to break out of the era to understand it.
3. **Opt-in when it changes the Mac-side experience** — host-side
   plumbing can be on by default; anything the kid sees is
   opt-in.
4. **Narrower alternative considered first** — and rejected for a
   stated reason.
5. **Rollback path documented** — including how to remove the
   exception if it proves wrong.

### Non-examples (would NOT pass the test)

- A Discord/iMessage-shaped icon on the Mac desktop (breaks #1
  and #2; the bridge-appliance design is the alternative).
- A Mac-side browser pointed at a modern proxy (breaks #1 and
  contradicts the no-internet posture).
- Modern-style notifications/popups inside Mac OS (breaks #1).
- A "kids' mode" launcher hiding the Finder by default (breaks
  the entire "honest computing" premise; should remain opt-in).

Each accepted exception, when introduced, gets a paragraph here
explaining which category it falls under and how it satisfies
the test.

---

## Repo / community choices

### Why no copyrighted material in the repo?

Apple ROMs, Mac OS system software, and most period applications
remain copyrighted. The chimebox repository deliberately ships
none of them: no ROM files, no disk images, no system-software
binaries.

Users obtain those artifacts themselves through `disk-prep/`
tooling that walks them through the build/fetch process from
sources they're responsible for. The Apache 2.0 license on
chimebox covers our code only; it does not grant any rights to
Apple's ROMs or system software. See `LICENSING.md` for the
authoritative position on each layer.

Source-only release is the supported public distribution model.
Prebuilt SD-card images, prebuilt disk images, and configured
hardware containing copyrighted ROMs/system disks/software are
out of scope and would require separate legal review.

### Why submodule strategy for Infinite Mac?

Submodule is the standard "we depend on this code, but it's not
ours" pattern. Alternatives:

- **Vendor it** (copy the relevant files in): cleaner from the
  user's perspective but creates a maintenance burden as
  Infinite Mac evolves.
- **Pull at install time** (`apt`-style): Infinite Mac doesn't
  publish prebuilt artifacts in a way our `disk-prep/` tooling
  could consume.
- **Submodule**: explicit version pin, init-on-demand,
  clean separation of upstream from our additions.

Submodule it is.

### Why the `local-*` gitignored personalization pattern?

The role file structure deliberately accepts user overrides at
predictable paths. For example: `roles/boot-splash/files/
local-splash.png` is gitignored; users drop their own image and
override the variable to use it. This lets families personalize
their chimebox without the personalization leaking into the
public repo.

---

### Why X11 / startx (not Wayland / direct DRM / direct SDL)?

Modern Raspberry Pi OS increasingly defaults to Wayland-based
session managers (Wayfire, Labwc). For chimebox v1 we deliberately
stay on X11 because:

- BasiliskII / SDL's path is well-tested under X11; the
  pointer-event handling, keyboard grabs, and modeset hooks all
  have known-good behavior.
- A minimal X session with no desktop environment and no window
  manager (well, matchbox-window-manager for SDL focus
  semantics) is predictable and small.
- Wayland adds compositor / session complexity without solving a
  problem chimebox currently has.
- We'll revisit if BasiliskII / SDL Wayland support becomes
  clearly better, or if X11 becomes unmaintained on Pi OS.

### Why mutable root (not immutable / overlayfs from day one)?

A read-only root with tmpfs overlay would be more robust against
power-yank corruption, but v1 deliberately accepts a mutable root
because:

- Provisioning is still iterating; ergonomic Ansible re-runs
  matter more right now than rollback robustness.
- The `kid-reset.sh` + snapshot machinery already covers the
  "kid broke the Mac" case at the disk-image level, which is
  the realistic damage vector.
- Read-only root is a real reliability milestone; it's tracked
  as `v2-readonly-root` in the roadmap.

When provisioning + day-2 ops stabilize, immutable root becomes
an attractive next step. Until then mutable root stays.

### Why not just use Infinite Mac in a browser?

Infinite Mac is excellent and we lean on its tooling and disk
images. We don't use it as the chimebox runtime because:

- A browser-hosted emulator is great for demos but less
  appliance-like; hard to lock down, hard to make the kiosk
  feel like a real first computer.
- Adds the modern host browser as an attack surface and
  failure mode.
- Complicates the offline guarantee — the runtime expects
  internet to fetch chunks unless extensively prepared.
- A native BasiliskII process gives simpler boot-to-kiosk
  behavior and local state that doesn't depend on a browser
  cache.

We do use Infinite Mac as upstream for the disk-prep pipeline,
prebuilt chunk CDN, and reference for what BasiliskII config
works. The runtime is intentionally separate.

---

## When to revisit

This document captures the position as of pre-public release. Any
of these decisions can and should be challenged on first
principles when:

1. A new emulator becomes substantially better at this combo.
2. A new Pi (or alternative SBC) shifts the price/performance
   curve enough to matter.
3. Apple changes its position on the ROMs / disk images (in
   either direction).
4. The kid-target audience shifts (older, younger, special needs).
5. The community settles on a different period (e.g., chimebox-2
   could be PowerPC-era).
6. **A safety / threat-model change** — e.g., a credible new
   side-channel for content reaching the kiosk.
7. **Licensing or source-availability change** from Infinite Mac,
   Macintosh Garden, Apple, or the emulator upstreams.
8. **Debian / Raspberry Pi OS package changes** — especially
   `basilisk2` removal or breakage in the apt repo.
9. **Hardware reliability evidence** accumulating — storage wear,
   thermal throttling, power-yank corruption rates.
10. **Real child-use evidence** — repeated frustration with a
    particular interface element, ignored features, or requests
    for capabilities the current era cannot satisfy.
11. **Accessibility need** from any target user.
12. **Public-release / community-support burden** — setup too
    hard, docs misunderstood, recurring user mistakes.
13. **Distribution-model change** — e.g., source-only hobby
    project → prebuilt images / hardware / commercial product.
14. **Maintenance burden** — if Ansible / disk-prep / native
    setup becomes harder than an alternative.

Each row above is a judgment call, not a permanent law.
