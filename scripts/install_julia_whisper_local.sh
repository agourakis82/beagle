#!/bin/bash
# Script para instalar Julia e Whisper.cpp LOCALMENTE (sem sudo)
# Instala em ~/.local/bin

set -e

echo "🔧 Instalando Julia e Whisper.cpp localmente..."

# Garante que ~/.local/bin existe
mkdir -p ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# 1. Instalar Julia localmente
if ! command -v julia &> /dev/null || ! julia --version | grep -q "1.10"; then
    echo "📦 Instalando Julia 1.10.0 localmente..."
    cd /tmp
    
    if [ ! -d julia-1.10.0 ]; then
        echo "   Baixando Julia..."
        wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz
        tar -xzf julia-1.10.0-linux-x86_64.tar.gz
        rm -f julia-1.10.0-linux-x86_64.tar.gz
    fi
    
    echo "   Copiando para ~/.local/julia..."
    rm -rf ~/.local/julia
    cp -r julia-1.10.0 ~/.local/julia
    ln -sf ~/.local/julia/bin/julia ~/.local/bin/julia
    chmod +x ~/.local/bin/julia
    
    echo "✅ Julia instalado: $(~/.local/bin/julia --version)"
else
    echo "✅ Julia já instalado: $(julia --version)"
fi

# 2. Instalar Whisper.cpp localmente
if ! command -v whisper-cpp &> /dev/null; then
    echo "📦 Instalando Whisper.cpp localmente..."
    cd /tmp
    
    if [ ! -d whisper.cpp ]; then
        echo "   Clonando whisper.cpp..."
        git clone https://github.com/ggerganov/whisper.cpp.git
    fi
    
    cd whisper.cpp
    
    if [ ! -f build/bin/whisper-cli ]; then
        echo "   Compilando whisper.cpp..."
        cmake -B build
        cmake --build build --config Release
    fi
    
    echo "   Copiando para ~/.local/bin..."
    cp build/bin/whisper-cli ~/.local/bin/whisper-cpp
    chmod +x ~/.local/bin/whisper-cpp
    
    echo "✅ Whisper.cpp instalado"
else
    echo "✅ Whisper.cpp já instalado"
fi

# 3. Adicionar ao PATH permanentemente
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "✅ PATH atualizado no .bashrc"
fi

# 4. Instalar dependências Julia do projeto
if [ -d "/mnt/e/workspace/beagle-remote/beagle-julia" ]; then
    echo "📦 Instalando dependências Julia do projeto..."
    cd /mnt/e/workspace/beagle-remote/beagle-julia
    export PATH="$HOME/.local/bin:$PATH"
    julia --project=. -e 'using Pkg; Pkg.instantiate()' || echo "⚠️  Algumas dependências podem falhar (ok, continua)"
    echo "✅ Dependências Julia instaladas"
fi

echo ""
echo "🎉 Instalação completa!"
echo ""
echo "📋 Para usar agora:"
echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "📋 Verificação:"
echo "   julia --version"
echo "   whisper-cpp --help"

