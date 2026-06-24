#!/usr/bin/env bash
# archive-legacy-memory.sh — Phase 3.4 decommission: ARCHIVE the legacy memory
# stack, never delete it.
#
# Tars the canonical exocortex JSONL directory and the LanceDB directory into a
# timestamped, checksummed archive. It COPIES — it never removes the originals.
# Deletion (if ever) is a separate, deliberate human step taken only after the
# archive is verified and stored off-box. Dry-run by default; pass --commit to
# actually write the archive.
#
# Env (override as needed):
#   EXOCORTEX_DIR   canonical JSONL dir   (default: $BEAGLE_DATA_DIR/exocortex)
#   LANCEDB_DIR     legacy LanceDB dir    (default: /var/lib/beagle/lancedb)
#   ARCHIVE_DIR     destination root      (default: /var/lib/beagle/archive)
#
# Usage:
#   ops/archive-legacy-memory.sh            # dry-run: show what would be archived
#   ops/archive-legacy-memory.sh --commit   # write + verify the archive
set -euo pipefail

COMMIT=0
[[ "${1:-}" == "--commit" ]] && COMMIT=1

EXOCORTEX_DIR="${EXOCORTEX_DIR:-${BEAGLE_DATA_DIR:-$HOME/beagle-data}/exocortex}"
LANCEDB_DIR="${LANCEDB_DIR:-/var/lib/beagle/lancedb}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/lib/beagle/archive}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${ARCHIVE_DIR}/legacy-memory-${STAMP}"

log() { printf '[archive] %s\n' "$*"; }

archive_one() {
  local src="$1" name="$2"
  if [[ ! -e "$src" ]]; then
    log "SKIP ${name}: not present at ${src}"
    return 0
  fi
  local size; size="$(du -sh "$src" 2>/dev/null | cut -f1 || echo '?')"
  if [[ "$COMMIT" -eq 0 ]]; then
    log "WOULD archive ${name} (${size}) ${src} -> ${DEST}/${name}.tar.gz"
    return 0
  fi
  log "archiving ${name} (${size}) ..."
  tar -czf "${DEST}/${name}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
  sha256sum "${DEST}/${name}.tar.gz" | tee -a "${DEST}/SHA256SUMS"
  # Verify the tarball is readable end-to-end (catches truncation/corruption).
  tar -tzf "${DEST}/${name}.tar.gz" >/dev/null
  log "OK ${name} archived + verified (originals left intact at ${src})"
}

log "exocortex=${EXOCORTEX_DIR}"
log "lancedb=${LANCEDB_DIR}"
log "archive=${DEST}  commit=${COMMIT}"

if [[ "$COMMIT" -eq 1 ]]; then
  mkdir -p "${DEST}"
  printf 'archived_at=%s\nexocortex_src=%s\nlancedb_src=%s\n' \
    "$STAMP" "$EXOCORTEX_DIR" "$LANCEDB_DIR" > "${DEST}/MANIFEST.txt"
fi

archive_one "$EXOCORTEX_DIR" "exocortex-jsonl"
archive_one "$LANCEDB_DIR"   "lancedb"

if [[ "$COMMIT" -eq 1 ]]; then
  log "DONE. Archive at ${DEST}. Originals NOT deleted — verify + copy off-box before any cleanup."
else
  log "DRY-RUN complete. Re-run with --commit to write the archive."
fi
