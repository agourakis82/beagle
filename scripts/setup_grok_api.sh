#!/bin/bash
# Configura a API key do Grok para o BEAGLE
# 
# USO:
#   export XAI_API_KEY="sua-api-key-aqui"
#   source scripts/setup_grok_api.sh
#
# Ou adicione ao seu ~/.bashrc ou ~/.zshrc:
#   export XAI_API_KEY="sua-api-key-aqui"

if [ -z "$XAI_API_KEY" ]; then
    echo "⚠️  XAI_API_KEY não configurada"
    echo ""
    echo "Para configurar, execute:"
    echo "  export XAI_API_KEY=\"sua-api-key-aqui\""
    echo ""
    echo "Ou adicione ao seu ~/.bashrc ou ~/.zshrc:"
    echo "  export XAI_API_KEY=\"sua-api-key-aqui\""
    echo ""
    exit 1
fi

echo "✅ XAI_API_KEY configurada"
echo ""

