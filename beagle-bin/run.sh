#!/bin/bash
# Script para rodar o BEAGLE SINGULARITY

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "  BEAGLE SINGULARITY - Starting..."
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verifica se SQLX_OFFLINE está configurado
if [ -z "$SQLX_OFFLINE" ]; then
    export SQLX_OFFLINE=true
    echo "ℹ️  SQLX_OFFLINE=true configurado automaticamente"
fi

# Build se necessário
if [ ! -f "target/release/beagle" ]; then
    echo "🔨 Compilando em modo release..."
    cargo build --release --bin beagle
    echo ""
fi

echo "🚀 Iniciando BEAGLE SINGULARITY..."
echo "   Pressione Ctrl+C para parar"
echo ""

# Executa
./target/release/beagle

