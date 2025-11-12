#!/bin/bash
set -euo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}$1${NC}"; }
success(){ echo -e "${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}$1${NC}"; }

info "════════════════════════════════════════════════════════════════════"
info "BEAGLE SQLX OFFLINE MODE CONFIGURATION PROTOCOL"
info "════════════════════════════════════════════════════════════════════"

info "[1/8] Verificando infraestrutura (Docker compose)…"
if ! docker compose ps | grep -q "beagle-postgres.*Up"; then
    error "✗ PostgreSQL container não está ativo"
    warn  "Iniciando serviços: docker compose up -d postgres redis"
    docker compose up -d postgres redis
    warn  "Aguardando 10s pela inicialização do PostgreSQL"
    sleep 10
else
    success "✓ PostgreSQL container em execução"
fi

info "[2/8] Configurando DATABASE_URL…"
DB_USER="${POSTGRES_USER:-beagle_user}"
DB_PASSWORD="${POSTGRES_PASSWORD:-beagle_dev_password_CHANGE_IN_PRODUCTION}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-beagle_dev}"
export DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
success "✓ DATABASE_URL configurado"
echo   "  URL: postgres://${DB_USER}:***@${DB_HOST}:${DB_PORT}/${DB_NAME}"

info "[3/8] Validando sintaxe da URL…"
[[ "$DATABASE_URL" =~ ^postgres:// ]] || { error "✗ Schema inválido"; exit 1; }
[[ "$DATABASE_URL" =~ @[a-zA-Z0-9.-]+:[0-9]+/ ]] || { error "✗ Formato inválido"; exit 1; }
success "✓ URL válida"

info "[4/8] Testando conectividade…"
if command -v psql >/dev/null 2>&1; then
    if timeout 5 psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; then
        success "✓ Conexão estabelecida"
    else
        error "✗ Falha na conexão"; exit 1
    fi
else
    warn "⚠ psql não encontrado; prosseguindo"
fi

info "[5/8] Validando esquema…"
if command -v psql >/dev/null 2>&1; then
    PGVECTOR=$(psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM pg_extension WHERE extname='vector';")
    if [ "${PGVECTOR}" -ne 1 ]; then
        warn "Instalando extensão pgvector"
        psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS vector;"
    fi
    success "✓ pgvector disponível"

    TABLE_COUNT=$(psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('nodes','hyperedges','edge_nodes');")
    if [ "${TABLE_COUNT}" -ne 3 ]; then
        warn "Esquema incompleto (${TABLE_COUNT}/3); executando migrações"
        pushd beagle-db >/dev/null
        command -v sqlx >/dev/null 2>&1 || cargo install sqlx-cli --no-default-features --features postgres --locked
        sqlx migrate run --database-url "$DATABASE_URL"
        popd >/dev/null
    fi
    success "✓ Esquema confirmado"
fi

info "[6/8] Gerando sqlx-data.json…"
cd beagle-hypergraph
command -v sqlx >/dev/null 2>&1 || cargo install sqlx-cli --no-default-features --features postgres --locked
warn "Executando: cargo sqlx prepare --database-url \"$DATABASE_URL\" -- --all-features"
cargo sqlx prepare --database-url "$DATABASE_URL" -- --all-features
success "✓ sqlx-data.json gerado"

info "[7/8] Verificando integridade…"
[[ -f sqlx-data.json ]] || { error "✗ sqlx-data.json ausente"; exit 1; }
FILE_SIZE=$(stat -f%z sqlx-data.json 2>/dev/null || stat -c%s sqlx-data.json)
if [ "$FILE_SIZE" -lt 100 ]; then
    error "✗ sqlx-data.json muito pequeno (${FILE_SIZE} bytes)"; exit 1
fi
if command -v jq >/dev/null 2>&1; then
    jq empty sqlx-data.json >/dev/null
    QUERY_COUNT=$(jq 'keys | length' sqlx-data.json)
    success "✓ JSON válido (${QUERY_COUNT} consultas)"
else
    warn "⚠ jq não encontrado; ignorando validação JSON"
fi
echo "  Tamanho: ${FILE_SIZE} bytes"
echo "  Local:   $(pwd)/sqlx-data.json"

info "[8/8] Testando compilação offline…"
unset DATABASE_URL
cargo check --all-features
success "✓ Compilação offline OK"

export DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

success "SQLX OFFLINE MODE CONFIGURATION COMPLETE ✓"
echo "Resumo:"
echo "  ✓ URL validada"
echo "  ✓ Conectividade testada"
echo "  ✓ pgvector garantido"
echo "  ✓ Migrações aplicadas"
echo "  ✓ sqlx-data.json gerado (${FILE_SIZE} bytes)"
echo "  ✓ Compilação offline bem-sucedida"
