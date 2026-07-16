#!/usr/bin/env bash
# memory-pg failover: promote the t560 standby to primary when the DGX Spark (.24) is gone.
#
# The memory (the user's recorded self, ~113K records) normally lives in a single Docker
# container on the Spark at 192.168.3.24:5433, with a live streaming standby on t560
# (StatefulSet memory-pg-standby) that is RPO~0. This script turns "the Spark died" into one
# command instead of a procedure recalled from memory under stress.
#
# What it does:
#   1. Confirms the standby is healthy and (still) in recovery.
#   2. Promotes it to a read-write primary (pg_promote).
#   3. Rewrites the memory-pg Secret DATABASE_URL to point at memory-pg-standby.beagle.svc:5432
#      (same user/password/db — a physical replica shares the primary's auth), and updates the
#      memory-pg-topology ConfigMap so the drift-check agrees with reality.
#   4. Rolls the 6 consumers so they reconnect to the promoted node.
#
# It is SAFE to dry-run (default). Pass --promote to actually do it. See project_memory_pg_durability.
set -euo pipefail

NS=beagle
STANDBY_POD=memory-pg-standby-0
STANDBY_SVC_HOST=memory-pg-standby.beagle.svc.cluster.local
STANDBY_SVC_PORT=5432
SECRET=memory-pg
CONFIGMAP=memory-pg-topology
CONSUMERS=(beagle-core beagle-mcp-server memory-pg-embed-worker memory-pg-graph-worker memory-pg-reranker memory-pg-serve)

DO_IT=0
[ "${1:-}" = "--promote" ] && DO_IT=1

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
run()  { if [ "$DO_IT" = 1 ]; then echo "+ $*"; "$@"; else echo "DRY-RUN: $*"; fi; }

kx() { kubectl -n "$NS" "$@"; }

say "0. preflight"
if ! kx get pod "$STANDBY_POD" >/dev/null 2>&1; then
  echo "FATAL: standby pod $STANDBY_POD not found. Nothing to promote." >&2; exit 1
fi
kx get pod "$STANDBY_POD" -o wide | tail -1
IN_REC=$(kx exec "$STANDBY_POD" -c postgres -- psql -U memory -tAc "SELECT pg_is_in_recovery()" 2>/dev/null || echo "?")
echo "standby pg_is_in_recovery = $IN_REC"
if [ "$IN_REC" = "f" ]; then
  echo "NOTE: standby is ALREADY a primary (not in recovery) — maybe promoted earlier. Continuing to repoint only." >&2
elif [ "$IN_REC" != "t" ]; then
  echo "FATAL: could not read recovery state from standby. Aborting." >&2; exit 1
fi

# Show how far behind it is (should be ~0). Informational only.
kx exec "$STANDBY_POD" -c postgres -- psql -U memory -tAc \
  "SELECT 'last_wal_replayed='||pg_last_wal_replay_lsn()||' at '||coalesce(pg_last_xact_replay_timestamp()::text,'n/a')" 2>/dev/null || true

if [ "$DO_IT" != 1 ]; then
  cat <<EOF

This is a DRY RUN. Re-run with:  $0 --promote
It will: pg_promote the standby, repoint the memory-pg Secret + topology ConfigMap at
$STANDBY_SVC_HOST:$STANDBY_SVC_PORT, and rollout-restart: ${CONSUMERS[*]}
EOF
  exit 0
fi

read -r -p $'\nType PROMOTE to confirm the Spark is gone and you want to fail over: ' ans
[ "$ans" = "PROMOTE" ] || { echo "aborted."; exit 1; }

say "1. ensure the stable standby Service exists"
run kubectl apply -f "$(dirname "$0")/../k8s/memory-pg/standby-service.yaml"

say "2. promote the standby to read-write primary"
if [ "$IN_REC" = "t" ]; then
  run kx exec "$STANDBY_POD" -c postgres -- psql -U memory -c "SELECT pg_promote(wait => true, wait_seconds => 60)"
  # verify
  for i in $(seq 1 12); do
    st=$(kx exec "$STANDBY_POD" -c postgres -- psql -U memory -tAc "SELECT pg_is_in_recovery()" 2>/dev/null || echo "?")
    echo "  post-promote pg_is_in_recovery = $st"
    [ "$st" = "f" ] && break
    sleep 2
  done
fi

say "3. repoint DATABASE_URL Secret + topology ConfigMap at the promoted node"
OLD_DSN=$(kx get secret "$SECRET" -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
# swap host:port only; keep user:pass and /db. Matches postgresql://user:pass@HOST:PORT/db?...
NEW_DSN=$(echo "$OLD_DSN" | sed -E "s#@[^/]+/#@${STANDBY_SVC_HOST}:${STANDBY_SVC_PORT}/#")
echo "new DSN host = ${STANDBY_SVC_HOST}:${STANDBY_SVC_PORT} (user/pass/db preserved)"
NEW_B64=$(printf '%s' "$NEW_DSN" | base64 -w0)
run kx patch secret "$SECRET" --type merge -p "{\"data\":{\"DATABASE_URL\":\"$NEW_B64\"}}"
run kx patch configmap "$CONFIGMAP" --type merge -p \
  "{\"data\":{\"MEMORY_PG_HOST\":\"${STANDBY_SVC_HOST}\",\"MEMORY_PG_PORT\":\"${STANDBY_SVC_PORT}\",\"MEMORY_PG_BACKEND\":\"t560-standby-promoted-paradedb-pg16\"}}"

say "4. roll the consumers so they reconnect to the promoted node"
for d in "${CONSUMERS[@]}"; do
  run kx rollout restart deployment "$d"
done

say "done. FAILED OVER to the t560 standby."
cat <<EOF
Follow-ups (not automated — do these deliberately once stable):
  * Verify recall: curl the memory-pg-serve /query and confirm results (hybrid BM25 needs ParadeDB — it's there).
  * Rebuild a NEW standby (the old primary is gone): re-basebackup from the promoted node, or bring the Spark
    back as the standby. Until then you are single-copy again — the hourly backups (backup-cronjob) still run.
  * The backup CronJob reads the same Secret, so it now dumps the promoted node automatically.
EOF
