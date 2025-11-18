# 🔑 Track 2 - API Key Status

## ⚠️ Problema Identificado

A API key está sendo carregada do `.env.dev`, mas ainda retorna erro 401 Unauthorized:

```
Anthropic retornou erro HTTP status=401 Unauthorized
{"error":{"message":"invalid x-api-key","type":"authentication_error"}}
```

## 📊 Verificação

- ✅ Arquivo `.env.dev` existe e é carregado
- ✅ Variável `ANTHROPIC_API_KEY` está configurada (108 caracteres)
- ✅ Formato parece correto: `sk-ant-api03-...`
- ❌ API retorna 401 (autenticação falhou)

## 🔍 Possíveis Causas

1. **API Key Expirada ou Revogada**
   - A chave no `.env.dev` pode ter expirado
   - Verificar no dashboard da Anthropic

2. **API Key Incorreta**
   - Verificar se a chave no `.env.dev` está correta
   - Comparar com a chave no dashboard

3. **Problema de Formatação**
   - Espaços extras ou quebras de linha
   - Aspas desnecessárias

4. **Limite de Rate ou Quota**
   - Verificar se há limite de requisições atingido
   - Verificar billing/quota no dashboard

## ✅ Solução

### 1. Verificar API Key no Dashboard Anthropic
- Acessar: https://console.anthropic.com/
- Verificar se a chave está ativa
- Gerar nova chave se necessário

### 2. Atualizar .env.dev
```bash
# Editar .env.dev
ANTHROPIC_API_KEY=sk-ant-api03-nova-chave-aqui
```

### 3. Testar API Key Diretamente
```bash
source .env.dev
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"test"}]}'
```

### 4. Executar Testes Novamente
```bash
source .env.dev
export PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH"
export OPENSSL_DIR=/usr
export OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH="$HOME/miniforge/lib:$LD_LIBRARY_PATH"
export SQLX_OFFLINE=true

cargo test --package beagle-hermes --test multi_agent_e2e test_athena_paper_search -- --ignored --nocapture
```

## 📝 Status Atual

- **Testes Unitários:** ✅ 2/2 passando (sem API key)
- **Testes com API:** ❌ 0/2 passando (API key inválida)
- **Próximo Passo:** Verificar/atualizar API key no `.env.dev`

## 🔗 Referências

- Anthropic API Docs: https://docs.anthropic.com/
- Dashboard: https://console.anthropic.com/

