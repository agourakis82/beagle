#!/bin/bash
# Script para testar API key da Anthropic

set -e

echo "🔑 Testando API Key da Anthropic"
echo "=================================="
echo ""

# Carregar API key
if [ -f .env ]; then
    source .env
elif [ -f .env.dev ]; then
    source .env.dev
else
    echo "❌ Arquivo .env ou .env.dev não encontrado"
    exit 1
fi

# Limpar API key (remover quebras de linha, espaços, aspas)
export ANTHROPIC_API_KEY=$(echo "$ANTHROPIC_API_KEY" | tr -d '\n\r "' | xargs)

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ ANTHROPIC_API_KEY não encontrada"
    exit 1
fi

echo "✅ API Key carregada: ${ANTHROPIC_API_KEY:0:30}..."
echo "   Tamanho: ${#ANTHROPIC_API_KEY} caracteres"
echo ""

# Testar com curl
echo "🧪 Testando com curl..."
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 10,
    "messages": [{"role": "user", "content": "test"}]
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo "HTTP Status: $HTTP_CODE"
echo "Response: $BODY"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ API Key válida e funcionando!"
    exit 0
elif [ "$HTTP_CODE" = "401" ]; then
    echo "❌ API Key inválida ou expirada"
    echo ""
    echo "Ações sugeridas:"
    echo "1. Verificar no dashboard: https://console.anthropic.com/"
    echo "2. Verificar se a chave está ativa"
    echo "3. Gerar nova chave se necessário"
    echo "4. Verificar quota/billing"
    exit 1
else
    echo "⚠️  Status HTTP inesperado: $HTTP_CODE"
    echo "Response: $BODY"
    exit 1
fi

