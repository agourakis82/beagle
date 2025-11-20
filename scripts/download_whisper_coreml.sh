#!/bin/bash
# Script para baixar modelo Whisper CoreML otimizado para Neural Engine (M3 Max)

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "  DOWNLOAD WHISPER COREML — NEURAL ENGINE (M3 MAX)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

MODELS_DIR="/home/agourakis82/beagle-models"
mkdir -p "$MODELS_DIR"

cd "$MODELS_DIR"

echo "📦 Baixando Whisper tiny CoreML otimizado para Neural Engine..."
echo ""

# Opção 1: Modelo CoreML da Apple (se disponível)
if [ -z "$SKIP_COREML" ]; then
    echo "Tentando baixar modelo CoreML da Apple..."
    
    # URL do Hugging Face (se disponível)
    COREML_URL="https://huggingface.co/apple/coreml-whisper-tiny/resolve/main/whisper_tiny.mlmodelc.zip"
    
    if curl -L -f -o whisper_tiny_coreml.zip "$COREML_URL" 2>/dev/null; then
        echo "✅ Modelo CoreML baixado"
        unzip -q whisper_tiny_coreml.zip -d "$MODELS_DIR"
        rm whisper_tiny_coreml.zip
        echo "✅ Modelo CoreML extraído em: $MODELS_DIR/whisper_tiny_coreml.mlmodelc"
    else
        echo "⚠️  Modelo CoreML não disponível, usando GGML padrão"
    fi
fi

# Opção 2: Modelo GGML padrão (whisper.cpp)
echo ""
echo "📦 Baixando modelo GGML padrão (whisper.cpp)..."
echo ""

GGML_TINY_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"

if curl -L -f -o ggml-tiny.bin "$GGML_TINY_URL"; then
    echo "✅ Modelo GGML baixado: $MODELS_DIR/ggml-tiny.bin"
else
    echo "❌ Falha ao baixar modelo GGML"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ DOWNLOAD COMPLETO"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Modelos disponíveis:"
ls -lh "$MODELS_DIR"/*.bin "$MODELS_DIR"/*.mlmodelc 2>/dev/null || true
echo ""
echo "Para usar:"
echo "  let whisper = WhisperNeuralEngine::new();"
echo "  let text = whisper.transcribe(\"/path/to/audio.wav\").await?;"
echo ""

