#!/bin/bash
#
# vLLM Server Setup Script for T560 (L4 24GB) - MÁQUINA LOCAL
# ============================================================
# Configura servidor de inferência vLLM com Qwen 2.5 32B GPTQ
#
# USO:
#   chmod +x setup_vllm_t560.sh
#   ./setup_vllm_t560.sh
#
# PRÉ-REQUISITOS:
#   - Executar LOCALMENTE na máquina T560
#   - Usuário com sudo
#   - GPU L4 24GB disponível
#   - ~50GB espaço em disco livre

set -euo pipefail

# Cores para output
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
info "vLLM SERVER SETUP - T560 (L4 24GB)"
info "════════════════════════════════════════════════════════════════════"

# ============================================================================
# 1. VERIFICAR PRÉ-REQUISITOS
# ============================================================================

info "[1/11] Verificando pré-requisitos..."

# Verificar se está rodando como root (não recomendado)
if [ "$EUID" -eq 0 ]; then
    warn "Script rodando como root. Recomendado usar usuário normal com sudo."
fi

# Verificar GPU
if ! command -v nvidia-smi &> /dev/null; then
    error "nvidia-smi não encontrado. GPU NVIDIA não detectada ou drivers não instalados."
    exit 1
fi

GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader)
info "GPU detectada: $GPU_INFO"

# Verificar se é L4
if ! echo "$GPU_INFO" | grep -qi "L4"; then
    warn "GPU não é L4. Script otimizado para L4 24GB."
    read -p "Continuar mesmo assim? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

success "Pré-requisitos OK"

# ============================================================================
# 2. ATUALIZAR SISTEMA
# ============================================================================

info "[2/11] Atualizando sistema..."
sudo apt update && sudo apt upgrade -y
success "Sistema atualizado"

# ============================================================================
# 3. INSTALAR CUDA (se necessário)
# ============================================================================

info "[3/11] Verificando CUDA..."

if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
    info "CUDA já instalado: versão $CUDA_VERSION"
    
    if [[ $(echo "$CUDA_VERSION >= 12.0" | bc -l) -eq 1 ]]; then
        success "CUDA 12.0+ detectado, pulando instalação"
    else
        warn "CUDA < 12.0 detectado. Recomendado atualizar para CUDA 12.4"
        read -p "Instalar CUDA 12.4? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Instalando CUDA 12.4..."
            wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
            sudo dpkg -i cuda-keyring_1.1-1_all.deb
            sudo apt update
            sudo apt install -y cuda-toolkit-12-4
            success "CUDA 12.4 instalado"
        fi
    fi
else
    info "CUDA não encontrado. Instalando CUDA 12.4..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt update
    sudo apt install -y cuda-toolkit-12-4
    success "CUDA 12.4 instalado"
fi

# ============================================================================
# 4. INSTALAR PYTHON 3.11
# ============================================================================

info "[4/11] Verificando Python 3.11..."

if command -v python3.11 &> /dev/null; then
    PYTHON_VERSION=$(python3.11 --version)
    success "Python 3.11 já instalado: $PYTHON_VERSION"
else
    info "Instalando Python 3.11..."
    sudo apt install -y python3.11 python3.11-venv python3-pip
    success "Python 3.11 instalado"
fi

# ============================================================================
# 5. CRIAR VIRTUAL ENVIRONMENT
# ============================================================================

info "[5/11] Criando virtual environment..."

VENV_DIR="$HOME/vllm-env"

if [ -d "$VENV_DIR" ]; then
    warn "Virtual environment já existe em $VENV_DIR"
    read -p "Recriar? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$VENV_DIR"
        python3.11 -m venv "$VENV_DIR"
        success "Virtual environment recriado"
    else
        success "Usando virtual environment existente"
    fi
else
    python3.11 -m venv "$VENV_DIR"
    success "Virtual environment criado em $VENV_DIR"
fi

# ============================================================================
# 6. INSTALAR vLLM E DEPENDÊNCIAS
# ============================================================================

info "[6/11] Instalando vLLM e dependências..."

source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install vllm torch torchvision --index-url https://download.pytorch.org/whl/cu121

success "vLLM instalado"

# ============================================================================
# 7. VERIFICAR GPU
# ============================================================================

info "[7/11] Verificando GPU..."

nvidia-smi

GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
info "Memória GPU: ${GPU_MEMORY}MB"

if [ "$GPU_MEMORY" -lt 20000 ]; then
    warn "GPU tem menos de 20GB. Qwen 32B GPTQ pode não caber."
fi

success "GPU verificada"

# ============================================================================
# 8. CONFIGURAR HUGGINGFACE
# ============================================================================

info "[8/11] Configurando HuggingFace..."

if ! command -v huggingface-cli &> /dev/null; then
    pip install huggingface-hub
fi

if [ -z "${HF_TOKEN:-}" ]; then
    warn "HF_TOKEN não definido. Você precisará fazer login manualmente."
    info "Execute: huggingface-cli login"
    info "Ou defina: export HF_TOKEN=seu_token_aqui"
else
    info "Usando HF_TOKEN do ambiente"
    echo "$HF_TOKEN" | huggingface-cli login --token "$HF_TOKEN"
    success "HuggingFace configurado"
fi

# ============================================================================
# 9. BAIXAR MODELO QWEN 2.5 32B GPTQ
# ============================================================================

info "[9/11] Baixando modelo Qwen 2.5 32B GPTQ..."

MODEL_DIR="$HOME/models/qwen-32b-gptq"

if [ -d "$MODEL_DIR" ]; then
    warn "Modelo já existe em $MODEL_DIR"
    read -p "Re-baixar? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        success "Usando modelo existente"
    else
        rm -rf "$MODEL_DIR"
        huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 \
            --local-dir "$MODEL_DIR"
        success "Modelo baixado"
    fi
else
    mkdir -p "$(dirname "$MODEL_DIR")"
    info "Baixando modelo (isso pode levar 30+ minutos, ~18GB)..."
    huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 \
        --local-dir "$MODEL_DIR"
    success "Modelo baixado em $MODEL_DIR"
fi

# ============================================================================
# 10. CRIAR SCRIPT DE START
# ============================================================================

info "[10/11] Criando script de start..."

START_SCRIPT="$HOME/start_vllm.sh"

cat > "$START_SCRIPT" << 'EOF'
#!/bin/bash
# vLLM Server Startup Script
# Auto-gerado por setup_vllm_t560.sh

set -e

source ~/vllm-env/bin/activate

MODEL_DIR="$HOME/models/qwen-32b-gptq"
PORT="${VLLM_PORT:-8001}"
HOST="${VLLM_HOST:-0.0.0.0}"

if [ ! -d "$MODEL_DIR" ]; then
    echo "ERROR: Modelo não encontrado em $MODEL_DIR"
    echo "Execute: huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 --local-dir $MODEL_DIR"
    exit 1
fi

echo "🚀 Iniciando vLLM server..."
echo "   Modelo: $MODEL_DIR"
echo "   Host: $HOST"
echo "   Port: $PORT"

python -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_DIR" \
  --dtype half \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --host "$HOST" \
  --port "$PORT" \
  --trust-remote-code \
  "$@"
EOF

chmod +x "$START_SCRIPT"
success "Script de start criado: $START_SCRIPT"

# ============================================================================
# 11. INSTALAR TMUX (para manter servidor rodando)
# ============================================================================

info "[11/11] Instalando tmux..."

if command -v tmux &> /dev/null; then
    success "tmux já instalado"
else
    sudo apt install -y tmux
    success "tmux instalado"
fi

# ============================================================================
# RESUMO FINAL
# ============================================================================

info "════════════════════════════════════════════════════════════════════"
success "SETUP COMPLETO!"
info "════════════════════════════════════════════════════════════════════"

echo ""
info "Próximos passos:"
echo ""
echo "1. Iniciar servidor (em tmux):"
echo "   ${GREEN}tmux new -s vllm${NC}"
echo "   ${GREEN}~/start_vllm.sh${NC}"
echo "   ${YELLOW}Ctrl+B, D${NC} para detach"
echo ""
echo "2. Testar API:"
echo "   ${GREEN}curl http://localhost:8001/v1/models${NC}"
echo ""
echo "3. Obter IP para acesso remoto:"
echo "   ${GREEN}ip addr show | grep 'inet '${NC}"
echo ""
echo "4. Usar de outro host:"
echo "   ${GREEN}http://<IP_DO_T560>:8001${NC}"
echo ""

success "Setup concluído com sucesso!"

