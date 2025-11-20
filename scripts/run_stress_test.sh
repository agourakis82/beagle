#!/bin/bash
# BEAGLE Stress Test - Executa 100 ciclos completos
# Roda com: ./scripts/run_stress_test.sh

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "  BEAGLE STRESS TEST — FULL CYCLE 100x"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Compila em release
echo "🔨 Compilando em release..."
cargo build --release --bin beagle-stress-test

echo ""
echo "🚀 Executando stress test..."
echo ""

# Roda o teste
RUST_LOG=info cargo run --release --bin beagle-stress-test

echo ""
echo "✅ Stress test concluído!"
echo "   Verifique o relatório JSON gerado: beagle_stress_test_*.json"
echo ""

