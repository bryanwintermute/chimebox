# Software shortlist for chimebox

This document maps software in the Infinite Mac library
(`third_party/infinite-mac/Library/`) onto recommendations for a
chimebox kiosk targeting a young user (~6.5 years old). It captures
the "what to put on the Desktop" decision and reasoning.

It also notes platform implications: which titles hint at whether
adding a different emulator/OS later (Mac OS 9, Mac OS X, Apple II,
DOS) would actually be worth it for kid use.

## How to use this document

1. Run the full disk-prep on a Mac. This produces `InfiniteHD.dsk`
   with all of these titles installed.
2. Push it via `scripts/push-disks.sh` to the Pi.
3. Boot the Mac, mount the library disk.
4. Manually curate the kiosk Desktop using Tier S as the starting set
   (or your own preferences below). The default Mac OS Finder view
   is fine; you don't need a special launcher.
5. Hide adult tools (Developer/, etc.) into nested folders.

## Tiers

### Tier S — set up first, on the Desktop

The "no notes, this is exactly what kid-Mac was made for" titles. Each
of these is genuinely good for a 6-to-8-year-old's *first computer*
experience. Set up first, leave on the Desktop.

| Title | Library path | Why for kids |
|---|---|---|
| **Kid Pix** | `Graphics/Kid Pix.json` | THE drawing-for-kids app. Stamps, sound effects, the famous dynamite eraser. Designed for ages 3-12. Drag a photo of yourself in, put a mustache on it, hear "wackadoodle". Best single addition to a kid Mac. |
| **HyperCard** | `Multimedia/HyperCard.json` | "Make your own software" for kids. Even before authoring, browsing pre-built stacks (like Cosmic Osmo) is delightful. |
| **Cosmic Osmo** | `Games/Cosmic Osmo.json` | HyperCard "stack-as-universe" by the Myst people. Clickable rooms, hidden interactions, no reading required. Excellent for the youngest kids. |
| **Lemmings** | `Games/Lemmings.json` | Puzzle game with adorable green-haired creatures. Great for "I need a builder here" problem-solving. |
| **Glider** | `Games/Glider.zip` | Paper airplane navigates household objects (toaster, cat). Charming, low-pressure, beautiful sprite art. |
| **Tetris** | `Games/Tetris.json` | Universal. May be too young for the full game; tier-S because the visual appeal is undeniable. |

### Tier A — add as the kid is ready (or on demand)

Slightly more reading or hand-eye coordination. Drop into a Games or
Apps folder one Finder click away from the Desktop.

| Title | Notes |
|---|---|
| **MacPaint 2.0** | Simpler than Kid Pix; pure drawing/painting fundamentals. Good "real artist tool" feel. |
| **The Oregon Trail** | Iconic, educational, but text-heavy. Good "with you" activity. |
| **Pipe Dream** | Fast-paced plumbing puzzle. |
| **StuntCopter** | Drop a paratrooper into a moving wagon. Pure simple fun. |
| **Sokoban** | Push-the-boxes puzzle. Increasingly hard levels. |
| **Battle Chess** | Animated combat when chess pieces capture each other — much more engaging than regular chess at this age. |
| **Snood** | Bubble-shooter puzzle. Famously addictive. |
| **Pararena** | Floating-robot sport. Fast and visual. |
| **Quinn 1.3.1** | Polished Tetris variant. |
| **Apeiron** (Ambrosia) | Centipede clone with great audio. |
| **Maelstrom** (Ambrosia) | Asteroids clone, frenetic. |
| **Bubble Trouble** (Ambrosia) | Bouncy bubble-popper. |
| **Swoop** (Ambrosia) | Polished Galaxian-clone. |

### Tier B — save for later (~age 8+ or when interest emerges)

Great titles, but need reading skill or strategic thinking. Keep
installed but not prominent.

- **SimCity** / **SimCity 2000** — city building; SC2000 is the more
  visually rewarding one
- **The Secret of Monkey Island** — classic adventure, lots of reading
  + humor
- **Civilization** — too complex now, but pin for later
- **Risk** — board game, needs reading
- **Indy and The Last Crusade** — adventure, reading-heavy
- **Pathways Into Darkness** — Bungie's pre-Marathon game; closer to
  RPG than FPS, but still mature

### Tier C — skip from the kid Desktop entirely

Either too violent, too hard, or too text-heavy. Don't *delete* them
(some are genuinely amazing for older kids / adults), just don't put
them in front of a young child.

Marathon trilogy, DOOM, Prince of Persia, Dark Castle, Spectre, A-10
Attack!, F-A-18 Hornet, Hellcats Over the Pacific, Warcraft I & II,
Strategic Conquest series, Continuum (cool but punishing), Solarian II,
Avara, Troubled Souls.

