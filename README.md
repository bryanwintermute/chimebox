# chimebox

> A locked-down, internet-free, period-correct retro computing experience on a
> Raspberry Pi — designed as a young person's first real computer.

**Status:** very early. This README documents intent more than reality.

## What is chimebox?

Chimebox turns a Raspberry Pi into a single-purpose retro computer kiosk. It
boots straight into a classic operating system running in an emulator,
fullscreen, with no visible host OS. From the user's perspective, it's just an
old computer. From an administrator's perspective, it's a normal Linux box you
can SSH into to maintain.

The first supported environment is **Mac OS 8.1** running in **Basilisk II**,
chosen for its sweet spot of color graphics, a well-known kid-friendly software
catalog (KidPix, MacPaint, HyperCard, Oregon Trail, Lemmings, etc.), and
mature, stable native emulation on `aarch64`.

## Why?

Modern computing experiences hide everything interesting behind glossy, locked-
down app stores and walled gardens. They also come with cameras, microphones,
trackers, ads, and a one-click bridge to the entire internet — none of which a
small child should have to navigate to learn what a computer *is*.

A retro Mac, by contrast:

- has a real, visible file system
- has no internet capability worth speaking of
- has no advertising, no autoplay, no notifications
- has a curated catalog of decades-old software, much of it educational and
  delightful, all of which works offline
- breaks gracefully — there's no "this app needs an update" loop

Chimebox is built for a young family member to grow up with one of these
machines as a first computer, alongside whatever modern devices they
eventually use.

## What's in the box

A typical chimebox deployment consists of:

- A **Raspberry Pi 5** (or similar) running Raspberry Pi OS Lite, headless,
  no desktop environment.
- A **kiosk session** that boots straight into a fullscreen emulator window
  with no escape to the host.
- A **prepared disk image** with a curated software library, built once on a
  separate workstation.
- An **administrator back door** over SSH for the responsible adult to manage
  the machine.

## Repository layout

```
chimebox/
├── docs/              ← Architecture, era decisions, ops runbooks, recovery
├── disk-prep/         ← Tools that run on a workstation to build the disk image
├── pi/                ← Ansible playbook and roles to provision the Pi
├── scripts/           ← Operational scripts (push disks, snapshot, reset)
├── disks/             ← .gitignored — local-only ROMs and disk images
├── LICENSE            ← Apache 2.0
├── LICENSING.md       ← Per-component licensing, including upstream projects
└── NOTICE             ← Apache 2.0 attribution to upstream projects
```

## Quickstart

Not yet — this is a scaffold. See `docs/architecture.md` for what's coming.

## Acknowledgements

Chimebox stands on the shoulders of years of work by the retro computing
community. Most directly, it draws on:

- **[Infinite Mac](https://github.com/mihaip/infinite-mac)** by Mihai Parparita
  (Apache 2.0) — the disk-build pipeline, machine and disk definitions, and
  curated Macintosh Garden manifests are invaluable starting points.
- **[Basilisk II](https://basilisk.cebix.net/)** and the **macemu** family of
  emulators (GPL v2).
- **[Macintosh Garden](https://macintoshgarden.org/)** — without their
  abandonware preservation work, there would be no software to load.

See [`NOTICE`](./NOTICE) for full attributions and [`LICENSING.md`](./LICENSING.md)
for the layered licensing situation around code, ROMs, and disk images.

## License

Source code in this repository is licensed under the **Apache License 2.0**.
See [`LICENSE`](./LICENSE).

ROMs, system disk images, and other Apple-copyrighted material are **not** part
of this repository and must be obtained by the user. See `LICENSING.md` and
`disks/README.md`.
