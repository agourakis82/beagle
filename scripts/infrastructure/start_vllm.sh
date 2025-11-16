#!/bin/bash
#
# vLLM Server Startup Script
# ===========================
# Inicia servidor vLLM com Qwen 2.5 32B GPTQ
#
# USO:
#   ./start_vllm.sh [opções adicionais para vllm]
#
# VARIÁVEIS DE AMBIENTE:
#   VLLM_PORT    - Porta do servidor (padrão: 8001)
#   VLLM_HOST    - Host do servidor (padrão: 0.0.0.0)
#   MODEL_DIR    - Diretório do modelo (padrão: ~/models/qwen-32b-gptq)

set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configurações padrão
VENV_DIR="${HOME}/vllm-env"
MODEL_DIR="${MODEL_DIR:-${HOME}/models/qwen-32b-gptq}"
PORT="${VLLM_PORT:-8001}"
HOST="${VLLM_HOST:-0.0.0.0}"

# Verificar virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}ERROR: Virtual environment não encontrado em $VENV_DIR${NC}"
    echo "Execute: ./setup_vllm_t560.sh primeiro"
    exit 1
fi

# Ativar virtual environment
source "$VENV_DIR/bin/activate"

# Verificar modelo
if [ ! -d "$MODEL_DIR" ]; then
    echo -e "${RED}ERROR: Modelo não encontrado em $MODEL_DIR${NC}"
    echo "Execute: huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 --local-dir $MODEL_DIR"
    exit 1
fi

# Verificar GPU
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}ERROR: nvidia-smi não encontrado${NC}"
    exit 1
fi

# Mostrar informações
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}vLLM Server Starting...${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "📦 Modelo: $MODEL_DIR"
echo "🌐 Host: $HOST"
echo "🔌 Port: $PORT"
echo ""

# Mostrar status GPU
echo "🎮 GPU Status:"
nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu --format=csv,noheader
echo ""

# Iniciar servidor
echo -e "${YELLOW}Iniciando vLLM server...${NC}"
echo ""

python -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_DIR" \
  --dtype half \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --host "$HOST" \
  --port "$PORT" \
  --trust-remote-code \
  "$@"


