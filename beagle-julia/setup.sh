#!/bin/bash
# Setup script para BEAGLE-Julia
# Executa: bash setup.sh

set -e

echo "🔬 BEAGLE-JULIA - Setup Script"
echo "================================"
echo ""

# Verificar se Julia está instalado
if ! command -v julia &> /dev/null; then
    echo "❌ Julia não encontrado!"
    echo ""
    echo "Instale Julia 1.10+ primeiro:"
    echo "  Linux/WSL: curl -fsSL https://install.julialang.org | sh"
    echo "  macOS:     brew install julia"
    echo "  Ou baixe:  https://julialang.org/downloads/"
    exit 1
fi

JULIA_VERSION=$(julia --version | grep -oP 'version \K[0-9]+\.[0-9]+')
echo "✅ Julia encontrado: versão $JULIA_VERSION"
echo ""

# Verificar versão mínima (1.10)
MAJOR=$(echo $JULIA_VERSION | cut -d. -f1)
MINOR=$(echo $JULIA_VERSION | cut -d. -f2)

if [ "$MAJOR" -lt 1 ] || ([ "$MAJOR" -eq 1 ] && [ "$MINOR" -lt 10 ]); then
    echo "⚠️  Julia 1.10+ recomendado (você tem $JULIA_VERSION)"
    echo "   Continuando mesmo assim..."
    echo ""
fi

# Ativar projeto e instalar dependências
echo "📦 Instalando dependências..."
julia --project=. -e 'using Pkg; Pkg.instantiate()'

echo ""
echo "✅ Setup completo!"
echo ""
echo "Para testar, execute:"
echo "  julia --project=. -e 'using BeagleQuantum; demo()'"
echo ""
echo "Ou entre no REPL:"
echo "  julia --project=."
echo "  julia> using BeagleQuantum"
echo "  julia> demo()"
echo ""




