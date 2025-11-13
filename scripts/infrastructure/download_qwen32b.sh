#!/bin/bash
#
# Download Qwen 2.5 32B GPTQ Model
# ================================
# Baixa modelo em sessão tmux separada (não interfere com vLLM running)
#
# USO:
#   ./download_qwen32b.sh
#
# O download roda em background na sessão tmux "download"
# Para ver progresso: tmux attach -t download

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
info "Download Qwen 2.5 32B GPTQ Model"
info "════════════════════════════════════════════════════════════════════"
echo ""

# Verificar se HuggingFace está configurado
if ! command -v huggingface-cli &> /dev/null; then
    error "huggingface-cli não encontrado"
    info "Instalando: pip install huggingface-hub"
    source ~/vllm-env/bin/activate
    pip install huggingface-hub
fi

# Verificar se já existe sessão download
if tmux has-session -t download 2>/dev/null; then
    warn "Sessão 'download' já existe"
    read -p "Matar sessão existente e recomeçar? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        tmux kill-session -t download
        success "Sessão anterior removida"
    else
        info "Usando sessão existente. Para ver progresso: tmux attach -t download"
        exit 0
    fi
fi

# Verificar se modelo já existe
MODEL_DIR="$HOME/models/qwen-32b-gptq"
if [ -d "$MODEL_DIR" ]; then
    warn "Modelo já existe em $MODEL_DIR"
    read -p "Re-baixar? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        success "Usando modelo existente"
        exit 0
    else
        warn "Removendo modelo existente..."
        rm -rf "$MODEL_DIR"
    fi
fi

# Criar diretório
mkdir -p "$(dirname "$MODEL_DIR")"

info "Criando sessão tmux 'download'..."
info "Modelo será baixado em: $MODEL_DIR"
info "Tamanho estimado: ~18GB"
info "Tempo estimado: 20-30 minutos"
echo ""

# Criar script de download
DOWNLOAD_SCRIPT=$(mktemp)
cat > "$DOWNLOAD_SCRIPT" << 'DOWNLOAD_EOF'
#!/bin/bash
source ~/vllm-env/bin/activate

echo "════════════════════════════════════════════════════════════════════"
echo "📥 Downloading Qwen 2.5 32B GPTQ Model"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Modelo: Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4"
echo "Destino: ~/models/qwen-32b-gptq"
echo "Tamanho: ~18GB"
echo "Tempo estimado: 20-30 minutos"
echo ""
echo "Iniciando download..."
echo ""

# Tentar primeiro modelo (oficial)
if huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 \
  --local-dir ~/models/qwen-32b-gptq \
  --local-dir-use-symlinks False; then
    echo ""
    echo "✅ Download concluído com sucesso!"
    echo "Modelo disponível em: ~/models/qwen-32b-gptq"
else
    echo ""
    echo "⚠️  Primeiro modelo falhou, tentando alternativa..."
    echo ""
    
    # Alternativa: TheBloke
    if huggingface-cli download TheBloke/Qwen2-72B-Instruct-GPTQ \
      --local-dir ~/models/qwen-32b-gptq \
      --revision main; then
        echo ""
        echo "✅ Download concluído (alternativa)!"
        echo "Modelo disponível em: ~/models/qwen-32b-gptq"
    else
        echo ""
        echo "❌ Download falhou em ambas tentativas"
        echo "Verifique conexão e permissões do HuggingFace"
        exit 1
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Para iniciar servidor com Qwen 32B:"
echo "  ~/swap_to_qwen.sh"
echo "════════════════════════════════════════════════════════════════════"
DOWNLOAD_EOF

chmod +x "$DOWNLOAD_SCRIPT"

# Criar sessão tmux e executar download
tmux new-session -d -s download -x 120 -y 30 "$DOWNLOAD_SCRIPT"

success "Sessão 'download' criada e download iniciado!"
echo ""
info "Para ver progresso:"
echo "  ${GREEN}tmux attach -t download${NC}"
echo ""
info "Para detach (deixar rodando):"
echo "  ${YELLOW}Ctrl+B, depois D${NC}"
echo ""
info "Quando terminar, execute:"
echo "  ${GREEN}~/swap_to_qwen.sh${NC}"
echo ""

success "Download iniciado em background!"


