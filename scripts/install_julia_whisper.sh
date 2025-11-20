#!/bin/bash
# Script para instalar Julia e Whisper.cpp no sistema

set -e

echo "🔧 Instalando Julia e Whisper.cpp..."

# 1. Instalar Julia
if ! command -v julia &> /dev/null; then
    echo "📦 Instalando Julia..."
    cd /tmp
    wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz
    tar -xzf julia-1.10.0-linux-x86_64.tar.gz
    sudo mv julia-1.10.0 /opt/julia
    sudo ln -sf /opt/julia/bin/julia /usr/local/bin/julia
    rm -f julia-1.10.0-linux-x86_64.tar.gz
    echo "✅ Julia instalado: $(julia --version)"
else
    echo "✅ Julia já instalado: $(julia --version)"
fi

# 2. Instalar Whisper.cpp
if ! command -v whisper-cpp &> /dev/null; then
    echo "📦 Instalando Whisper.cpp..."
    cd /tmp
    if [ ! -d whisper.cpp ]; then
        git clone https://github.com/ggerganov/whisper.cpp.git
    fi
    cd whisper.cpp
    make
    sudo cp whisper /usr/local/bin/whisper-cpp
    echo "✅ Whisper.cpp instalado"
else
    echo "✅ Whisper.cpp já instalado"
fi

# 3. Instalar dependências Julia do projeto
if [ -d "/mnt/e/workspace/beagle-remote/beagle-julia" ]; then
    echo "📦 Instalando dependências Julia do projeto..."
    cd /mnt/e/workspace/beagle-remote/beagle-julia
    julia --project=. -e 'using Pkg; Pkg.instantiate()'
    echo "✅ Dependências Julia instaladas"
fi

echo "🎉 Instalação completa!"

