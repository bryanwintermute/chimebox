# Design: Printer bridge (Mac → modern PDF / printer)

**Status:** design sketch (not yet implemented). v2 feature, can
ship independently of v1; reuses BasiliskII's serial-port
emulation directive (`seriala`).

**One-line vision:** the Mac sees what looks like a real
LaserWriter on its serial port. Anything the user prints from any
Mac app produces a PDF in a shared folder a few seconds later.
Optional adult-mode forwards to a real network printer via CUPS.

---

## Why a printer bridge

- **Period-correct:** LaserWriter is *the* Mac OS 8.1-era printer.
  The driver ships with System 8.1; users print with the same
  Print dialog they'd have used in 1998.
- **Universal:** any Mac app that can print works (SimpleText,
  Kid Pix, MacPaint, HyperCard, Lemmings, Tetris score sheets…).
  No per-app integration.
- **Lossless:** PostScript is structured and
  resolution-independent. The PDF we produce is identical to
  what would have come out of a real LaserWriter, modulo font
  substitution.
- **Adult bonus:** the same daemon can forward jobs to a real
  network printer via CUPS — useful for "print this kid's drawing
  to the office printer for the fridge."
- **Composability:** integrates cleanly with the bridge appliance
  vision (`v3-bridge-appliance-design.md`) — the prints folder
  could be exposed as an AppleShare drop box for family-side
  retrieval.

---

## Architecture

```
                  Pi running BasiliskII
   ┌────────────────────────────────────────────────────┐
   │                                                    │
   │  BasiliskII (Mac OS 8.1)                           │
   │  ┌──────────────────────────────────────────────┐  │
   │  │ LaserWriter driver in System Folder          │  │
   │  │   ↓ writes PostScript                         │  │
   │  │ Serial port A (config'd in Chooser)           │  │
   │  └────────────────┬─────────────────────────────┘  │
   │                   │                                │
   │              ┌────▼─────┐                          │
   │              │ pty slave│ /dev/chimebox-printer    │
   │              │  end     │ (stable symlink, owned   │
   │              └────┬─────┘  by chimebox group)      │
   │                   │                                │
   │              ┌────▼─────┐                          │
   │              │ pty      │                          │
   │              │ master   │ ← held by socat          │
   │              │ end      │                          │
   │              └────┬─────┘                          │
   │                   │ stdin                          │
   │              ┌────▼──────────────────────────────┐ │
   │              │ chimebox-print-daemon             │ │
   │              │  (Python; systemd-supervised)     │ │
   │              │                                   │ │
   │              │ - Reads PostScript byte-stream    │ │
   │              │ - Splits jobs on %!PS-Adobe /     │ │
   │              │     %%EOF / Ctrl-D markers        │ │
   │              │ - For each job:                   │ │
   │              │     · Save raw .ps (debug mode)   │ │
   │              │     · gs -sDEVICE=pdfwrite ...    │ │
   │              │     · Write PDF to prints/        │ │
   │              │     · Optional: lpr to CUPS       │ │
   │              │     · Optional: notify (matrix,   │ │
   │              │       email) via bridge appliance │ │
   │              └───────────────────────────────────┘ │
   └────────────────────────────────────────────────────┘
                            │ (optional adult-mode)
                            ▼
                    CUPS / AirPrint
                  to network printer
```

### Components per chimebox

1. **socat** (apt-installable, ~150KB) — manages the pty pair.
   Configured via systemd to spawn at boot and re-establish on
   restart.
2. **`chimebox-print-daemon`** — small Python script, reads
   PostScript from stdin, runs ghostscript, writes PDFs.
3. **ghostscript + PostScript fonts** — renders PostScript to
   PDF. Apt: `ghostscript` + `gsfonts`. ~50MB total.
4. **BasiliskII prefs change** — `seriala /dev/chimebox-printer`
   line, conditional on `chimebox_printer_enabled`.
5. **Mac OS one-time setup** — Apple menu → Chooser →
   LaserWriter → "Modem" port → close Chooser. Persists in the
   Mac System Folder.
6. **Optional CUPS integration** — package only installed if
   `chimebox_printer_forward_to` is configured.

---

## Why pty (not Unix socket, not named pipe)

