#!/bin/bash
#
# Swap vLLM Server: Mistral-7B → Qwen 32B
# =========================================
# Para servidor atual e inicia com Qwen 32B GPTQ
#
# USO:
#   ./swap_to_qwen.sh
#
# PRÉ-REQUISITOS:
#   - Modelo Qwen 32B baixado em ~/models/qwen-32b-gptq
#   - vLLM environment ativado

set -euo pipefail

# Cores
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

info "════════════════════════════════════════════════════════════════════"
info "Swap vLLM: Mistral-7B → Qwen 32B"
info "════════════════════════════════════════════════════════════════════"
echo ""

# Verificar se modelo existe
MODEL_DIR="$HOME/models/qwen-32b-gptq"
if [ ! -d "$MODEL_DIR" ]; then
    error "Modelo Qwen 32B não encontrado em $MODEL_DIR"
    echo ""
    info "Execute primeiro:"
    echo "  ${GREEN}./download_qwen32b.sh${NC}"
    exit 1
fi

# Verificar se tem arquivos do modelo
if [ -z "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]; then
    error "Diretório do modelo está vazio"
    echo ""
    info "Verifique se download foi concluído:"
    echo "  ${GREEN}tmux attach -t download${NC}"
    exit 1
fi

success "Modelo encontrado: $MODEL_DIR"
echo ""

# Parar servidor atual
info "🔄 Parando servidor vLLM atual (Mistral-7B)..."

if tmux has-session -t vllm 2>/dev/null; then
    tmux kill-session -t vllm
    success "Servidor Mistral-7B parado"
else
    warn "Sessão 'vllm' não encontrada (pode já estar parado)"
fi

# Aguardar liberação de recursos
info "⏳ Aguardando 5 segundos para liberação de recursos..."
sleep 5

# Verificar GPU
info "🎮 Verificando GPU..."
if ! command -v nvidia-smi &> /dev/null; then
    error "nvidia-smi não encontrado"
    exit 1
fi

GPU_MEMORY=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
info "Memória GPU em uso: ${GPU_MEMORY}MB"

if [ "$GPU_MEMORY" -gt 5000 ]; then
    warn "GPU ainda tem ${GPU_MEMORY}MB em uso. Aguardando mais 5 segundos..."
    sleep 5
fi

# Verificar virtual environment
VENV_DIR="$HOME/vllm-env"
if [ ! -d "$VENV_DIR" ]; then
    error "Virtual environment não encontrado em $VENV_DIR"
    exit 1
fi

# Criar script de start
START_SCRIPT=$(mktemp)
cat > "$START_SCRIPT" << 'START_EOF'
#!/bin/bash
source ~/vllm-env/bin/activate

MODEL_DIR="$HOME/models/qwen-32b-gptq"
PORT="${VLLM_PORT:-8000}"
HOST="${VLLM_HOST:-0.0.0.0}"

echo "════════════════════════════════════════════════════════════════════"
echo "🚀 Starting vLLM Server - Qwen 32B GPTQ"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "📦 Modelo: $MODEL_DIR"
echo "🌐 Host: $HOST"
echo "🔌 Port: $PORT"
echo ""

# Mostrar status GPU
echo "🎮 GPU Status:"
nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu --format=csv,noheader
echo ""

echo "Iniciando servidor..."
echo ""

python -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_DIR" \
  --dtype half \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --host "$HOST" \
  --port "$PORT" \
  --trust-remote-code
START_EOF

chmod +x "$START_SCRIPT"

# Iniciar novo servidor
info "🚀 Iniciando servidor Qwen 32B..."

tmux new-session -d -s vllm -x 120 -y 30 "$START_SCRIPT"

# Aguardar inicialização
info "⏳ Aguardando 10 segundos para inicialização..."
sleep 10

# Testar se servidor está respondendo
info "🧪 Testando servidor..."

MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -f "http://localhost:8000/v1/models" > /dev/null 2>&1; then
        success "Servidor está respondendo!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            warn "Aguardando servidor... ($RETRY_COUNT/$MAX_RETRIES)"
            sleep 5
        else
            error "Servidor não está respondendo após $MAX_RETRIES tentativas"
            echo ""
            info "Verifique logs:"
            echo "  ${GREEN}tmux attach -t vllm${NC}"
            exit 1
        fi
    fi
done

# Mostrar modelos disponíveis
echo ""
info "Modelos disponíveis:"
curl -s "http://localhost:8000/v1/models" | python3 -m json.tool 2>/dev/null | grep -A 2 '"id"' || curl -s "http://localhost:8000/v1/models"

echo ""
info "════════════════════════════════════════════════════════════════════"
success "✅ Qwen 32B iniciado com sucesso na porta 8000!"
info "════════════════════════════════════════════════════════════════════"
echo ""
info "🧪 Testar servidor:"
echo "  ${GREEN}curl http://localhost:8000/v1/models${NC}"
echo ""
info "📊 Ver logs:"
echo "  ${GREEN}tmux attach -t vllm${NC}"
echo ""
info "🛑 Parar servidor:"
echo "  ${YELLOW}tmux kill-session -t vllm${NC}"
echo ""

success "Swap concluído!"


