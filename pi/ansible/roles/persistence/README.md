# role: persistence

Sets up:

- A nightly cron that snapshots `System.dsk` to
  `~/chimebox/snapshots/daily-YYYY-MM-DD.dsk`, retaining the last
  `chimebox_snapshot_keep_daily` daily snapshots.
- A weekly snapshot kept as `weekly-YYYY-WW.dsk`, retaining
  `chimebox_snapshot_keep_weekly`.
- A `chimebox-snapshot` script invokable manually.
- A `chimebox-reset` script that restores `System.dsk` from a chosen
  snapshot.

These run as `root` (cron requires it for atomic file ops) but the
snapshots themselves are owned by `chimebox_user`.
