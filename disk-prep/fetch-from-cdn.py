#!/usr/bin/env python3
"""
fetch-from-cdn.py

Fetch chimebox disk images from the Infinite Mac CDN
(https://infinitemac.org) instead of running the full upstream
import-disks pipeline locally.

This is the "fast path" for chimebox disk-prep: skips the
multi-gigabyte Macintosh Garden library download, the GUI emulator
desktop-database rebuild step, and ~1.5 hours of run time. Trade-off:
you get exactly what infinitemac.org currently serves; if you need to
customize the disk image at build time, use the full pipeline
(disk-prep/prep.sh) instead.

How it works:

1. Fetch the deployed app's HTML, find the main JS bundle.
2. Walk the JS bundles to discover the per-disk manifest module URLs
   (Vite emits them as 'assets/<DiskName>.dsk-<hash>.js').
3. For each requested disk:
   a. Fetch the manifest JS module, parse out the chunk list.
   b. Fetch all unique chunks in parallel (cached on disk between
      runs at ~/.chimebox-cache/chunks/).
   c. Reassemble into a contiguous .dsk file.

Cache: chunks are content-addressed (SHA-derived filenames), so the
cache is safe to keep forever and reuse across runs / disks. Total
cache size is bounded by the upstream's deduped chunk corpus
(~couple GB max).

Usage:
    fetch-from-cdn.py --output-dir ../disks "Mac OS 8.1 HD" "Infinite HD"

Exit codes:
    0  success
    1  argument or HTTP error
    2  manifest parsing error
    3  chunk verification failed
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DEFAULT_BASE_URL = "https://infinitemac.org"
DEFAULT_CACHE_DIR = Path.home() / ".chimebox-cache" / "chunks"
DEFAULT_PARALLEL = 16
USER_AGENT = "chimebox-disk-prep/1 (+https://github.com/bryanwintermute/chimebox)"

# All-zeros chunk content; manifests denote zero-runs with "..." instead
# of a hash to save space, expanding to chunk_size bytes of zeros.
ZERO_CHUNK_MARKER = "..."


@dataclass
class Manifest:
    name: str
    total_size: int
    chunk_size: int
    chunks: List[str]  # entries are hash strings, or "" for zero-chunks


def fetch_text(url: str) -> str:
    req = urllib.request.Request(_quote_url(url), headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode("utf-8")


def fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(_quote_url(url), headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def _quote_url(url: str) -> str:
    """Quote special chars in the path while preserving the URL structure."""
    parsed = urllib.parse.urlsplit(url)
    quoted_path = urllib.parse.quote(parsed.path, safe="/")
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, quoted_path,
         parsed.query, parsed.fragment)
    )


def discover_manifest_urls(base_url: str) -> Dict[str, str]:
    """Walk the deployed app's bundles to map disk-display-name to
    manifest-module URL.

    Returns: {"Mac OS 8.1 HD": "https://.../assets/Mac OS 8.1 HD.dsk-XYZ.js", ...}
    """
    print(f"  fetching {base_url}/ ...", file=sys.stderr)
    html = fetch_text(base_url + "/")

    # Find every assets/*.js URL in the HTML and recursively in the JS chunks
    # that contain disk-import statements.
    asset_re = re.compile(r'/assets/[A-Za-z0-9._-]+\.js')
    seen = set()
    to_visit = list(set(asset_re.findall(html)))

    # Pattern Vite emits for `import("@/Data/<DiskName>.dsk.json")`:
    #     import(`./<DiskName>.dsk-<hash>.js`)
    # We want to capture the disk display name and hash.
    import_re = re.compile(
        r'import\(`\./([^`]+\.dsk)-([A-Za-z0-9_-]+)\.js`\)'
    )

    manifests: Dict[str, str] = {}
    while to_visit:
        url_path = to_visit.pop()
        if url_path in seen:
            continue
        seen.add(url_path)
        url = base_url + url_path
        try:
            js = fetch_text(url)
        except Exception as e:
            print(f"  warn: failed to fetch {url_path}: {e}", file=sys.stderr)
            continue

        for m in import_re.finditer(js):
            display_name_dsk, hash_str = m.group(1), m.group(2)
            # Strip ".dsk" from the display name to match disks.py naming
            display_name = display_name_dsk
            if display_name.endswith(".dsk"):
                display_name = display_name[: -len(".dsk")]
            manifest_url = f"{base_url}/assets/{display_name_dsk}-{hash_str}.js"
            manifests[display_name] = manifest_url

        # Discover further JS bundles (chunks) referenced from this one
        for ref in asset_re.findall(js):
            if ref not in seen:
                to_visit.append(ref)

    print(f"  discovered {len(manifests)} disk manifests", file=sys.stderr)
    return manifests


def parse_manifest_module(js: str, source_name: str) -> Manifest:
    """Parse a Vite-emitted manifest JS module into a Manifest object.

    The module looks like:
        var e=`<name>`,t=<totalSize>,n=`<dot-separated-hashes>`.split(`.`),
            r=<chunkSize>,i={name:e,totalSize:t,chunks:n,chunkSize:r};
        export {...}
    """
    name_m = re.search(r'var e=`([^`]+)`', js)
    # totalSize may be encoded as scientific notation like "2097152e3"
    total_m = re.search(r',t=([\d.eE+-]+),', js)
    chunks_m = re.search(r'n=`([^`]*)`\.split\(`\.`\)', js)
    cs_m = re.search(r',r=([\d.eE+-]+),', js)

    if not (name_m and total_m and chunks_m and cs_m):
        raise ValueError(f"cannot parse manifest module from {source_name}")

    name = name_m.group(1)
    # int() doesn't parse scientific notation; go via float
    total_size = int(float(total_m.group(1)))
    chunk_size = int(float(cs_m.group(1)))
    raw_chunks = chunks_m.group(1).split(".")

    # In the upstream's encoding, "" represents a zero-chunk (saves bytes
    # in the manifest). We keep "" in our list (matches our existing
    # reassemble_chunked.py contract).
    chunks = ["" if c == "" else c for c in raw_chunks]

    return Manifest(
        name=name,
        total_size=total_size,
        chunk_size=chunk_size,
        chunks=chunks,
    )


def fetch_chunk(
    base_url: str,
    chunk_hash: str,
    cache_dir: Path,
) -> Path:
    """Fetch a chunk by hash, caching on disk. Returns local path."""
    cached = cache_dir / f"{chunk_hash}.chunk"
    if cached.is_file():
        return cached

    url = f"{base_url}/Disk/{chunk_hash}.chunk"
    try:
        data = fetch_bytes(url)
    except Exception as e:
        raise RuntimeError(f"fetch {url}: {e}")

    # Write atomically via .tmp then rename
    tmp = cached.with_suffix(".chunk.tmp")
    tmp.write_bytes(data)
    tmp.rename(cached)
    return cached


def fetch_all_unique_chunks(
    manifests: List[Manifest],
    base_url: str,
    cache_dir: Path,
    parallel: int,
) -> None:
    """Fetch every unique chunk hash referenced across the manifests."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    unique = set()
    for m in manifests:
        for h in m.chunks:
            if h:
                unique.add(h)

    already_cached = sum(
        1 for h in unique if (cache_dir / f"{h}.chunk").is_file()
    )
    to_fetch = [h for h in unique if not (cache_dir / f"{h}.chunk").is_file()]

    print(
        f"  {len(unique):,} unique chunks total; "
        f"{already_cached:,} already cached; {len(to_fetch):,} to fetch",
        file=sys.stderr,
    )

    if not to_fetch:
        return

    fetched = 0
    failures: List[Tuple[str, str]] = []
    last_pct_printed = -1
    with concurrent.futures.ThreadPoolExecutor(max_workers=parallel) as ex:
        futures = {
            ex.submit(fetch_chunk, base_url, h, cache_dir): h
            for h in to_fetch
        }
        for fut in concurrent.futures.as_completed(futures):
            h = futures[fut]
            try:
                fut.result()
            except Exception as e:
                failures.append((h, str(e)))
            else:
                fetched += 1
                pct = int(fetched * 100 / len(to_fetch))
                if pct != last_pct_printed:
                    print(
                        f"\r  fetched {fetched:,}/{len(to_fetch):,} "
                        f"({pct}%)   ",
                        end="",
                        file=sys.stderr,
                    )
                    sys.stderr.flush()
                    last_pct_printed = pct
    print(file=sys.stderr)

    if failures:
        for h, e in failures[:10]:
            print(f"  fail {h}: {e}", file=sys.stderr)
        if len(failures) > 10:
            print(f"  ... and {len(failures) - 10} more", file=sys.stderr)
        raise RuntimeError(f"{len(failures)} chunk fetches failed")


