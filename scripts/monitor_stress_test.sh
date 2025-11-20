#!/bin/bash
# Monitora o progresso do stress test em tempo real

LOG_FILE="stress_test_output.log"
REPORT_PATTERN="beagle_stress_test_*.json"

echo "═══════════════════════════════════════════════════════════════"
echo "  BEAGLE STRESS TEST — MONITORAMENTO"
echo "═══════════════════════════════════════════════════════════════"
echo ""

while true; do
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "  BEAGLE STRESS TEST — MONITORAMENTO"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Verifica se o processo está rodando
    if ! pgrep -f "beagle-stress-test" > /dev/null; then
        echo "⚠️  Processo não encontrado. Teste pode ter terminado."
        echo ""
        
        # Verifica se há relatório gerado
        if ls $REPORT_PATTERN 1> /dev/null 2>&1; then
            LATEST_REPORT=$(ls -t $REPORT_PATTERN | head -1)
            echo "✅ Relatório encontrado: $LATEST_REPORT"
            echo ""
            echo "Resumo:"
            cat "$LATEST_REPORT" | jq -r '
                "  Total de ciclos: \(.total_cycles)
  Ciclos bem-sucedidos: \(.successful_cycles)
  Ciclos falhados: \(.failed_cycles)
  Taxa de sucesso: \(.success_rate | round)%
  Duração total: \(.total_duration_ms / 1000 | round)s
  Duração média: \(.avg_duration_ms | round)ms"'
            echo ""
        fi
        break
    fi
    
    # Mostra últimas linhas do log
    echo "📊 Últimas 20 linhas do log:"
    echo "───────────────────────────────────────────────────────────"
    tail -20 "$LOG_FILE" 2>/dev/null | grep -E "(CICLO|Progresso|✅|❌|⚠️)" || echo "Aguardando logs..."
    echo ""
    
    # Estatísticas do log
    if [ -f "$LOG_FILE" ]; then
        TOTAL_CYCLES=$(grep -c "CICLO #" "$LOG_FILE" 2>/dev/null || echo "0")
        SUCCESS_CYCLES=$(grep -c "CICLO.*COMPLETO" "$LOG_FILE" 2>/dev/null || echo "0")
        PROGRESS=$(grep "Progresso:" "$LOG_FILE" | tail -1 | grep -oE "[0-9]+/[0-9]+" || echo "0/0")
        
        echo "📈 Estatísticas:"
        echo "   Ciclos iniciados: $TOTAL_CYCLES"
        echo "   Ciclos completos: $SUCCESS_CYCLES"
        echo "   Progresso: $PROGRESS"
        echo ""
    fi
    
    # Verifica se há relatório parcial
    if ls $REPORT_PATTERN 1> /dev/null 2>&1; then
        LATEST_REPORT=$(ls -t $REPORT_PATTERN | head -1)
        echo "📄 Relatório: $LATEST_REPORT"
        echo ""
    fi
    
    echo "───────────────────────────────────────────────────────────"
    echo "Pressione Ctrl+C para parar o monitoramento"
    echo ""
    
    sleep 5
done

