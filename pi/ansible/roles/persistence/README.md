# role: persistence

Sets up the snapshot-and-rollback machinery for `System.dsk`.

## Rotating snapshots (cron-driven)

- A nightly cron that snapshots `System.dsk` to
  `~/chimebox/snapshots/daily-YYYY-MM-DD.dsk`, retaining the last
  `chimebox_snapshot_keep_daily` daily snapshots.
- A weekly snapshot kept as `weekly-YYYY-WW.dsk`, retaining
  `chimebox_snapshot_keep_weekly`.
- Manual snapshots (`chimebox-snapshot manual` /
  `scripts/snapshot-now.sh`) named `manual-YYYY-MM-DD-HHMMSS.dsk`.

The cron runs as `root` (for atomic file ops); snapshots are
chowned to `chimebox_user`.

## Factory baseline (operator-blessed)

A separate **factory baseline** at `~/chimebox/factory.dsk` lives
*outside* the rotating snapshots dir. It is operator-blessed and
re-baselineable:

- `chimebox-snapshot factory` (or `scripts/factory-bless.sh` from
  a workstation) captures the current `System.dsk` as the new
  factory baseline. The file is written read-only (`0440`) so
  accidental overwrites are blocked. Re-blessing replaces the
  prior baseline.
- `chimebox-reset factory` (or `scripts/factory-reset.sh`)
  restores `System.dsk` from this baseline.

The factory baseline is *deliberately* outside the rotation so:

1. The daily/weekly cron never overwrites it (cron only rewrites
   files matching `daily-*.dsk` / `weekly-*.dsk` patterns, and the
   factory file is in a different directory entirely).
2. `chimebox-reset latest` and the kid-reset hotkey never pick it
   up (they glob `snapshots/*.dsk`, which doesn't match
   `chimebox/factory.dsk`).
3. It survives the cycle of rotating snapshots that may have
   captured the corruption you're trying to undo.

Bless after curation milestones (e.g., kid-shortlist Setup is the
way you want it long-term) so a "factory reset" is a meaningful
"back to the version I shipped" rollback.

## Helper scripts installed

| Script | Purpose |
|---|---|
| `chimebox-snapshot daily\|weekly\|manual` | Write to rotating snapshots dir |
| `chimebox-snapshot factory` | Bless current `System.dsk` as factory baseline |
| `chimebox-reset list` | List rotating snapshots + factory presence |
| `chimebox-reset latest` | Restore from most recent rotating snapshot |
| `chimebox-reset factory` | Restore from factory baseline |
| `chimebox-reset <filename>` | Restore from named rotating snapshot |

## Audit trail

Both helpers log every fire to syslog with a stable tag, so cron-
driven snapshots and out-of-band restores are visible in the
journal. The cron `(root) CMD (...)` wrapper line by itself
only says cron *invoked* the script -- it doesn't capture the
script's actual outcome (which file was written, retention
pruning, errors, etc.). The `logger -t` lines below give that
forensic data:

```bash
# Did the daily snapshot fire correctly last night?
journalctl -t chimebox-snapshot --since '24 hours ago'

# Recent restores (kid-reset, factory-reset, ad-hoc)
journalctl -t chimebox-reset --since '7 days ago'

# Both helpers in one pass
journalctl -t chimebox-snapshot -t chimebox-reset --since today
```

Sample output:

```
May 11 03:17:01 chimebox-snapshot: daily: snapshotting /home/.../System.dsk -> .../daily-2026-05-11.dsk
May 11 03:17:01 chimebox-snapshot: daily: wrote .../daily-2026-05-11.dsk (104857600 bytes)
May 11 03:17:01 chimebox-snapshot: daily: retention prunes 1 old snapshot(s) (keep=7)
May 11 03:17:01 chimebox-snapshot:   prune .../daily-2026-05-04.dsk
```
