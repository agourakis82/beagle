# Instalar o MCP `beagle-cognitive` no Mac

Dá ao Claude Desktop (e a qualquer outra Claude Code rodando no Mac) os mesmos 21 tools que o agent pod e o Linux host já têm: 13 cockpit + 8 cognitive, com ambient-suffix regret/adversarial/prediction em cada resposta, e caller-tag próprio pro Mac (`caller=mac-desktop`).

Pré-requisitos (o Mac já tem):
- Tailscale logado no mesmo tailnet do cluster (beagle-core / beagle-auth)
- Node 20+ (`brew install node` ou Xcode toolchain)
- Claude Desktop ou Claude Code CLI

## Passo 1 — baixar o MCP server script

Do host Linux para o Mac (via scp ou copy-paste):

```
# no Mac:
mkdir -p ~/Library/Application\ Support/Claude/mcp-servers
scp devsounio@<linux-host>:/home/devsounio/.claude/mcp-servers/cockpit-mcp-server.mjs \
    ~/Library/Application\ Support/Claude/mcp-servers/cockpit-mcp-server.mjs
```

Ou clonar o repo beagle no Mac e apontar pra `beagle/k8s/agent-pods/cockpit-mcp-server.mjs`.

## Passo 2 — Claude Desktop

Editar `~/Library/Application Support/Claude/claude_desktop_config.json` — adicionar (ou mergear):

```json
{
  "mcpServers": {
    "beagle-cognitive": {
      "command": "node",
      "args": [
        "/Users/YOUR_USER/Library/Application Support/Claude/mcp-servers/cockpit-mcp-server.mjs"
      ],
      "env": {
        "AUTH_BRIDGE_URL": "http://beagle-auth.tail21cbc4.ts.net",
        "BEAGLE_URL": "http://beagle-core.tail21cbc4.ts.net",
        "COCKPIT_API": "http://sounio-cockpit.tail21cbc4.ts.net",
        "COCKPIT_PROJECT": "mac-desktop",
        "BEAGLE_CONSUMER": "beagle-operator"
      }
    }
  }
}
```

Se o arquivo já tem `mcpServers`, adicione o entry `beagle-cognitive` dentro. Claude Desktop pede reinício pra pegar mudanças.

## Passo 3 — Claude Code CLI no Mac

```
claude mcp add --scope user beagle-cognitive \
  --env AUTH_BRIDGE_URL=http://beagle-auth.tail21cbc4.ts.net \
  --env BEAGLE_URL=http://beagle-core.tail21cbc4.ts.net \
  --env COCKPIT_API=http://sounio-cockpit.tail21cbc4.ts.net \
  --env COCKPIT_PROJECT=mac-code \
  --env BEAGLE_CONSUMER=beagle-operator \
  -- node ~/Library/Application\ Support/Claude/mcp-servers/cockpit-mcp-server.mjs
```

Mude `COCKPIT_PROJECT` entre `mac-desktop` e `mac-code` se rodar ambos — assim cada cliente gera sua própria Φ-rhythm substrate separadamente (`split=true` no `tool_rhythm_phi` vai mostrar os dois).

## Passo 4 — verificar

```
claude mcp list | grep beagle-cognitive      # → ✓ Connected

# dentro de uma sessão claude:
/mcp                                          # mostra os 21 tools
```

Ou fora da sessão:

```
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
              '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | \
  AUTH_BRIDGE_URL=http://beagle-auth.tail21cbc4.ts.net \
  BEAGLE_URL=http://beagle-core.tail21cbc4.ts.net \
  COCKPIT_PROJECT=mac-desktop \
  BEAGLE_CONSUMER=beagle-operator \
  node ~/Library/Application\ Support/Claude/mcp-servers/cockpit-mcp-server.mjs
```

Deve retornar 21 tools no id=2.

## Troubleshooting

- **tools aparecem mas toda chamada volta `error: beagle-token bridge failed`**: Tailscale não logado ou não vê `beagle-auth.tail21cbc4.ts.net`. `tailscale status | grep beagle-auth`.
- **pthread DNS crash no node**: o Mac não sofre desse bug (macOS libc ≠ glibc). Se aparecer, reinstalar Node via `brew install node@20`.
- **token 401**: o secret `beagle-core-secrets` mudou; o bridge serve token fresco. Limpar cache do MCP (não tem em disco; só em memória do processo node). Reiniciar Claude Desktop.
