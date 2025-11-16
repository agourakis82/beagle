# Beagle Sync (Linux ↔ Windows)

Use rsync over SSH with exclusions to mirror code between:
- Local (Linux): `/home/maria/beagle`
- Remote (Windows host via POSIX path): e.g., `/mnt/e/workspace/beagle-remote` at `10.100.0.1` or `10.100.0.2`

## Environment
- `BEAGLE_SYNC_HOST` (10.100.0.1 or 10.100.0.2)
- `BEAGLE_SYNC_USER` (SSH user)
- `BEAGLE_REMOTE_PATH` (e.g., `/mnt/e/workspace/beagle-remote`)
- Optional: `BEAGLE_LOCAL_PATH` (default `/home/maria/beagle`)
- Optional: `BEAGLE_RSYNC_EXCLUDES` (default `sync/excludes.rsync`)
- Optional: `BEAGLE_SSH_OPTS` (e.g., `-p 22 -o StrictHostKeyChecking=no`)

## Commands
Linux → Windows:
```bash
BEAGLE_SYNC_HOST=10.100.0.1 \
BEAGLE_SYNC_USER=YOURUSER \
BEAGLE_REMOTE_PATH=/mnt/e/workspace/beagle-remote \
scripts/sync/linux_to_windows.sh
```

Windows → Linux:
```bash
BEAGLE_SYNC_HOST=10.100.0.1 \
BEAGLE_SYNC_USER=YOURUSER \
BEAGLE_REMOTE_PATH=/mnt/e/workspace/beagle-remote \
scripts/sync/windows_to_linux.sh
```

See exclusion patterns in `sync/excludes.rsync`.

