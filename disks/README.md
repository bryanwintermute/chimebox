# disks/

This directory holds **user-supplied** ROMs and disk images that are used to
build and run a chimebox. Nothing in here (other than this README) is committed
to git — see the repo-root `.gitignore`.

## What lives here

After running `disk-prep/` on your workstation, you should end up with:

```
disks/
├── README.md            ← this file (committed)
├── Quadra-650.rom       ← Apple-copyrighted ROM, you provide
├── System.dsk           ← Mac OS 8.1 boot disk (writable kid profile)
└── InfiniteHD.dsk       ← Curated software library (read-only at runtime)
```

These three files are then pushed to the Pi via `scripts/push-disks.sh`.

## Why nothing here is committed

- ROMs are copyrighted by Apple. We do not redistribute them. See
  [`../LICENSING.md`](../LICENSING.md) for the long-form discussion.
- Curated disk images contain a mix of Apple system software and third-party
  abandonware that we are similarly not in a position to redistribute.

## How to obtain a ROM

Lawful sources include:

- A classic Mac you own — extracting the ROM from real hardware is the
  cleanest provenance.
- Apple's historical "Older Software Downloads" releases, where applicable.
- The community-maintained checkouts that ship with major emulator
  distributions, used personally and not redistributed.

For chimebox v1, the target ROM is **Quadra 650** (32-bit clean, supports
Mac OS 7.5–8.1). The expected file name is `Quadra-650.rom` and its size and
checksum will be documented in `disk-prep/` once the build pipeline lands.

## How to build the disks

See [`../disk-prep/README.md`](../disk-prep/README.md) for the full
walkthrough. The fast path uses prebuilt chunks from the
infinitemac.org CDN and produces both disk images in ~90 seconds on
a recent Mac. The slow path runs the full Infinite Mac upstream
build pipeline locally.

In short: clone with submodules so `third_party/infinite-mac` is
populated, then run the disk-prep tooling. ROM is user-supplied and
not built by the pipeline.