def reassemble(
    manifest: Manifest,
    cache_dir: Path,
    output_path: Path,
) -> None:
    """Reassemble the disk image from cached chunks."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    with output_path.open("wb") as out:
        last_pct = -1
        for i, h in enumerate(manifest.chunks):
            if h == "":
                # Zero chunk; honor trailing-chunk size limit
                remaining = manifest.total_size - written
                this_size = min(manifest.chunk_size, remaining)
                out.write(b"\0" * this_size)
                written += this_size
            else:
                chunk_path = cache_dir / f"{h}.chunk"
                data = chunk_path.read_bytes()
                out.write(data)
                written += len(data)
            pct = int((i + 1) * 100 / len(manifest.chunks))
            if pct != last_pct:
                print(
                    f"\r  reassembling {output_path.name}: {pct}%   ",
                    end="",
                    file=sys.stderr,
                )
                sys.stderr.flush()
                last_pct = pct
    print(file=sys.stderr)

    if written != manifest.total_size:
        raise RuntimeError(
            f"size mismatch: wrote {written:,}, manifest says "
            f"{manifest.total_size:,}"
        )
    print(
        f"  wrote {output_path} ({written:,} bytes)",
        file=sys.stderr,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "disks",
        nargs="+",
        help='Disk display names (e.g. "Mac OS 8.1 HD" "Infinite HD")',
    )
    ap.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help=f"Infinite Mac base URL (default: {DEFAULT_BASE_URL})",
    )
    ap.add_argument(
        "--cache-dir",
        type=Path,
        default=DEFAULT_CACHE_DIR,
        help=f"chunk cache (default: {DEFAULT_CACHE_DIR})",
    )
    ap.add_argument(
        "--output-dir",
        type=Path,
        default=Path("disks"),
        help="where to write reassembled .dsk files (default: ./disks)",
    )
    ap.add_argument(
        "--parallel",
        type=int,
        default=DEFAULT_PARALLEL,
        help=f"concurrent chunk fetches (default: {DEFAULT_PARALLEL})",
    )
    ap.add_argument(
        "--output-name",
        action="append",
        default=[],
        metavar="DISK=NAME",
        help=(
            "rename a disk on output, e.g. --output-name 'Mac OS 8.1 HD=System' "
            "writes to System.dsk instead of Mac OS 8.1 HD.dsk. May be "
            "repeated."
        ),
    )
    args = ap.parse_args()

    rename_map: Dict[str, str] = {}
    for spec in args.output_name:
        if "=" not in spec:
            print(f"error: --output-name must be DISK=NAME, got {spec!r}",
                  file=sys.stderr)
            return 1
        k, v = spec.split("=", 1)
        rename_map[k] = v

    print("Discovering manifest URLs ...", file=sys.stderr)
    try:
        all_manifest_urls = discover_manifest_urls(args.base_url)
    except Exception as e:
        print(f"error discovering manifests: {e}", file=sys.stderr)
        return 1

    # Look up each requested disk
    requested: List[Tuple[str, str]] = []  # (display_name, manifest_url)
    missing: List[str] = []
    for disk in args.disks:
        if disk in all_manifest_urls:
            requested.append((disk, all_manifest_urls[disk]))
        else:
            missing.append(disk)
    if missing:
        print(f"error: unknown disk(s): {missing}", file=sys.stderr)
        print(f"available: {sorted(all_manifest_urls.keys())}", file=sys.stderr)
        return 1

    print("Fetching manifests ...", file=sys.stderr)
    manifests: List[Manifest] = []
    for display_name, mfu in requested:
        print(f"  {display_name} <- {mfu}", file=sys.stderr)
        js = fetch_text(mfu)
        m = parse_manifest_module(js, display_name)
        manifests.append(m)
        print(
            f"    {m.total_size:,} bytes, {len(m.chunks):,} chunks "
            f"of {m.chunk_size:,}",
            file=sys.stderr,
        )

    print("Fetching chunks ...", file=sys.stderr)
    try:
        fetch_all_unique_chunks(
            manifests, args.base_url, args.cache_dir, args.parallel
        )
    except Exception as e:
        print(f"error fetching chunks: {e}", file=sys.stderr)
        return 1

    print("Reassembling ...", file=sys.stderr)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for m in manifests:
        out_basename = rename_map.get(m.name, m.name)
        out_path = args.output_dir / f"{out_basename}.dsk"
        reassemble(m, args.cache_dir, out_path)

    print("Done.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
