#!/bin/bash

# Setup Whisper.cpp - 100% Local, Zero Nuvem
# Roda no Mac (M3 Max) ou Linux (tower)

set -e

echo "🎤 BEAGLE Whisper Setup"
echo "======================="
echo ""

# Detecta sistema
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "✅ macOS detectado"
    WHISPER_DIR="$HOME/whisper.cpp"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "✅ Linux detectado"
    WHISPER_DIR="$HOME/whisper.cpp"
else
    echo "❌ Sistema não suportado: $OSTYPE"
    exit 1
fi

# 1. Clona whisper.cpp
if [ ! -d "$WHISPER_DIR" ]; then
    echo "📦 Clonando whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    cd "$WHISPER_DIR"
else
    echo "✅ whisper.cpp já existe"
    cd "$WHISPER_DIR"
    git pull
fi

# 2. Compila
echo ""
echo "🔧 Compilando whisper.cpp..."
make

if [ ! -f "$WHISPER_DIR/main" ]; then
    echo "❌ Falha ao compilar whisper.cpp"
    exit 1
fi

echo "✅ whisper.cpp compilado"

# 3. Baixa modelo
echo ""
echo "📥 Baixando modelo large-v3 (qualidade alta, ~1.5GB)..."
if [ ! -f "$WHISPER_DIR/models/ggml-large-v3.bin" ]; then
    cd "$WHISPER_DIR"
    bash models/download-ggml-model.sh large-v3
else
    echo "✅ Modelo já existe"
fi

# 4. Testa
echo ""
echo "🧪 Testando whisper.cpp..."
if [ -f "$WHISPER_DIR/samples/jfk.wav" ]; then
    "$WHISPER_DIR/main" -m "$WHISPER_DIR/models/ggml-large-v3.bin" -f "$WHISPER_DIR/samples/jfk.wav" -l en --no-print-progress > /dev/null 2>&1
    echo "✅ Teste passou"
else
    echo "⚠️  Arquivo de teste não encontrado (ok, continua)"
fi

echo ""
echo "=" ^ 60)
echo "✅ Whisper.cpp instalado e pronto!"
echo "=" ^ 60)
echo ""
echo "📁 Localização:"
echo "   Executável: $WHISPER_DIR/main"
echo "   Modelo: $WHISPER_DIR/models/ggml-large-v3.bin"
echo ""
echo "🚀 Como usar:"
echo "   cargo run --example voice_assistant --package beagle-whisper"
echo ""

