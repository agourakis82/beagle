#!/bin/bash
# BEAGLE Status Dashboard

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           BEAGLE v2.0 - System Status Dashboard          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Docker Services
echo -e "${YELLOW}🐳 Docker Services:${NC}"
if command -v docker &>/dev/null; then
  # Prefer docker compose (v2)
  if docker compose version &>/dev/null; then
    # Autodetect compose file
    COMPOSE_FILE="${COMPOSE_FILE}"
    if [ -z "$COMPOSE_FILE" ] && [ -f "./docker-compose.maria-mvp.yml" ]; then
      COMPOSE_FILE="./docker-compose.maria-mvp.yml"
    elif [ -z "$COMPOSE_FILE" ] && [ -f "/home/maria/beagle/docker-compose.maria-mvp.yml" ]; then
      COMPOSE_FILE="/home/maria/beagle/docker-compose.maria-mvp.yml"
    elif [ -z "$COMPOSE_FILE" ] && [ -f "./docker-compose.yml" ]; then
      COMPOSE_FILE="./docker-compose.yml"
    elif [ -z "$COMPOSE_FILE" ] && [ -f "/home/maria/beagle/docker-compose.yml" ]; then
      COMPOSE_FILE="/home/maria/beagle/docker-compose.yml"
    fi
    if [ -n "$COMPOSE_FILE" ]; then
      docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || echo "  ❌ docker compose ps failed for $COMPOSE_FILE"
    else
      # Fallback: show global compose projects and try ps without file
      docker compose ls 2>/dev/null || true
      docker compose ps 2>/dev/null || echo "  ❌ docker compose ps (no file) failed"
    fi
  elif command -v docker-compose &>/dev/null; then
    docker-compose -f docker-compose.maria-mvp.yml ps 2>/dev/null || echo "  ❌ docker-compose ps failed"
  else
    echo "  ❌ docker compose not available"
  fi
else
  echo "  ❌ docker not found"
fi
echo ""

# GPU Status
echo -e "${YELLOW}🎮 GPU Status:${NC}"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits | \
    awk -F', ' '{printf "  GPU: %s\n  VRAM: %s/%s MB (%.1f%%)\n  Utilization: %s%%\n  Temperature: %s°C\n", $1, $2, $3, ($2/$3*100), $4, $5}'
else
    echo "  ❌ nvidia-smi not available"
fi
echo ""

# Service Health
echo -e "${YELLOW}🏥 Service Health:${NC}"

# PostgreSQL
if docker exec beagle-postgres pg_isready -U beagle &>/dev/null; then
    PAPERS=$(docker exec beagle-postgres psql -U beagle -d beagle -t -c "SELECT COUNT(*) FROM papers;" 2>/dev/null | tr -d ' ')
    echo -e "  ${GREEN}✅${NC} PostgreSQL: UP (${PAPERS} papers)"
else
    echo -e "  ${RED}❌${NC} PostgreSQL: DOWN"
fi

# Redis
if docker exec beagle-redis redis-cli -a redis_secure_2025 ping &>/dev/null; then
    KEYS=$(docker exec beagle-redis redis-cli -a redis_secure_2025 DBSIZE 2>/dev/null | grep -oP '\\d+')
    echo -e "  ${GREEN}✅${NC} Redis: UP (${KEYS} keys)"
else
    echo -e "  ${RED}❌${NC} Redis: DOWN"
fi

# Qdrant
if curl -s http://localhost:6333/healthz &>/dev/null; then
    COLLECTIONS=$(curl -s http://localhost:6333/collections | grep -oP '\"collections\":\\[\\K[^\\]]*' | grep -o '{' | wc -l)
    echo -e "  ${GREEN}✅${NC} Qdrant: UP (${COLLECTIONS} collections)"
else
    echo -e "  ${RED}❌${NC} Qdrant: DOWN"
fi

# vLLM
if curl -s http://localhost:8000/health &>/dev/null; then
    MODEL=$(curl -s http://localhost:8000/v1/models | grep -oP '\"id\":\"\\K[^\"]+' | head -1)
    echo -e "  ${GREEN}✅${NC} vLLM: UP (${MODEL})"
else
    echo -e "  ${YELLOW}⏳${NC} vLLM: LOADING... (check logs)"
fi

echo ""

# Disk Usage
echo -e "${YELLOW}💾 Storage:${NC}"
df -h /home/maria/beagle/data | tail -1 | awk '{printf "  %s used of %s (%s)\n", $3, $2, $5}'
echo ""

# Corpus overview
PDF_DIR="/home/maria/beagle/data/corpus/papers"
FAILED_LOG="/home/maria/beagle/data/corpus/raw/failed_downloads.log"
RAW_DIR="/home/maria/beagle/data/corpus/raw"
PDF_COUNT=0
PENDING_FAILS=0
TOTAL_PAPERS=""
LATEST_JSON=""
if [ -d "$PDF_DIR" ]; then
  PDF_COUNT=$(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' 2>/dev/null | wc -l | tr -d ' ')
fi
if [ -f "$FAILED_LOG" ]; then
  PENDING_FAILS=$(grep -cve '^[[:space:]]*$' "$FAILED_LOG" 2>/dev/null || echo 0)
fi
if [ -d "$RAW_DIR" ]; then
  LATEST_JSON=$(ls -1t "$RAW_DIR"/corpus_*.json 2>/dev/null | head -1)
  if [ -n "$LATEST_JSON" ] && command -v python3 &>/dev/null; then
    TOTAL_PAPERS=$(python3 - "$LATEST_JSON" << 'EOF'
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, list):
        print(len(data))
    elif isinstance(data, dict) and "data" in data:
        v = data["data"]
        print(len(v) if isinstance(v, list) else 0)
    else:
        print(0)
except Exception:
    print(0)
EOF
)
  fi
fi
echo -e "${YELLOW}📚 Corpus:${NC}"
if [ -n "$LATEST_JSON" ]; then
  echo "  Último corpus: $(basename "$LATEST_JSON") (${TOTAL_PAPERS} papers)"
fi
echo "  PDFs OA baixados: ${PDF_COUNT}"
echo "  PDFs pendentes (fila retry): ${PENDING_FAILS}"
echo ""

# Last Update
echo -e "${BLUE}Last update: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}Node: maria ($(hostname))${NC}"


