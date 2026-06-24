#!/usr/bin/env bash
# memory-pg-backup.sh — Phase 3.4 decommission: back up the new canonical store.
#
# Takes a logical, extension-aware dump of the memory-pg database with pg_dump
# (custom format, compressed). A logical dump is chosen over a physical
# pg_basebackup because the restore must CREATE EXTENSION (vector, pg_search)
# BEFORE the data is loaded — the halfvec/bm25 columns need their types to exist
# first. (Physical alternatives — pg_basebackup or a Ceph RBD snapshot of the
# PVC — are documented in the decommission runbook.)
#
# Env:
#   MEMORY_PG_DSN   postgres connection string (required)
#   BACKUP_DIR      destination dir (default: /var/lib/beagle/archive/memory-pg)
#
# Usage:
#   MEMORY_PG_DSN=postgres://... ops/memory-pg-backup.sh
set -euo pipefail

: "${MEMORY_PG_DSN:?set MEMORY_PG_DSN}"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/beagle/archive/memory-pg}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/memory-pg-${STAMP}.dump"

log() { printf '[backup] %s\n' "$*"; }

mkdir -p "${BACKUP_DIR}"
log "dumping memory-pg -> ${OUT}"
# -Fc custom format (selective + compressed); --no-owner for portable restore.
pg_dump --dbname="${MEMORY_PG_DSN}" -Fc --no-owner --file="${OUT}"
sha256sum "${OUT}" | tee "${OUT}.sha256"
# Sanity: the dump must list our core tables.
pg_restore --list "${OUT}" | grep -E 'TABLE (DATA )?(records|chunks|embeddings)' >/dev/null \
  && log "OK dump contains records/chunks/embeddings" \
  || { log "ERROR: dump missing core tables"; exit 1; }

cat <<EOF
[backup] DONE: ${OUT}

RESTORE (logical) — extensions FIRST, then data:
  createdb -h <host> -U <user> memory_restored
  psql -h <host> -U <user> -d memory_restored -c 'CREATE EXTENSION IF NOT EXISTS vector;'
  psql -h <host> -U <user> -d memory_restored -c 'CREATE EXTENSION IF NOT EXISTS pg_search;'
  # (Apache AGE deferred — only needed once Phase 4 graph tables exist)
  pg_restore --no-owner --dbname=postgres://<user>@<host>/memory_restored "${OUT}"
EOF