BasiliskII's `seriala` directive expects a **tty-like file** —
it `open()`s the path and uses `read()` / `write()` /
`tcsetattr()`. Unix sockets don't support `tcsetattr`; named
pipes are unidirectional and don't survive close. A pty is
exactly what BasiliskII expects to talk to.

The pty's slave-end name (`/dev/pts/N`) is unstable across
reboots / process restarts, which would break BasiliskII's
prefs. **socat solves this** by creating the pty and exposing
it as a stable symlink:

```
socat -d -d \
    PTY,raw,echo=0,link=/dev/chimebox-printer,user=chimebox,group=chimebox,mode=0660 \
    EXEC:/usr/local/sbin/chimebox-print-daemon
```

`/dev/chimebox-printer` is now stable; BasiliskII references it.
socat hands the pty master end to the daemon as stdin/stdout.

---

## Job detection in the byte stream

LaserWriter emits PostScript as a byte stream. Job boundaries
are signaled by:

- `%!PS-Adobe-X.Y` — start of new job (ASCII header).
- `%%EOF` — declared end of job (PostScript convention).
- `Ctrl-D` (`\x04`) — protocol-level end-of-job (LaserWriter
  serial behavior).

The daemon's parser is a simple state machine:

```
WAITING_FOR_HEADER → BUFFERING_JOB → JOB_COMPLETE → render → WAITING…
```

