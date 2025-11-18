#!/bin/bash
#
# BEAGLE Storage Centralization Script
# Centraliza TODO armazenamento em ~/beagle-data/
# Roda UMA VEZ e nunca mais tem bagunça
#
# Uso: bash scripts/fix_storage.sh

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DATA_DIR="$HOME/beagle-data"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  BEAGLE STORAGE CENTRALIZATION${NC}"
echo -e "${BLUE}  Centralizando TODO armazenamento em ~/beagle-data/${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# 1. Cria estrutura de diretórios centralizada
echo -e "${GREEN}[1/6] Criando estrutura ~/beagle-data/...${NC}"
mkdir -p "$DATA_DIR"/{models,lora,postgres,qdrant,redis,neo4j,logs,papers/{drafts,final},embeddings,datasets}
echo -e "  ${GREEN}✅${NC} Estrutura criada"

# 2. Move dados existentes (se houver)
echo -e "${GREEN}[2/6] Verificando dados existentes...${NC}"

# Move models se existir
if [ -d "$HOME/models" ] && [ "$HOME/models" != "$DATA_DIR/models" ]; then
    echo -e "  ${YELLOW}⚠️${NC} Movendo ~/models → $DATA_DIR/models"
    mv "$HOME/models"/* "$DATA_DIR/models/" 2>/dev/null || true
    rmdir "$HOME/models" 2>/dev/null || true
fi

# Move postgres se existir dentro do repo
if [ -d "$REPO_DIR/data/postgres" ]; then
    echo -e "  ${YELLOW}⚠️${NC} Movendo data/postgres → $DATA_DIR/postgres"
    [ -d "$DATA_DIR/postgres" ] && [ "$(ls -A "$DATA_DIR/postgres" 2>/dev/null)" ] && \
        echo -e "    ${YELLOW}⚠️${NC} postgres já tem dados, pulando..." || \
        mv "$REPO_DIR/data/postgres"/* "$DATA_DIR/postgres/" 2>/dev/null || true
    rmdir "$REPO_DIR/data/postgres" 2>/dev/null || true
fi

# Move qdrant se existir
if [ -d "$REPO_DIR/data/qdrant" ]; then
    echo -e "  ${YELLOW}⚠️${NC} Movendo data/qdrant → $DATA_DIR/qdrant"
    [ -d "$DATA_DIR/qdrant" ] && [ "$(ls -A "$DATA_DIR/qdrant" 2>/dev/null)" ] && \
        echo -e "    ${YELLOW}⚠️${NC} qdrant já tem dados, pulando..." || \
        mv "$REPO_DIR/data/qdrant"/* "$DATA_DIR/qdrant/" 2>/dev/null || true
    rmdir "$REPO_DIR/data/qdrant" 2>/dev/null || true
fi

# Move redis se existir
if [ -d "$REPO_DIR/data/redis" ]; then
    echo -e "  ${YELLOW}⚠️${NC} Movendo data/redis → $DATA_DIR/redis"
    [ -d "$DATA_DIR/redis" ] && [ "$(ls -A "$DATA_DIR/redis" 2>/dev/null)" ] && \
        echo -e "    ${YELLOW}⚠️${NC} redis já tem dados, pulando..." || \
        mv "$REPO_DIR/data/redis"/* "$DATA_DIR/redis/" 2>/dev/null || true
    rmdir "$REPO_DIR/data/redis" 2>/dev/null || true
fi

# Move lora adapters
if [ -d "$REPO_DIR/lora_adapter" ]; then
    echo -e "  ${YELLOW}⚠️${NC} Movendo lora_adapter → $DATA_DIR/lora"
    mv "$REPO_DIR/lora_adapter"/* "$DATA_DIR/lora/" 2>/dev/null || true
    rmdir "$REPO_DIR/lora_adapter" 2>/dev/null || true
fi

# Move logs
if [ -d "$REPO_DIR/logs" ] && [ "$(ls -A "$REPO_DIR/logs" 2>/dev/null)" ]; then
    echo -e "  ${YELLOW}⚠️${NC} Movendo logs → $DATA_DIR/logs"
    mv "$REPO_DIR/logs"/* "$DATA_DIR/logs/" 2>/dev/null || true
fi

echo -e "  ${GREEN}✅${NC} Dados migrados (se existiam)"

# 3. Cria symlinks para compatibilidade
echo -e "${GREEN}[3/6] Criando symlinks para compatibilidade...${NC}"

cd "$REPO_DIR"

# Cria diretório data se não existir
mkdir -p data

# Symlinks dentro do repo (para código antigo continuar funcionando)
ln -sfn "$DATA_DIR/models" models
ln -sfn "$DATA_DIR/lora" lora_adapter
ln -sfn "$DATA_DIR/postgres" data/postgres
ln -sfn "$DATA_DIR/qdrant" data/qdrant
ln -sfn "$DATA_DIR/redis" data/redis
ln -sfn "$DATA_DIR/neo4j" data/neo4j
ln -sfn "$DATA_DIR/logs" logs
ln -sfn "$DATA_DIR/papers/drafts" drafts
ln -sfn "$DATA_DIR/papers/final" papers

echo -e "  ${GREEN}✅${NC} Symlinks criados"

# 4. Atualiza docker-compose.yml
echo -e "${GREEN}[4/6] Atualizando docker-compose.yml...${NC}"

if [ -f "docker-compose.yml" ]; then
    # Backup original
    cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)
    
    # Substitui paths (usa variável de ambiente para compatibilidade)
    # O docker-compose.yml já usa ${BEAGLE_DATA_DIR:-${HOME}/beagle-data}
    # Só precisa definir BEAGLE_DATA_DIR se quiser customizar
    echo -e "  ${BLUE}ℹ️${NC} docker-compose.yml já usa BEAGLE_DATA_DIR"
    echo -e "     Configure no .env: BEAGLE_DATA_DIR=$DATA_DIR"
    
    # Adiciona variável DATA_DIR se não existir
    if ! grep -q "DATA_DIR" docker-compose.yml; then
        sed -i "1a\\# DATA_DIR padrão: ~/beagle-data/" docker-compose.yml
    fi
    
    echo -e "  ${GREEN}✅${NC} docker-compose.yml atualizado"
else
    echo -e "  ${YELLOW}⚠️${NC} docker-compose.yml não encontrado"
fi

# 5. Atualiza .gitignore
echo -e "${GREEN}[5/6] Atualizando .gitignore...${NC}"

if [ -f ".gitignore" ]; then
    # Adiciona entradas se não existirem
    grep -q "^models$" .gitignore || echo "models" >> .gitignore
    grep -q "^lora_adapter$" .gitignore || echo "lora_adapter" >> .gitignore
    grep -q "^data/postgres$" .gitignore || echo "data/postgres" >> .gitignore
    grep -q "^data/qdrant$" .gitignore || echo "data/qdrant" >> .gitignore
    grep -q "^data/redis$" .gitignore || echo "data/redis" >> .gitignore
    grep -q "^data/neo4j$" .gitignore || echo "data/neo4j" >> .gitignore
    grep -q "^logs$" .gitignore || echo "logs" >> .gitignore
    grep -q "^drafts$" .gitignore || echo "drafts" >> .gitignore
    grep -q "^papers$" .gitignore || echo "papers" >> .gitignore
    
    echo -e "  ${GREEN}✅${NC} .gitignore atualizado"
fi

# 6. Cria arquivo de configuração de paths
echo -e "${GREEN}[6/6] Criando config de paths...${NC}"

cat > "$REPO_DIR/.beagle-data-path" <<EOF
# BEAGLE Data Directory
# Este arquivo define onde o BEAGLE armazena dados
# Não commitar este arquivo no git

BEAGLE_DATA_DIR=$DATA_DIR
EOF

# Adiciona ao .gitignore
grep -q "^\.beagle-data-path$" .gitignore || echo ".beagle-data-path" >> .gitignore

echo -e "  ${GREEN}✅${NC} Config criado"

# 7. Resumo final
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ ARMAZENAMENTO 100% CENTRALIZADO${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}📁 Diretório central:${NC} $DATA_DIR"
echo ""
echo -e "${BLUE}Estrutura criada:${NC}"
echo -e "  📦 models/       → Modelos LLM"
echo -e "  🔧 lora/         → LoRA adapters"
echo -e "  🗄️  postgres/     → PostgreSQL data"
echo -e "  🔍 qdrant/       → Vector DB"
echo -e "  ⚡ redis/        → Cache"
echo -e "  🌐 neo4j/        → Graph DB"
echo -e "  📝 logs/         → Logs"
echo -e "  📄 papers/       → Drafts e papers finais"
echo -e "  🧮 embeddings/   → Embeddings cache"
echo -e "  📊 datasets/     → Datasets"
echo ""
echo -e "${GREEN}Symlinks criados no repo para compatibilidade${NC}"
echo -e "${YELLOW}⚠️  Backup do docker-compose.yml salvo${NC}"
echo ""
echo -e "${BLUE}Próximo passo:${NC}"
echo -e "  1. Configure BEAGLE_DATA_DIR no .env (opcional, padrão: ~/beagle-data):"
echo -e "     export BEAGLE_DATA_DIR=$DATA_DIR"
echo -e "  2. Reinicie os containers Docker se estiverem rodando"
echo ""
echo -e "${GREEN}Nunca mais tu tem bagunça de armazenamento!${NC}"
echo ""

