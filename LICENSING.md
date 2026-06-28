# Licensing

Chimebox is composed of multiple layers of work by different authors under
different licenses. This document spells out which is which, so contributors
and users can make informed decisions.

> **This document is informational, not legal advice.** If you intend to
> commercialize chimebox, distribute disk images, or sell hardware preloaded
> with this software, talk to a lawyer.

## Layer 1: chimebox itself

All original source code, configuration, and documentation in this repository
is licensed under the **Apache License 2.0**. See [`LICENSE`](./LICENSE).

## Layer 2: derived work from upstream projects

Some files in this repository — particularly under `disk-prep/` — adapt code
or configuration from other open-source projects. Where this is the case:

- Files carry a header comment identifying the upstream source.
- The [`NOTICE`](./NOTICE) file attributes the upstream project per its
  license requirements.

| Upstream | License | How chimebox uses it |
|---|---|---|
| [Infinite Mac](https://github.com/mihaip/infinite-mac) | Apache 2.0 | Disk-build pipeline, machine/disk definitions, library manifests |

Apache 2.0 is permissive and compatible with chimebox's own Apache 2.0
license; we preserve copyright notices and add attribution.

## Layer 3: emulators (installed at deploy time)

Chimebox does **not** redistribute emulator binaries. The Ansible playbook
installs them on the Pi from upstream sources — apt packages where available,
otherwise built from source on the device.

| Emulator | License | Distribution method |
|---|---|---|
| Basilisk II (`macemu`) | GPL v2 | apt package or build-from-source |
| Mini vMac | GPL v2 | apt package or build-from-source |
| SheepShaver (`macemu`) | GPL v2 | build-from-source (future) |
| DingusPPC | BSD-3-Clause | build-from-source (future) |
| Previous | GPL v2 | build-from-source (future) |
| PearPC | GPL v2 | build-from-source (future) |
| Snow | MIT-ish (verify per release) | build-from-source (future) |

Because chimebox does not bundle these binaries, GPL source-distribution
obligations fall on whoever distributes them (typically Debian / upstream),
not on chimebox or its users. Building from source on the Pi keeps the source
trivially available.

## Layer 4: ROMs (NOT redistributed)

The classic Mac ROMs (e.g., Quadra 650 ROM) are **copyrighted by Apple Inc.**
and are **not** part of this repository. They are listed in `.gitignore` and
will not be committed.

Apple has historically tolerated personal/educational use of these ROMs in
the emulator community without taking enforcement action, but this tolerance
is not a license. Chimebox users must:

- Obtain ROMs from a machine they legally own, or from another lawful source.
- Use them only on their own personal chimebox installation.
- Never redistribute them.

For a personal chimebox deployment for a child or family member: this is
within commonly accepted norms of the emulator community.

For a public release / hardware product / commercial deployment: don't.

## Layer 5: system disk images (NOT redistributed)

System software disk images (System 6, 7, Mac OS 8, Mac OS 9, etc.) are
similarly **copyrighted by Apple Inc.** and **not** part of this repository.
The same guidance as ROMs applies.

Apple has released some early System Software (1.1 through 7.5.5) on its
website historically, with permissive language for personal use, but again:
this is not a license to redistribute. Each user obtains their own copy.

## Layer 6: third-party software for the curated library

The chimebox software library draws on:

- **[Macintosh Garden](https://macintoshgarden.org/)** — abandonware
  preservation. Macintosh Garden hosts software whose copyright holders are
  defunct, unreachable, or who have not requested takedowns. Their
  [policy](https://macintoshgarden.org/policy) is opt-out: rights holders
  who object can request removal. Chimebox treats Macintosh Garden as the
  source of truth for what is currently considered acceptable to host.
- **[Internet Archive](https://archive.org/)** — period CD-ROM images and
  software collections with their own per-item rights.

Chimebox does **not** redistribute software from these sources. The
disk-prep tooling fetches them at build time, on the user's workstation, into
a local disk image used only on that user's chimebox.

If a chimebox user wishes to publish a prebuilt disk image: don't, unless
every piece of software on it is verifiably under a license that permits it.

## Layer 7: project branding / art

The icon and logo art under [`branding/`](./branding/) is **AI-generated**
(Google Gemini) and, per current U.S. Copyright Office guidance
([*Copyright and Artificial Intelligence, Part 2*](https://www.copyright.gov/ai/),
Jan 2025), purely prompt-generated images are **not copyrightable** in the U.S.
(other jurisdictions may differ). Chimebox asserts no copyright in this art (nor
in its purely mechanical edits); **no rights are asserted** and it is **not**
covered by the Apache 2.0 license above. It contains no Apple logo or other known
third-party trademarks. Derived copies (e.g. the Plymouth boot splash at
`pi/ansible/roles/boot-splash/files/splash.png`) carry the same status. See
[`branding/README.md`](./branding/README.md) for full provenance.

## What this means in practice

### For a personal deployment

You're fine. ROMs and disks come from your own sources; emulators are built
from public source on your Pi; the curated library is fetched at build time
on your workstation. Nothing copyrighted leaves your machines.

### For contributing back to chimebox

Contributions land under Apache 2.0 (per the
[Apache 2.0 contribution clause](./LICENSE)). Don't commit ROMs, disk
images, or proprietary software.

### For redistributing chimebox publicly

Source-only redistribution: Apache 2.0 lets you do this freely with
attribution.

Distributing prebuilt images, hardware, or anything containing ROMs / Apple
disks / Macintosh Garden content: get a lawyer.

## See also

- [`NOTICE`](./NOTICE) — Apache 2.0 attribution requirements
- [`branding/README.md`](./branding/README.md) — project art provenance (AI-generated)
- [`disks/README.md`](./disks/README.md) — how to obtain ROMs and disks
- [Apache 2.0 license text](./LICENSE)
