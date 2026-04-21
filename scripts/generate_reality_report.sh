#!/usr/bin/env bash
# Gera um snapshot markdown dos entregáveis de auditoria vs restoration plan.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS="$ROOT/audit/reports"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$REPORTS/REALITY_SNAPSHOT_${STAMP}.md"

mkdir -p "$REPORTS"

check_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    echo "- [x] $label"
  else
    echo "- [ ] $label **MISSING**"
  fi
}

check_script() {
  local name="$1"
  if [[ -x "$ROOT/scripts/$name" ]] || [[ -f "$ROOT/scripts/$name" ]]; then
    echo "- [x] scripts/$name"
  else
    echo "- [ ] scripts/$name **MISSING**"
  fi
}

{
  echo "# BEAGLE reality snapshot"
  echo
  echo "Generated: $(date -Iseconds)"
  echo
  echo "## Audit reports (restoration plan 1.1)"
  check_file "$REPORTS/COMPILATION_STATUS.md" "audit/reports/COMPILATION_STATUS.md"
  check_file "$REPORTS/EXTERNAL_DEPENDENCIES.md" "audit/reports/EXTERNAL_DEPENDENCIES.md"
  check_file "$REPORTS/MOCK_INVENTORY.md" "audit/reports/MOCK_INVENTORY.md"
  check_file "$ROOT/audit/FUNCTIONALITY_GAPS.md" "audit/FUNCTIONALITY_GAPS.md"
  check_file "$ROOT/audit/CRITICAL_PATHS.md" "audit/CRITICAL_PATHS.md"
  echo
  echo "## Scripts referenced by BEAGLE_RESTORATION_PLAN.md"
  check_script "audit_system.sh"
  check_script "check_external_services.sh"
  check_script "generate_reality_report.sh"
  check_script "categorize_mocks.sh"
  echo
  echo "## v0.3 follow-ups (see docs/BACKLOG_HYBRID_v0_3_plus_restoration.md)"
  echo "- VoidNavigator / beagle-ontic: see apps/beagle-monorepo/Cargo.toml (optional deps)"
  echo "- MCP: OAuth / streaming / webhooks not implemented (bearer token only)"
  echo
  echo "## Next manual steps"
  echo "- Run: \`./scripts/audit_system.sh\` (use Rust MSRV-compatible toolchain or container)"
  echo "- Run: \`./scripts/check_external_services.sh\` if services are configured"
} > "$OUT"

echo "[OK] Wrote $OUT"
