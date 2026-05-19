# disk-prep

Workstation-side tooling that produces the disk images a chimebox boots from.
**Fast path (`4-fetch-cdn.sh`) runs on Linux and macOS;** the full
local-build pipeline (`prep.sh`) still requires macOS for the
GUI-emulator desktop-database step. The output goes to
`../disks/` (gitignored) and is later pushed to the Pi via
`../scripts/push-disks.sh`.

## What this produces

Three artifacts in `../disks/`:

| File | Contents | Source |
|---|---|---|
| `Quadra-650.rom` | The Quadra 650 ROM image | **You provide** (see "Obtaining the ROM" below) |
| `System.dsk` | Mac OS 8.1 boot disk (writable kid profile) | Infinite Mac's `Images/` |
| `InfiniteHD.dsk` | Curated software library disk (read-only at runtime) | Built by Infinite Mac's `import-disks` pipeline |

For chimebox v1, **`System.dsk` ships as the stock Infinite Mac image** —
no chimebox-specific customization. Customization (kid shortcuts on Desktop,
hidden Developer/, etc.) is deferred to a future step.

## Why macOS-only for the full pipeline

Infinite Mac's `import-disks` pipeline invokes **native** Mini vMac and
Basilisk II as a final step to rebuild the desktop database on the produced
disk. That step works cleanly on macOS today; a Linux/Docker port is on the
roadmap but is not v1. The fast path (`4-fetch-cdn.sh`) sidesteps this
entirely by downloading pre-built chunks from `infinitemac.org` and
reassembling them locally — that works on Linux and macOS.

## How it's wired

```
chimebox/
├── third_party/
│   └── infinite-mac/        ← pinned submodule
└── disk-prep/
    ├── README.md            ← this file
    ├── 0-bootstrap.sh       ← installs prerequisites (uv, etc.)
    ├── 1-build-library.sh   ← runs Infinite Mac's import-library
    ├── 2-build-disks.sh     ← runs Infinite Mac's import-disks
    ├── 3-collect.sh         ← copies outputs into ../disks/
    ├── prep.sh              ← runs steps 0-3 end-to-end (full pipeline)
    ├── 4-fetch-cdn.sh       ← FAST PATH: fetch from infinitemac.org
    ├── fetch-from-cdn.py    ← the Python fetcher (used by 4-fetch-cdn.sh)
    └── reassemble_chunked.py
```

There are **two paths** to producing chimebox disk images, with
different trade-offs:

### Fast path (recommended): `4-fetch-cdn.sh`

Fetches pre-built chunks from `infinitemac.org`'s CDN and reassembles
them locally. Result: byte-identical disk images to what the upstream
pipeline would produce, in ~10 minutes instead of ~1.5 hours, with no
GUI emulator dance.

```sh
./disk-prep/4-fetch-cdn.sh
# Outputs to ../disks/{System.dsk, InfiniteHD.dsk}
```

Use this unless you need to customize the disk image at build time
(in which case use the full pipeline below).

### Full pipeline: `prep.sh`

Runs Infinite Mac's `import-library` + `import-disks` locally,
including the Macintosh Garden library download and the GUI emulator
desktop-database rebuild. ~1.5 hours; needs ~5 minutes of GUI
clicking partway through. Required if you want to modify the disk
image while it's being built.

```sh
./disk-prep/prep.sh
# (Will prompt you about the GUI emulator step partway through.)
```

The numbered scripts (0-bootstrap.sh, 1-build-library.sh,
2-build-disks.sh, 3-collect.sh) can also be run individually for
development; each is idempotent.

## Quickstart

```sh
# From the chimebox repo root:
git submodule update --init third_party/infinite-mac

# (One-time) drop your Quadra 650 ROM at:
#   disks/Quadra-650.rom
# See "Obtaining the ROM" below.

cd disk-prep

# FAST path (recommended; ~10 min):
./4-fetch-cdn.sh

# OR full pipeline (slow but customizable; ~1.5h):
./prep.sh
```

After the chosen path finishes you should have:

```
disks/
├── Quadra-650.rom        (yours)
├── System.dsk            (Mac OS 8.1)
└── InfiniteHD.dsk        (curated library)
```

## Prerequisites

- **For the fast path:** Linux or macOS. Python 3 + standard
  utilities; no GUI emulators needed. `0-bootstrap.sh` is not
  required for this path.
- **For the full pipeline:**
  - macOS (Apple Silicon or Intel).
  - **Xcode Command Line Tools** (`xcode-select --install`).
  - **`uv`** for Python package management — `0-bootstrap.sh` installs it if
    missing.
  - A working **Mini vMac** and **Basilisk II** native build (the Infinite Mac
    README documents how to obtain these for the `import-disks` step).

`0-bootstrap.sh` will check the full-pipeline prerequisites and
print clear errors for what's missing.

## Obtaining the ROM

The Quadra 650 ROM is **Apple-copyrighted** and **not** distributed by this
project. Lawful sources include:

- A real Quadra 650 you own (extract via `CopyROM` or similar).
- An emulator distribution that ships with a ROM you've kept private.
- Apple's historical "Older Software" archives (where applicable).

Place the file at `../disks/Quadra-650.rom` (the path relative to this
directory). The expected file size is **1,048,576 bytes (1 MiB)**.

`prep.sh` will refuse to proceed if the ROM is missing or wrong-sized, with
a clear error message.

## Recovering from a broken run

`import-disks` is the longest step (it boots emulators headfully on your Mac
to rebuild the desktop database — be patient, and don't quit them yourself
unless prompted). If something dies mid-way:

- Check `../third_party/infinite-mac/Images/` for partial outputs.
- Re-run the failing numbered script directly; it will resume.

## Future

- Step 4: `4-curate.sh` — chimebox-specific tweaks (kid shortcuts on
  Desktop, hidden Developer/, kid-friendly volume defaults). Deferred to a
  later commit.
- Linux/Docker port to remove the macOS dependency.
- Verification step that boots the produced disk in B2 headlessly to
  confirm it's bootable.
