#!/bin/bash
#
# vLLM Server Test Script
# =======================
# Testa servidor vLLM após inicialização
#
# USO:
#   ./test_vllm.sh [URL]  # URL padrão: http://localhost:8001

set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# URL do servidor
VLLM_URL="${1:-http://localhost:8001}"

info()    { echo -e "${BLUE}[TEST]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }

info "════════════════════════════════════════════════════════════════════"
info "vLLM Server Test - $VLLM_URL"
info "════════════════════════════════════════════════════════════════════"
echo ""

# ============================================================================
# TEST 1: Verificar se servidor está respondendo
# ============================================================================

info "[1/4] Verificando se servidor está respondendo..."

if curl -s -f "$VLLM_URL/health" > /dev/null 2>&1; then
    success "Servidor está respondendo"
elif curl -s -f "$VLLM_URL/v1/models" > /dev/null 2>&1; then
    success "Servidor está respondendo (endpoint /v1/models)"
else
    error "Servidor não está respondendo em $VLLM_URL"
    echo ""
    echo "Verifique:"
    echo "  1. Servidor está rodando? (tmux attach -t vllm)"
    echo "  2. URL está correta? (atual: $VLLM_URL)"
    echo "  3. Firewall permite conexão?"
    exit 1
fi

# ============================================================================
# TEST 2: Listar modelos disponíveis
# ============================================================================

info "[2/4] Listando modelos disponíveis..."

MODELS_RESPONSE=$(curl -s "$VLLM_URL/v1/models")

if [ $? -eq 0 ] && echo "$MODELS_RESPONSE" | grep -q "data"; then
    success "Modelos listados com sucesso"
    echo ""
    echo "$MODELS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$MODELS_RESPONSE"
else
    error "Falha ao listar modelos"
    echo "Resposta: $MODELS_RESPONSE"
    exit 1
fi

echo ""

# ============================================================================
# TEST 3: Testar completions endpoint
# ============================================================================

info "[3/4] Testando completions endpoint..."

# Detectar modelo disponível automaticamente
DETECTED_MODEL=$(echo "$MODELS_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data'][0]['id'] if data.get('data') else '')" 2>/dev/null || echo "")

if [ -z "$DETECTED_MODEL" ]; then
    # Fallback: tentar extrair do JSON manualmente
    DETECTED_MODEL=$(echo "$MODELS_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$DETECTED_MODEL" ]; then
    warn "Não foi possível detectar modelo, usando padrão"
    DETECTED_MODEL="qwen-32b-gptq"
else
    info "Modelo detectado: $DETECTED_MODEL"
fi

COMPLETION_RESPONSE=$(curl -s -X POST "$VLLM_URL/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$DETECTED_MODEL\",
    \"prompt\": \"Explain CRISPR gene editing in 50 words:\",
    \"max_tokens\": 100,
    \"temperature\": 0.7
  }")

if [ $? -eq 0 ] && echo "$COMPLETION_RESPONSE" | grep -q "choices"; then
    success "Completions funcionando"
    echo ""
    echo "Resposta:"
    echo "$COMPLETION_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$COMPLETION_RESPONSE"
else
    error "Falha no completions"
    echo "Resposta: $COMPLETION_RESPONSE"
    exit 1
fi

echo ""

# ============================================================================
# TEST 4: Testar chat completions (se suportado)
# ============================================================================

info "[4/4] Testando chat completions..."

CHAT_RESPONSE=$(curl -s -X POST "$VLLM_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$DETECTED_MODEL\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is pharmacokinetics? Answer in one sentence.\"}
    ],
    \"max_tokens\": 50,
    \"temperature\": 0.7
  }")

if [ $? -eq 0 ] && echo "$CHAT_RESPONSE" | grep -q "choices"; then
    success "Chat completions funcionando"
    echo ""
    echo "Resposta:"
    echo "$CHAT_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$CHAT_RESPONSE"
else
    warn "Chat completions pode não estar disponível (isso é OK)"
    echo "Resposta: $CHAT_RESPONSE"
fi

echo ""

# ============================================================================
# RESUMO
# ============================================================================

info "════════════════════════════════════════════════════════════════════"
success "TODOS OS TESTES PASSARAM!"
info "════════════════════════════════════════════════════════════════════"
echo ""
info "Servidor vLLM está funcionando corretamente em:"
echo "   ${GREEN}$VLLM_URL${NC}"
echo ""
info "Para usar de outro host, obtenha o IP:"
echo "   ${YELLOW}ip addr show | grep 'inet '${NC}"
echo ""

success "Teste concluído!"

