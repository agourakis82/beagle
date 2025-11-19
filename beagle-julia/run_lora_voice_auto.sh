#!/bin/bash
# BEAGLE LoRA Voice - Execução Automática
# Treina LoRA com drafts reais em 15 minutos no M3 Max

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 BEAGLE LoRA Voice - Treinamento Automático"
echo "=============================================="
echo ""

# Verifica se Julia está instalado
if ! command -v julia &> /dev/null; then
    echo "❌ Julia não encontrado!"
    echo "   Instale Julia: https://julialang.org/downloads/"
    exit 1
fi

# Verifica se o diretório de drafts existe
DRAFTS_DIR="${BEAGLE_DATA_DIR:-$HOME/beagle-data}/papers/drafts"
if [ ! -d "$DRAFTS_DIR" ]; then
    echo "⚠️  Diretório de drafts não existe: $DRAFTS_DIR"
    echo "   Execute o adversarial loop primeiro para gerar drafts"
    exit 1
fi

# Conta drafts disponíveis
DRAFT_COUNT=$(find "$DRAFTS_DIR" -name "draft_iter_*.md" | wc -l)
if [ "$DRAFT_COUNT" -lt 2 ]; then
    echo "⚠️  Menos de 2 drafts encontrados ($DRAFT_COUNT)"
    echo "   Execute o adversarial loop primeiro:"
    echo "   julia beagle-julia/adversarial.jl"
    exit 1
fi

echo "✅ Encontrados $DRAFT_COUNT drafts em $DRAFTS_DIR"
echo ""

# Executa o treinamento
echo "🎯 Iniciando treinamento LoRA..."
echo ""

julia --project=. lora_voice_auto.jl

echo ""
echo "✅ Treinamento concluído!"
echo ""
echo "💡 Para usar o adapter no vLLM:"
echo "   ssh maria 'cd /home/ubuntu/beagle && docker-compose restart vllm'"

