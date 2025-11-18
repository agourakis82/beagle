#!/bin/bash
# Script para instalar dependências OpenSSL necessárias para compilação

set -e

echo "📦 Instalando dependências OpenSSL para compilação Rust..."
echo ""

# Verificar se já está instalado
if dpkg -l | grep -q "^ii.*libssl-dev"; then
    echo "✅ libssl-dev já está instalado"
    exit 0
fi

# Instalar dependências
echo "Executando: sudo apt-get update"
sudo apt-get update -qq

echo "Executando: sudo apt-get install -y pkg-config libssl-dev"
sudo apt-get install -y pkg-config libssl-dev

echo ""
echo "✅ Dependências instaladas com sucesso!"
echo ""
echo "Agora você pode executar:"
echo "  export PATH=\"\$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:\$PATH\""
echo "  cargo build --package beagle-hermes --tests"

