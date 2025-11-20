#!/bin/bash
# Monitora o stress test em tempo real com formatação bonita

LOG_FILE="stress_test_output.log"

echo "═══════════════════════════════════════════════════════════════"
echo "  BEAGLE STRESS TEST — MONITORAMENTO EM TEMPO REAL"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Pressione Ctrl+C para parar"
echo ""

# Função para mostrar estatísticas
show_stats() {
    if [ -f "$LOG_FILE" ]; then
        TOTAL=$(grep -c "CICLO #" "$LOG_FILE" 2>/dev/null || echo "0")
        COMPLETE=$(grep -c "CICLO.*COMPLETO" "$LOG_FILE" 2>/dev/null || echo "0")
        PROGRESS=$(grep "Progresso:" "$LOG_FILE" | tail -1 | grep -oE "[0-9]+/[0-9]+" || echo "0/0")
        SUCCESS_RATE=$(grep "Progresso:" "$LOG_FILE" | tail -1 | grep -oE "[0-9]+\.[0-9]+%" || echo "0.0%")
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📊 Estatísticas Atuais:"
        echo "   Ciclos iniciados: $TOTAL"
        echo "   Ciclos completos: $COMPLETE"
        echo "   Progresso: $PROGRESS"
        echo "   Taxa de sucesso: $SUCCESS_RATE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi
}

# Mostra estatísticas iniciais
show_stats

# Monitora em tempo real
tail -f "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
    # Filtra apenas linhas relevantes
    if echo "$line" | grep -qE "(CICLO|Progresso|✅|❌|Grok.*response|RESULTADO|Taxa)"; then
        # Extrai timestamp se existir
        if echo "$line" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T"; then
            TIMESTAMP=$(echo "$line" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1)
            MESSAGE=$(echo "$line" | sed 's/^[^:]*://' | sed 's/^[[:space:]]*//')
            echo "[$TIMESTAMP] $MESSAGE"
        else
            echo "$line"
        fi
        
        # Atualiza estatísticas a cada progresso
        if echo "$line" | grep -q "Progresso:"; then
            echo ""
            show_stats
            echo ""
        fi
    fi
done

