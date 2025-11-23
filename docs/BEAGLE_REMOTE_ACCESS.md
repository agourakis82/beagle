# BEAGLE Remote Access via Cloudflare Tunnel

Este documento descreve como expor o BEAGLE core e MCP server de forma segura via Cloudflare Tunnel, permitindo acesso remoto HTTPS sem expor portas diretamente.

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                      Cloudflare Edge                            │
│  https://beagle-core.yourdomain.com                            │
│  https://beagle-mcp.yourdomain.com                             │
└────────────────────────┬────────────────────────────────────────┘
                         │ Cloudflare Tunnel
                         │ (encrypted, authenticated)
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Local Machine (127.0.0.1)                    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ BEAGLE Core (Rust/Axum)                                  │  │
│  │ - Listens on: 127.0.0.1:8080                            │  │
│  │ - Auth: Bearer token (BEAGLE_API_TOKEN)                 │  │
│  │ - Public route: /health (no auth)                       │  │
│  │ - Protected routes: /api/* (requires auth)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ BEAGLE MCP Server (Node/TypeScript)                      │  │
│  │ - Listens on: stdio (Claude Desktop)                    │  │
│  │ - Or: 127.0.0.1:4000 (HTTP mode)                        │  │
│  │ - Calls BEAGLE Core with Bearer token                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Princípios de Segurança

1. **BEAGLE Core nunca escuta em 0.0.0.0** - sempre em `127.0.0.1:8080`
2. **Autenticação obrigatória** - todos os endpoints `/api/*` requerem `Authorization: Bearer <token>`
3. **Cloudflare Tunnel** - tráfego criptografado e autenticado do edge até o localhost
4. **Opcional**: Cloudflare Access pode adicionar camada extra de autenticação (OAuth, email OTP, etc.)

## Setup do BEAGLE Core

### 1. Configuração de Ambiente

Crie ou edite `.env` (ou export via shell):

```bash
# Profile (dev, lab, prod)
BEAGLE_PROFILE=prod

# API Token - OBRIGATÓRIO em prod
BEAGLE_API_TOKEN=your-super-secret-token-here-min-32-chars

# BEAGLE Core bind address (sempre localhost para segurança)
BEAGLE_CORE_ADDR=127.0.0.1:8080

# Safe mode (true = evita publicações automáticas)
BEAGLE_SAFE_MODE=true

# Data directory
BEAGLE_DATA_DIR=/home/user/beagle-data

# LLM API keys (opcional)
XAI_API_KEY=xai-...
ANTHROPIC_API_KEY=sk-ant-...
```

### 2. Inicie o BEAGLE Core

```bash
cd beagle-remote/apps/beagle-monorepo
cargo run --bin core_server --release
```

Verifique que está rodando:

```bash
curl http://127.0.0.1:8080/health
# Resposta: {"status":"ok","service":"beagle-core","profile":"prod",...}
```

Teste autenticação:

```bash
# Sem token → 401 Unauthorized
curl -X POST http://127.0.0.1:8080/api/pipeline/start \
  -H "Content-Type: application/json" \
  -d '{"question":"test"}'

# Com token → 200 OK
curl -X POST http://127.0.0.1:8080/api/pipeline/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-super-secret-token-here-min-32-chars" \
  -d '{"question":"test"}'
```

## Setup do MCP Server

### 1. Configuração de Ambiente

Edite `beagle-mcp-server/.env`:

```bash
# BEAGLE Core URL (sempre localhost, mesmo com Cloudflare Tunnel)
BEAGLE_CORE_URL=http://127.0.0.1:8080

# API Token (deve coincidir com BEAGLE_API_TOKEN do core)
BEAGLE_CORE_API_TOKEN=your-super-secret-token-here-min-32-chars
```

### 2. Inicie o MCP Server

```bash
cd beagle-remote/beagle-mcp-server
npm run build
npm start
```

## Setup do Cloudflare Tunnel

### 1. Instalação do `cloudflared`

```bash
# Linux (via apt)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb

# macOS (via Homebrew)
brew install cloudflare/cloudflare/cloudflared

# Windows
# Download do instalador: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/
```

### 2. Autenticação

```bash
cloudflared tunnel login
```

Isso abre o navegador para autenticar com sua conta Cloudflare e selecionar o domínio.

### 3. Criação do Tunnel

```bash
cloudflared tunnel create beagle-tunnel
```

Isso gera:
- Um UUID único para o tunnel (ex: `abc123-def456-...`)
- Arquivo de credenciais: `~/.cloudflared/abc123-def456-....json`

### 4. Configuração do Tunnel

Crie `~/.cloudflared/config.yml`:

```yaml
tunnel: abc123-def456-ghi789  # UUID do seu tunnel
credentials-file: /home/user/.cloudflared/abc123-def456-ghi789.json

ingress:
  # BEAGLE Core - HTTP API
  - hostname: beagle-core.yourdomain.com
    service: http://127.0.0.1:8080
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s

  # BEAGLE MCP Server (se rodando em modo HTTP)
  - hostname: beagle-mcp.yourdomain.com
    service: http://127.0.0.1:4000
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s

  # Fallback - retorna 404
  - service: http_status:404
```

### 5. Criação de DNS Records

Para cada hostname, crie um CNAME no Cloudflare DNS:

```bash
cloudflared tunnel route dns beagle-tunnel beagle-core.yourdomain.com
cloudflared tunnel route dns beagle-tunnel beagle-mcp.yourdomain.com
```

Ou manualmente no Cloudflare Dashboard:
- Type: `CNAME`
- Name: `beagle-core` (ou `beagle-mcp`)
- Target: `abc123-def456-ghi789.cfargotunnel.com`
- Proxy: ✅ **Proxied** (orange cloud)

### 6. Inicie o Tunnel

```bash
cloudflared tunnel run beagle-tunnel
```

Ou como serviço (systemd):

```bash
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

### 7. Teste Remoto

```bash
# Health check (público, sem auth)
curl https://beagle-core.yourdomain.com/health

# API call (requer auth)
curl -X POST https://beagle-core.yourdomain.com/api/pipeline/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-super-secret-token-here-min-32-chars" \
  -d '{"question":"What is quantum entanglement?"}'
```

## Segurança Adicional: Cloudflare Access (Opcional)

Para adicionar autenticação adicional **antes** de chegar ao BEAGLE:

### 1. Habilite Cloudflare Access

No Cloudflare Dashboard:
1. Vá para **Zero Trust** → **Access** → **Applications**
2. **Add an application** → **Self-hosted**
3. Configure:
   - **Application name**: BEAGLE Core API
   - **Session duration**: 24 hours
   - **Application domain**: `beagle-core.yourdomain.com`

### 2. Crie Policy de Acesso

Opções:
- **Email domains**: `@yourdomain.com`
- **One-time PIN**: via email
- **OAuth**: Google, GitHub, etc.
- **IP ranges**: whitelist específico

### 3. Resultado

Agora, para acessar `https://beagle-core.yourdomain.com/api/*`, o usuário precisa:
1. Passar pela autenticação do Cloudflare Access (OAuth, email PIN, etc.)
2. **E** fornecer o Bearer token correto (`BEAGLE_API_TOKEN`)

**Defesa em profundidade**: duas camadas de autenticação.

## Monitoring e Logs

### BEAGLE Core Logs

```bash
# Via systemd (se rodando como serviço)
journalctl -u beagle-core -f

# Ou diretamente
tail -f ~/beagle-data/logs/beagle-pipeline/*.log
```

### Cloudflare Tunnel Logs

```bash
# Via systemd
journalctl -u cloudflared -f

# Ou rodando em foreground
cloudflared tunnel run beagle-tunnel
```

### Cloudflare Analytics

No Cloudflare Dashboard:
- **Analytics & Logs** → **Web Analytics**: tráfego, requests, bandwidth
- **Zero Trust** → **Access** → **Audit Logs**: autenticações, tentativas de acesso

## Troubleshooting

### Erro 401 Unauthorized

**Sintoma**: `{"error":"unauthorized","reason":"invalid or missing API token"}`

**Solução**:
1. Verifique que `BEAGLE_API_TOKEN` está configurado no BEAGLE Core
2. Verifique que `BEAGLE_CORE_API_TOKEN` está configurado no MCP e coincide com o token do core
3. Verifique que o header `Authorization: Bearer <token>` está sendo enviado corretamente

### Tunnel não conecta

**Sintoma**: `cloudflared` mostra `ERR  error="no connections active"`

**Solução**:
1. Verifique que o `tunnel UUID` em `config.yml` está correto
2. Verifique que o arquivo `credentials-file` existe e é válido
3. Teste conectividade: `cloudflared tunnel info beagle-tunnel`

### BEAGLE Core não responde

**Sintoma**: `502 Bad Gateway` via Cloudflare Tunnel

**Solução**:
1. Verifique que o BEAGLE Core está rodando: `curl http://127.0.0.1:8080/health`
2. Verifique que a porta `8080` está correta no `config.yml`
3. Verifique logs do BEAGLE Core para erros de bind/startup

## Cenários de Uso

### 1. Desenvolvimento Local

```bash
# Sem Cloudflare Tunnel
BEAGLE_PROFILE=dev
BEAGLE_API_TOKEN=  # Opcional
BEAGLE_CORE_ADDR=127.0.0.1:8080
```

Acesso apenas local via `http://127.0.0.1:8080`.

### 2. Lab/Testing Remoto

```bash
# Com Cloudflare Tunnel, sem Cloudflare Access
BEAGLE_PROFILE=lab
BEAGLE_API_TOKEN=lab-token-change-me
BEAGLE_CORE_ADDR=127.0.0.1:8080
```

Acesso remoto via `https://beagle-core.yourdomain.com` com Bearer token.

### 3. Produção

```bash
# Com Cloudflare Tunnel + Cloudflare Access
BEAGLE_PROFILE=prod
BEAGLE_API_TOKEN=prod-super-secret-min-64-chars-recommended
BEAGLE_CORE_ADDR=127.0.0.1:8080
BEAGLE_SAFE_MODE=true
```

Acesso remoto via `https://beagle-core.yourdomain.com`:
1. Autenticação via Cloudflare Access (OAuth/email)
2. **E** Bearer token

## Referências

- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Access Docs](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [BEAGLE Config Docs](../crates/beagle-config/README.md)
- [MCP Server Docs](../beagle-mcp-server/README.md)
