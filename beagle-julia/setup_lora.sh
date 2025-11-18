#!/bin/bash
# Setup script para LoRA Training (Unsloth)
# Executa: bash setup_lora.sh

set -e

echo "🔬 BEAGLE LoRA TRAINING - Setup"
echo "================================"
echo ""

# Verifica CUDA disponível
if command -v nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA GPU detectada"
    nvidia-smi --query-gpu=name --format=csv,noheader | head -1
    echo ""
    
    CUDA_VERSION=$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+' | head -1)
    echo "CUDA Version: $CUDA_VERSION"
    echo ""
    
    # Detecta arquitetura
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | tr '[:upper:]' '[:lower:]')
    
    if [[ $GPU_NAME == *"ampere"* ]] || [[ $GPU_NAME == *"a100"* ]] || [[ $GPU_NAME == *"3090"* ]]; then
        UNSLOTH_VARIANT="cu121-ampere-torch240"
    elif [[ $GPU_NAME == *"hoppler"* ]] || [[ $GPU_NAME == *"h100"* ]]; then
        UNSLOTH_VARIANT="cu121-hoppler-torch240"
    else
        UNSLOTH_VARIANT="cu121-ampere-torch240"  # default
    fi
    
    echo "Instalando Unsloth para: $UNSLOTH_VARIANT"
else
    echo "⚠️  NVIDIA GPU não detectada. Usando CPU (não recomendado para treinamento)."
    UNSLOTH_VARIANT="cpu-torch240"
fi

echo ""
echo "📦 Instalando Unsloth..."
pip install "unsloth[$UNSLOTH_VARIANT]" --extra-index-url https://download.unsloth.ai

echo ""
echo "✅ Setup LoRA Training completo!"
echo ""
echo "Para testar, execute no Julia REPL:"
echo "  include(\"lora_training.jl\")"
echo "  using BeagleLoRATraining"
echo ""
echo "Ou use com adversarial:"
echo "  include(\"adversarial.jl\")"
echo "  using BeagleAdversarial"
echo "  adversarial_self_play(\"...\", enable_lora_training=true)"
echo ""

