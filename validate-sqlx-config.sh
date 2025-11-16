#!/bin/bash
#
# BEAGLE SQLX CONFIGURATION VALIDATION PROTOCOL
# ---------------------------------------------
# Executa uma bateria de verificações garantindo que o modo offline do SQLx,
# banco de dados e dependências estejam corretamente configurados.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

echo "════════════════════════════════════════════════════════════════════"
echo "BEAGLE SQLX CONFIGURATION VALIDATION PROTOCOL"
echo "════════════════════════════════════════════════════════════════════"
echo ""

step_result() {
  local status=$1
  local message=$2
  case "$status" in
    pass)
      echo -e "${GREEN}✓ PASS${NC}"
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;
    fail)
      echo -e "${RED}✗ FAIL${NC}"
      echo "    $message"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
    skip)
      echo -e "${YELLOW}⊘ SKIP${NC}"
      echo "    $message"
      ;;
  esac
}

# 1. DATABASE_URL definido
echo -n "[1/7] DATABASE_URL definido... "
if [ -n "${DATABASE_URL:-}" ]; then
  step_result pass ""
else
  step_result fail "Defina DATABASE_URL antes de prosseguir."
fi

# 2. sqlx-data.json existe
echo -n "[2/7] sqlx-data.json existe... "
if [ -f "beagle-hypergraph/sqlx-data.json" ]; then
  step_result pass ""
else
  step_result fail "Execute configure-sqlx-offline.sh para gerar o arquivo."
fi

# 3. sqlx-data.json é JSON válido
echo -n "[3/7] sqlx-data.json é JSON válido... "
if command -v jq >/dev/null 2>&1; then
  if jq empty beagle-hypergraph/sqlx-data.json >/dev/null 2>&1; then
    step_result pass ""
  else
    step_result fail "Conteúdo inválido; regenere com cargo sqlx prepare."
  fi
else
  step_result skip "jq não instalado; pule este teste ou instale jq."
fi

# 4. Compilação offline
echo -n "[4/7] Compilação offline... "
pushd beagle-hypergraph >/dev/null
if (unset DATABASE_URL && cargo check --all-features >/dev/null 2>&1); then
  step_result pass ""
else
  step_result fail "cargo check falhou sem DATABASE_URL"
fi
popd >/dev/null

# 5. Conectividade ao banco
echo -n "[5/7] Conectividade ao banco... "
if command -v psql >/dev/null 2>&1; then
  if [ -n "${DATABASE_URL:-}" ] && psql "$DATABASE_URL" -c "SELECT 1;" >/dev/null 2>&1; then
    step_result pass ""
  else
    step_result fail "Não foi possível conectar usando DATABASE_URL."
  fi
else
  step_result skip "psql não instalado; teste omitido."
fi

# 6. Extensão pgvector
echo -n "[6/7] Extensão pgvector instalada... "
if command -v psql >/dev/null 2>&1 && [ -n "${DATABASE_URL:-}" ]; then
  PGVECTOR=$(psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM pg_extension WHERE extname='vector';" 2>/dev/null || echo "0")
  if [ "$PGVECTOR" -eq 1 ]; then
    step_result pass ""
  else
    step_result fail "Extensão pgvector ausente; instale com CREATE EXTENSION vector;"
  fi
else
  step_result skip "psql indisponível; teste omitido."
fi

# 7. Tabelas principais
echo -n "[7/7] Tabelas obrigatórias presentes... "
if command -v psql >/dev/null 2>&1 && [ -n "${DATABASE_URL:-}" ]; then
  TABLE_COUNT=$(psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('nodes','hyperedges','edge_nodes');" 2>/dev/null || echo "0")
  if [ "$TABLE_COUNT" -eq 3 ]; then
    step_result pass ""
  else
    step_result fail "Encontradas ${TABLE_COUNT}/3 tabelas; execute as migrações."
  fi
else
  step_result skip "psql indisponível; teste omitido."
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "VALIDATION SUMMARY"
echo "════════════════════════════════════════════════════════════════════"
echo -e "Tests passed: ${GREEN}${PASS_COUNT}${NC}"
echo -e "Tests failed: ${RED}${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✓ ALL TESTS PASSED - System ready for development${NC}"
  exit 0
else
  echo -e "${RED}✗ SOME TESTS FAILED - Review configuration${NC}"
  exit 1
fi