### Tier P — "this is what computers used to be" — show, don't push

Adult-oriented titles that are cool to demo together when the kid
asks "what's that one?" Don't put on the Desktop.

- **Graphing Calculator** — the famous Apple Easter egg, beautiful 3D
  math visualizations
- **Kai's Power Tools** / **KPT Bryce** — psychedelic image filters
  and 3D landscapes
- **Adobe Photoshop 1.0** — historical curiosity ("look how much this
  used to cost")
- **MacBench** — "how fast is the Mac?"
- **Aldus PageMaker 1.2** — desktop publishing's birth
- **QuarkXPress 1.1 / 2.11 / 3.1** — same era

### Productivity — expose, don't push

Set up but don't surface to the Desktop unless asked. Useful when the
kid wants to "do real-computer stuff."

- **ClarisWorks** — the Microsoft Office of 1995, kid-accessible
  word/draw/spreadsheet/database in one
- **MacWrite / MacWrite 2.2** — pure word processing
- **FileMaker II** — databases (genuinely useful pattern for older
  kids)
- **Microsoft Word** — for the "this is what mom uses" recognition

## Suggested initial Desktop layout

After running disk-prep and mounting the library, manually arrange
the Desktop to look approximately like this:

```
Macintosh HD                        ← built-in
[Kid's Drawings folder]             ← create this; empty, for saves
KidPix                              ← Tier S
MacPaint                            ← Tier A
HyperCard                           ← Tier S
Cosmic Osmo                         ← Tier S
Lemmings                            ← Tier S
Glider                              ← Tier S
StuntCopter                         ← Tier A
Trash                               ← built-in
```

Eight to ten icons. Anything more is clutter. The full library lives
on `Infinite HD` (which she can browse if she wants) but doesn't need
to be on the kiosk Desktop.

## Platform implications for the chimebox roadmap

This was the bonus question: what does the library suggest about
whether to add SheepShaver / Mac OS 9 / Mac OS X / Apple II / DOS later?

### Mac OS 9 via SheepShaver (PPC) — low ROI for kid use

Most of the kid-friendly titles in the Infinite Mac library run on
the current Quadra 650 / Mac OS 8.1 / 68K setup. Mac OS 9 mostly
opens up:

- Late Marathon (Infinity in native PPC)
- Diablo II
- Total Annihilation
- Quake III Arena
- Civilization II/III

…all of which are 12+ titles, not 6.5yo titles. **Defer until the
kid is older, or until you want it for yourself.**

### Mac OS X via PearPC — small library, slow emulator

About 5 titles in the library are Mac OS X-only (look for the "X"
suffix: GraphicConverter X, Pixelmator 1.0, Comic Life 1.0.1,
Audion X, Iconographer X, etc.). Of those, **Comic Life** is genuinely
kid-friendly (drag photos, build comic strips with speech bubbles —
perfect for a 7yo). **Pixelmator** is good once she outgrows Kid Pix.

But PearPC is the slowest emulator chimebox supports; the heavy lift
isn't justified by the small library win. **Defer.**

### Apple II / DOSBox / other platforms — strongest case for "next platform"

Several canonical kid-edu titles are **not in the Infinite Mac
library** because they were never Mac titles:

- **Number Munchers** (Apple II / DOS)
- **Where in the World is Carmen Sandiego?** (DOS)
- **Reader Rabbit** (DOS)
- **Mavis Beacon Teaches Typing** (DOS later, but most associated
  with DOS)
- **Crystal Caves** (DOS)
- **Commander Keen** (DOS)
- **Jumpstart Kindergarten / 1st Grade / etc.** (DOS / Mac, mostly
  late 90s)

If the kid takes to retro computing and exhausts the Mac titles,
the next platform expansion is probably **DOSBox + Win 3.1 / DOS**,
not more Mac. That maps to the `v3-generalize-beyond-mac` roadmap
item: refactor the `chimebox` Ansible role to be emulator-agnostic
so a `dosbox` emulator role becomes a peer of `basiliskii`.

### Sticky recommendation

For now, the **Quadra 650 + Mac OS 8.1** target is well-matched to
kid-software, and adding emulators speculatively would add complexity
without a clear win. Wait for a signal: "I want to do X and there's
no Mac version" → that tells you which platform to add next.

## Sources / further reading

- Infinite Mac's curated software library: this repo's
  `third_party/infinite-mac/Library/`
- Macintosh Garden: <https://macintoshgarden.org/> — broader
  abandonware archive
- Bungie's Marathon Open Source: <https://alephone.lhowon.org/> —
  modern engine if you want to add Marathon later
- For the DOS expansion: <https://archive.org/details/softwarelibrary_msdos_games>
