#!/bin/bash
# Mostra status atual do stress test de forma limpa

LOG_FILE="stress_test_output.log"

clear
echo "═══════════════════════════════════════════════════════════════"
echo "  BEAGLE STRESS TEST — STATUS EM TEMPO REAL"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "⚠️  Arquivo de log não encontrado: $LOG_FILE"
    exit 1
fi

# Progresso atual
PROGRESS=$(grep "Progresso:" "$LOG_FILE" 2>/dev/null | tail -1)
if [ -n "$PROGRESS" ]; then
    echo "$PROGRESS" | sed 's/.*Progresso: /📊 Progresso: /'
else
    echo "📊 Progresso: Aguardando primeiro ciclo..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Últimos 15 ciclos completos:"
echo ""

tail -200 "$LOG_FILE" 2>/dev/null | grep "CICLO.*COMPLETO" | tail -15 | \
    sed 's/.*CICLO/✅ CICLO/' | \
    sed 's/.*INFO beagle_stress_test:   //' | \
    awk '{printf "   %s\n", $0}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 Últimas respostas do Grok:"
echo ""

tail -100 "$LOG_FILE" 2>/dev/null | grep "Grok.*response" | tail -5 | \
    sed 's/.*INFO beagle_grok_api: //' | \
    sed 's/.*INFO beagle_nuclear: //' | \
    awk '{printf "   %s\n", $0}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Estatísticas
TOTAL=$(grep -c "CICLO #" "$LOG_FILE" 2>/dev/null || echo "0")
COMPLETE=$(grep -c "CICLO.*COMPLETO" "$LOG_FILE" 2>/dev/null || echo "0")

if [ "$TOTAL" -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=1; $COMPLETE * 100 / $TOTAL" | bc 2>/dev/null || echo "0")
    echo "📊 Estatísticas:"
    echo "   Ciclos iniciados: $TOTAL"
    echo "   Ciclos completos: $COMPLETE"
    echo "   Taxa de sucesso: ${SUCCESS_RATE}%"
    echo ""
fi

echo "Para atualizar: ./scripts/live_status.sh"
echo "Para monitorar em tempo real: tail -f stress_test_output.log | grep -E '(CICLO|Progresso|Grok)'"
echo ""

