#!/usr/bin/env python3
"""
reassemble_chunked.py

Reassemble a chunked disk image produced by Infinite Mac's `write_chunked_image`
back into a single .dsk file.

Infinite Mac chunks disk images for web serving:
- chunks live in    Images/build/<sha>.chunk
- a manifest lives in src/Data/<DiskName>.json with the ordered list of
  chunk hashes (and "" for zero-chunks of the chunkSize).

We need a contiguous .dsk file to feed to native Basilisk II on the Pi, so
this script does the inverse operation: read the manifest, concatenate the
chunks (substituting all-zeros where the manifest has ""), and write the
result.

Usage:
    reassemble_chunked.py --manifest <path/to/Infinite HD.json> \\
                          --chunks-dir <path/to/Images/build> \\
                          --output <path/to/output.dsk>

Exit codes:
    0  success
    1  argument or manifest error
    2  missing chunk file
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def reassemble(manifest_path: Path, chunks_dir: Path, output_path: Path) -> int:
    if not manifest_path.is_file():
        print(f"error: manifest not found: {manifest_path}", file=sys.stderr)
        return 1
    if not chunks_dir.is_dir():
        print(f"error: chunks dir not found: {chunks_dir}", file=sys.stderr)
        return 1

    with manifest_path.open("r") as f:
        manifest = json.load(f)

    chunk_size = manifest["chunkSize"]
    total_size = manifest["totalSize"]
    chunks = manifest["chunks"]
    name = manifest.get("name", manifest_path.stem)

    zero_chunk = b"\0" * chunk_size

    print(
        f"Reassembling {name}: {len(chunks)} chunks, "
        f"{total_size:,} bytes target, {chunk_size:,} bytes/chunk",
        file=sys.stderr,
    )

    # Stream-write to the output path so we don't need to hold the entire
    # disk image in memory.
    output_path.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    last_pct = -1
    with output_path.open("wb") as out:
        for i, sig in enumerate(chunks):
            if sig == "":
                # zero chunk -- but we need to honor the *actual* trailing
                # chunk size (the last chunk may be shorter than chunk_size)
                remaining = total_size - written
                this_size = min(chunk_size, remaining)
                out.write(b"\0" * this_size)
                written += this_size
            else:
                chunk_path = chunks_dir / f"{sig}.chunk"
                if not chunk_path.is_file():
                    print(
                        f"\nerror: missing chunk file: {chunk_path}",
                        file=sys.stderr,
                    )
                    return 2
                with chunk_path.open("rb") as cf:
                    data = cf.read()
                out.write(data)
                written += len(data)

            pct = int((i + 1) * 100 / len(chunks))
            if pct != last_pct:
                print(f"  {pct}%\r", end="", file=sys.stderr)
                sys.stderr.flush()
                last_pct = pct

    print(file=sys.stderr)

    if written != total_size:
        print(
            f"warning: wrote {written:,} bytes, manifest says {total_size:,}",
            file=sys.stderr,
        )

    print(f"wrote {output_path} ({written:,} bytes)", file=sys.stderr)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--manifest", required=True, type=Path)
    ap.add_argument("--chunks-dir", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    return reassemble(args.manifest, args.chunks_dir, args.output)


if __name__ == "__main__":
    sys.exit(main())
