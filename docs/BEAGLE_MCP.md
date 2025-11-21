# BEAGLE MCP Server - Guia de Integração

## Visão Geral

O **BEAGLE MCP Server** expõe o BEAGLE como um **Memory & Control Plane (MCP)** para ChatGPT (custom connector) e Claude (MCP client), permitindo que esses LLMs acessem:

- **Memória persistente** (GraphRAG + embeddings)
- **Pipeline científico** (geração de papers + Triad)
- **Jobs científicos** (PBPK, Heliobiology, Scaffolds, PCS, KEC)
- **Feedback e experimentos** (continuous learning)

## Arquitetura

```
ChatGPT/Claude
    ↓ (MCP Protocol)
BEAGLE MCP Server (TypeScript/Node.js)
    ↓ (HTTP)
BEAGLE Core (Rust/Axum @ localhost:8080)
    ↓
Pipeline, Triad, Memory, Jobs, etc.
```

## Instalação

```bash
cd beagle-mcp-server
npm install
npm run build
```

## Configuração

1. Copie `.env.example` para `.env`:

```bash
cp .env.example .env
```

2. Configure as variáveis:

```bash
# BEAGLE Core HTTP endpoint
BEAGLE_CORE_URL=http://localhost:8080

# MCP Server Auth (recomendado para produção)
MCP_AUTH_TOKEN=your-secret-token-here
MCP_ENABLE_AUTH=true

# Features experimentais (off por default)
MCP_ENABLE_SERENDIPITY=false
MCP_ENABLE_VOID=false
```

## Executando

### Desenvolvimento

```bash
npm run dev
```

### Produção

```bash
npm run build
npm start
```

## Integração com ChatGPT

### 1. Habilitar Developer Mode

- ChatGPT Pro/Business/Enterprise
- Settings → Developer Mode → Enable

### 2. Criar Custom Connector

1. Acesse: Settings → Custom Connectors
2. Clique em "Create Connector"
3. Configure:

```json
{
  "name": "BEAGLE Exocortex",
  "url": "https://your-mcp-server.com",
  "auth": {
    "type": "bearer",
    "token": "your-secret-token"
  },
  "tools": [
    "beagle_query_memory",
    "beagle_run_pipeline",
    "beagle_get_run_summary",
    "beagle_list_recent_runs",
    "beagle_tag_run"
  ]
}
```

### 3. Testar

No ChatGPT, digite:

```
Use beagle_query_memory to find recent work on PBPK modeling
```

Ou:

```
Run a pipeline for: "How does HRV affect cognitive performance in scientific writing?"
```

## Integração com Claude

### 1. Configurar MCP Server

No Claude Code/Desktop, edite as configurações:

```json
{
  "mcpServers": {
    "beagle": {
      "url": "https://your-mcp-server.com",
      "auth": {
        "type": "bearer",
        "token": "your-secret-token"
      }
    }
  }
}
```

### 2. Reiniciar Claude

Reinicie o Claude Code/Desktop para carregar o MCP server.

### 3. Testar

No Claude, digite:

```
Use MCP server: BEAGLE. Query memory for recent experiments on heliobiology.
```

## Tools Disponíveis

### Pipeline & Triad

- **`beagle_run_pipeline`**: Inicia pipeline para gerar draft científico
- **`beagle_get_run_summary`**: Obtém resumo e artefatos de um run
- **`beagle_list_recent_runs`**: Lista runs recentes

### Science Jobs

- **`beagle_start_science_job`**: Inicia job científico (PBPK, Helio, Scaffold, PCS, KEC)
- **`beagle_get_science_job_status`**: Verifica status de um job
- **`beagle_get_science_job_artifacts`**: Obtém artefatos de um job

### Memory

- **`beagle_query_memory`**: Consulta memória persistente (GraphRAG)
- **`beagle_ingest_chat`**: Ingere conversa na memória

### Feedback

- **`beagle_tag_run`**: Marca run com feedback humano
- **`beagle_tag_experiment_run`**: Marca run com condição experimental

### Experimental (dev/lab only)

- **`beagle_serendipity_toggle`**: Liga/desliga Serendipity Engine
- **`beagle_serendipity_perturb_prompt`**: Perturba prompt via Serendipity
- **`beagle_void_break_loop`**: Aplica comportamento Void

## Segurança

### MCP-UPD Protection

O servidor implementa proteções contra **Unintended Privacy Disclosure**:

- **Sanitização de output**: Remove marcadores de prompt injection
- **Delimitadores de memória**: Marca explicitamente dados de memória como DADOS, não comandos
- **Validação de input**: Valida inputs para padrões perigosos

### Autenticação

- **Bearer token**: Recomendado para produção
- **OAuth**: Pode ser adicionado para cenários multi-usuário

### TLS

Para produção, execute atrás de um reverse proxy (nginx, Caddy) com TLS:

```nginx
server {
    listen 443 ssl;
    server_name your-mcp-server.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Casos de Uso

### 1. Memória Persistente

**ChatGPT/Claude**: "Use beagle_query_memory to find what we discussed about PBPK modeling last week"

**Resultado**: BEAGLE retorna contexto relevante de conversas anteriores, runs, experimentos.

### 2. Pipeline Científico

**ChatGPT/Claude**: "Run a pipeline for: 'How does heliobiology affect cognitive performance?'"

**Resultado**: BEAGLE gera draft + Triad review, retorna run_id.

### 3. Jobs Científicos

**ChatGPT/Claude**: "Start a PBPK job with these parameters: {...}"

**Resultado**: BEAGLE executa job Julia, retorna job_id.

### 4. Feedback Contínuo

**ChatGPT/Claude**: "Tag run abc123 as accepted with rating 9"

**Resultado**: BEAGLE registra feedback para continuous learning.

## Troubleshooting

### Erro: "BEAGLE API error (404)"

- Verifique se `BEAGLE_CORE_URL` está correto
- Confirme que o BEAGLE core está rodando em `localhost:8080`

### Erro: "Tool not found"

- Verifique se o tool está listado no connector config
- Confirme que o MCP server está retornando a lista correta de tools

### Erro: "Authentication failed"

- Verifique se `MCP_AUTH_TOKEN` está configurado
- Confirme que o token está sendo enviado no header `Authorization: Bearer ...`

## Desenvolvimento

### Testando com MCP Inspector

```bash
npm install -g @modelcontextprotocol/inspector
mcp-inspector --server beagle-mcp-server
```

### Logging

Logs são escritos em stdout. Configure `MCP_LOG_LEVEL`:

- `debug`: Todos os logs
- `info`: Info e acima (default)
- `warn`: Warnings e erros
- `error`: Apenas erros

## Próximos Passos

1. **OAuth**: Implementar OAuth para multi-usuário
2. **Streaming**: Suporte a streaming de respostas longas
3. **Webhooks**: Notificações quando jobs/pipelines completarem
4. **Rate Limiting**: Limites de taxa por usuário/IP

## Referências

- [MCP Specification](https://platform.openai.com/docs/mcp)
- [MCPKit (OpenAI)](https://github.com/openai/mcpkit)
- [BEAGLE Core API](../apps/beagle-monorepo/README.md)