We use `\x04` as the *primary* delimiter (LaserWriter always
sends it). `%%EOF` is the *secondary* check (helps if a stray
Ctrl-D shows up mid-job, which it shouldn't but defensively).

If the daemon is interrupted mid-job, the partial bytes are
saved to `prints/incomplete-<timestamp>.ps` for debugging, and
the next job starts fresh.

---

## ghostscript invocation

```sh
gs -dSAFER -dNOPAUSE -dBATCH -dQUIET \
   -sDEVICE=pdfwrite \
   -sOutputFile="$OUTPUT_PATH" \
   -
```

- `-dSAFER` — restrict file access; no ghostscript program in
  the PostScript can read host files.
- `pdfwrite` — modern, supported PDF output.
- `-` — read PostScript from stdin.

Can also produce PNG, JPEG, etc. for the "save as image" mode
(see `chimebox_printer_format` knob below).

---

## Output path conventions

```
~chimebox/prints/
├── 2026-05-06-22-30-15-Untitled.pdf
├── 2026-05-06-22-32-08-MyDrawing.pdf
└── raw/                           ← only if debug mode on
    └── 2026-05-06-22-30-15.ps
```

Filename template (configurable):

```
{date}-{title}.pdf
```

`{title}` is parsed from the PostScript header's `%%Title:`
comment if present, sanitized to `[A-Za-z0-9._-]`, max 32
chars. Falls back to "Untitled" if missing.

---

## Mac OS 8.1 setup (one-time, baked into System.dsk)

1. Boot the Mac.
2. Apple menu → Chooser.
3. Click **LaserWriter** in left pane.
4. **AppleTalk** off.
5. Right pane shows port options; pick **Modem** (corresponds
   to BasiliskII's `seriala`).
6. Click **Setup…** → choose generic LaserWriter PPD (the one
   that ships with the System).
7. Close Chooser.

These settings persist in the Mac System Folder and apply to all
print dialogs from then on. Should be added to the Tier-S
shortlist work as a one-time configuration step.

---

## Variables (Ansible role surface)

| Var | Default | Effect |
|---|---|---|
| `chimebox_printer_enabled` | `false` | Master switch (off = role inert) |
| `chimebox_printer_output_dir` | `~chimebox/prints` | Where PDFs land |
| `chimebox_printer_format` | `pdf` | Or `png`, `jpeg` (Phase 3) |
| `chimebox_printer_filename_template` | `{date}-{title}` | Output filename pattern |
| `chimebox_printer_forward_to` | `""` | Optional CUPS URI for real-printer forward |
| `chimebox_printer_keep_raw_postscript` | `false` | Debug mode: also save .ps files |
| `chimebox_printer_notify_url` | `""` | Phase 4: webhook URL for "new print" notifications |

---

## Implementation phases

### Phase 0: validate the pty + BasiliskII serial path

**Goal:** confirm that BasiliskII actually talks to a socat-
managed pty as a serial port. This is the key risk: BasiliskII's
serial emulation might require specific tty modes or
bidirectional handshake.

**Steps:**

1. socat creates pty linked to `/dev/test-printer-pty`.
2. BasiliskII configured with `seriala /dev/test-printer-pty`,
   restart kiosk.
3. Mac side: open Chooser, configure LaserWriter on Modem port.
4. Open SimpleText, type "test", File → Print.
5. Watch socat's other end with `cat`. Expect to see
   PostScript bytes scrolling.

**Success criterion:** PostScript bytes appear at socat's other
end. Then we can move to Phase 1.

**Risk if it doesn't work:** LaserWriter driver may want
bidirectional protocol exchange (the printer responds to status
queries). If so, we need either:

- A trivial mock that replies to known LaserWriter status
  queries (`\004` → `OK\r\n` or similar), or
- Switch to ImageWriter II driver (one-way bitmap printer)
  which we'd render to PNG via a custom parser.

### Phase 1: PostScript → PDF

**Goal:** Mac prints, PDF appears in `prints/`.

**Adds:**

- New Ansible role `printer-bridge`:
  - Apt: `socat`, `ghostscript`, `gsfonts`
  - systemd unit `chimebox-print-bridge.service` that runs
    socat with the daemon
  - Helper script `/usr/local/sbin/chimebox-print-daemon`
    (Python; PostScript stream parser + ghostscript invocation)
  - Output dir creation
- chimebox role's `basiliskii-prefs.j2` adds `seriala
  /dev/chimebox-printer` line, conditional.

**Validates:** the primary use case end-to-end.

### Phase 2: ImageWriter mode (the kid's-bitmap-printer path)

**Goal:** alternative output mode for the period-correct
"my drawing came out of a dot-matrix printer" feel.

**Adds:**

- ImageWriter II driver-side detection in the daemon (different
  byte protocol than PostScript).
- Bitmap parser (~few hundred lines) that interprets
  ImageWriter ESC sequences and produces a PNG raster.
- New format option in the role config.

**Validates:** for users who want bitmap output (Kid Pix-style
"perfect dithered drawing") without going through PDF.

### Phase 3: Real-printer forwarding (CUPS)

**Goal:** PDFs auto-forward to a network printer.

**Adds:**

- Optional CUPS install (only when forwarding configured).
- Daemon: after PDF write, also invoke `lpr -P <printer>` if
  `chimebox_printer_forward_to` is set.
- Test/discover commonly-shared CUPS targets (AirPrint via Avahi,
  IPP everywhere, etc.).

**Validates:** the adult use case ("print to the office printer
from a Mac OS app").

### Phase 4: Notifications / family integration

**Goal:** when a kid prints a drawing, family knows.

**Adds:**

- After successful PDF write, post via webhook (Matrix-bridge
  / email / Discord depending on family setup) — naturally
  composes with the v3 bridge appliance.
- Could be a separate daemon watching `prints/` rather than
  baked into the print daemon; `inotifywait`-driven.

**Validates:** the "fridge gallery" workflow a family might
actually use.

---

## Security / safety design

| Concern | Mitigation |
|---|---|
| PostScript program reads host files | `gs -dSAFER` blocks `file` operator and disk access |
| PostScript program escapes to a shell | `-dSAFER` blocks the entire PostScript file/exec syscall surface |
| Daemon runs as wrong user | Runs as a dedicated `chimebox-print` system user, not chimebox or root |
| Disk-fill DoS via massive print jobs | Per-job size limit (configurable, default 50MB raw PS) |
| Disk-fill DoS via many small jobs | Output-dir cleanup cron: keep last N or M days |
| Forwarded job bypasses adult review | Phase 3 forwarding requires explicit config; default off |

---

## Open questions

1. **LaserWriter driver: one-way or two-way protocol?**
   Phase 0's whole purpose is to find out. If two-way, we mock
   the responses (`%%[ status: idle ]%%` etc.) — well-documented
   in PostScript Printer Description files.

2. **Font substitution.** ghostscript ships URW++ replacements
   for Times/Helvetica/Courier/Symbol. They look fine for kid
   drawings but professional documents might notice the
   difference. Document as a non-issue for chimebox use case.

3. **Page size.** LaserWriter defaults to US Letter. If Mac OS
   8.1 page setup says "A4" we should respect that — does
   ghostscript pick up `%%DocumentMedia` from the PostScript or
   does it need a `-sPAPERSIZE=a4` flag? Test in Phase 1.

4. **Multi-page jobs.** Is each Print → multi-page job a single
   PostScript stream with multiple `showpage` calls? Yes —
   `pdfwrite` handles that natively as a multi-page PDF.

5. **Print Monitor / spooling.** Mac OS 8.1's PrintMonitor
   spools jobs to a folder before sending. Does this affect our
   flow? Probably not — bytes still arrive on the serial port
   one job at a time. Worth verifying in Phase 0.

6. **Idle behavior.** What does the daemon do when no jobs are
   coming? `read()` blocks; that's fine. socat keeps the
   connection open. No special handling needed.

7. **Multiple chimeboxes printing to one CUPS target.** If
   forwarding is configured on multiple chimeboxes pointing at
   the same printer, jobs interleave correctly because CUPS
   handles concurrency. No coordination needed.

---

## Out of scope for this design

- **Bidirectional Mac-side notifications** (e.g., "print
  succeeded" / "out of paper" from CUPS back to Mac OS).
  The LaserWriter driver supports the protocol but we'd have
  to maintain status-query handling in the daemon. Not worth
  it for kiosk use.
- **Color printing.** Mac OS 8.1's LaserWriter driver is
  monochrome. Printing color requires a different driver
  (ColorSync) and is era-inappropriate for our setup.
- **Print preview.** Mac OS 8.1 doesn't have native print
  preview; any preview happens app-side. Out of scope.
- **Fax via the daemon.** Some Mac apps shipped fax drivers in
  the era; we don't go there.
- **Direct AppleTalk-printer protocol.** Skipping this in favor
  of serial because (a) AppleTalk plumbing isn't in v1 yet, and
  (b) serial is simpler to test. Phase 5 (post-AppleTalk)
  could add the AppleTalk path as a parallel option.

---

## Comparison to other v2 features

| Feature | Era-correct | Effort | Demo-ability |
|---|---|---|---|
| `v2-extfs-outside-world` | Yes | 1 evening (DONE) | Kid plugs USB → folder appears |
| `v2-printer-bridge` (this) | Yes | 2-3 evenings | Kid prints → PDF appears in folder |
| `v2-inter-chimebox-appletalk` | Yes | 1-2 weekends | Two chimeboxes see each other |
| `v3-bridge-appliance` | Yes (preserves UX) | 2-4 weekends | Mac → Matrix message |

Printer bridge is in the sweet spot: meaningful effort but very
self-contained (one Linux daemon, no Mac-side code, no networking
beyond optional CUPS). Could ship in 2–3 evenings of focused
work.

---

## What this enables longer-term

- **"Refrigerator gallery"** workflow: the kid prints drawings;
  PDFs accumulate in `prints/`; an adult periodically picks
  favorites and prints to the real fridge.
- **"Mail to a relative"** workflow: the daemon posts new
  prints to the family's bridge appliance; they show up as
  Matrix messages or emails. Composes with v3.
- **Homework worksheet workflow** (older kids): Mac OS gives a
  surprisingly good HyperCard-driven worksheet experience; print
  → PDF → re-print on real printer.
- **Memorabilia archive**: every drawing the kid ever made,
  preserved in a dated folder. Future-them will be charmed.

---

## References

- Apple, "PostScript Language Reference Manual" (3rd ed.) —
  job structure, `%%` comment conventions.
- ghostscript man page (`gs(1)`) — `-dSAFER` semantics, device
  list.
- BasiliskII source: `BasiliskII/src/Unix/serial_unix.cpp` — how
  `seriala` is implemented; behavior under different host file
  types.
- socat man page — `PTY` and `EXEC` address types, `link=`
  option for stable names.
- LaserWriter / ImageWriter Printer Reference — old Apple
  manuals for protocol details (still findable on
  vintage-Apple sites).
