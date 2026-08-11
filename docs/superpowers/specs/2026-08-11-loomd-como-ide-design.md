# loomd como autoridade de IDE

**Data:** 11-ago-2026
**Repo:** `beagle`, branch `reconcile/unify-beagle`
**Crate:** `crates/loomd`
**Antecessora:** [Lane ACP](2026-08-10-lane-acp-design.md) — entregue, 89 testes, em produção.

## O problema

As 3 lanes Claude que o operador usa todo dia rodam em TUI no tmux. Depois da fatia anterior, o
loomd **observa** o que elas fazem (transcript → `confidence: exact`, 3.298 eventos). Mas ele não
**serve** nada a elas: não há diff no Mission Control vindo dessas lanes, não há diagnóstico, e o
agente não tem como pedir coisa alguma.

O caminho para dirigir uma lane por protocolo existe (ACP, `claude-4`) e custou caro: adaptador
Node, credencial própria, e um dia perdido atrás de OAuth expirado. Para as lanes que **já estão
trabalhando**, dirigir não é o que falta — falta **servir**.

## A descoberta

A extensão oficial `anthropic.claude-code-2.1.225-linux-x64` **já está instalada** no
openvscode-server do workspace, e ela implementa o lado IDE do protocolo. O contrato é trivial:

```json
// $HOME/.claude/ide/<porta>.lock   (modo 0600)
{ "pid": 321, "workspaceFolders": [], "ideName": "OpenVSCode Server",
  "transport": "ws", "runningInWindows": false, "authToken": "<36 chars, formato UUID>" }

// o que o loomd escreve, por lane:
// { "pid": <do loomd>, "workspaceFolders": ["/workspace/.wt/claude-1"],
//   "ideName": "Sounio Mission Control", "transport": "ws",
//   "runningInWindows": false, "authToken": "<token DESTA lane>" }
```

Quem escreve o lock é **servidor**; o `claude` lê, conecta por WebSocket em `127.0.0.1:<porta>` e
autentica no cabeçalho `x-claude-code-ide-authorization`. O servidor oferece oito métodos:
`openDiff`, `getDiagnostics`, `getOpenEditors`, `getCurrentSelection`, `openFile`, `saveDocument`,
`close_tab`, `executeCode`.

**Qualquer coisa que escreva esse lock e sirva esses métodos é uma IDE aos olhos do agente.**

### 🎯 O núcleo essencial, medido comparando duas implementações independentes

O operador **usa** o plugin oficial do Claude Code para JetBrains (`claude-code-jetbrains-plugin
0.1.14-beta`, em CLion 2025.3). Comparar as duas implementações do mesmo protocolo separa o que é
**exigido** do que é acidente de quem tinha um editor rico à mão:

| | VS Code `2.1.225` (7,4 MB) | JetBrains `0.1.14-beta` (282 KB) |
|---|---|---|
| `.claude/ide` + `authToken` | sim | **sim** |
| `openDiff` | sim | **sim** |
| `getDiagnostics` | sim | **sim** |
| `getWorkspaceFolders` | sim | **sim** |
| `openFile` | sim | **sim** |
| `close_tab` | sim | **sim** |
| `getCurrentSelection` / `getLatestSelection` | sim | não |
| `checkDocumentDirty` / `saveDocument` | sim | não |
| `closeAllDiffTabs` | sim | não |
| `executeCode` | sim | **não** |

**Cinco métodos bastam.** O `claude` funciona com o plugin do JetBrains — o operador confirmou que
usou —, e aquele plugin serve apenas o núcleo. Os outros sete são opcionais, e são exatamente
aqueles que o loomd só poderia responder vazio, por não haver editor nem cursor humano.

Segundo dado embutido na comparação: **servir o protocolo é pequeno**. 282 KB fazem o núcleo; os
7,4 MB do VS Code são chat, UI e produto.

**Enquadramento e nomes, lidos do bundle:** é **MCP sobre WebSocket** — os métodos são *tools*
registradas (`.tool("openDiff", "Open a git diff for the file", {old_file_path: …})`), invocadas por
`tools/call`, com `tools/list` para descoberta. Os argumentos são **`snake_case`**
(`old_file_path`, `new_file_path`, `new_file_contents`) — deduzir camelCase produziria um servidor
que não funciona.

Dois fatos medidos que motivam a fatia:

- `$HOME/.claude/ide/56908.lock` existe desde 07-ago e **ninguém escuta naquela porta** — lock
  órfão. Um agente que confia nele espera um servidor morto.
- **`.agents/claude-{1,2,3}/.claude/ide/` estão VAZIOS.** Cada lane tem HOME próprio, e a extensão
  anunciou apenas no HOME compartilhado. As 3 lanes **nunca viram IDE nenhuma**.

## A tese (consulta ao Fable)

Uma IDE pessoal não supera as comerciais no jogo delas; joga um jogo que elas estão
estruturalmente proibidas de jogar. Das quatro frentes que a consulta identificou, esta fatia
planta a fundação de uma e abre caminho para as outras:

1. **Ser cúmplice do compilador** — o dono da IDE é dono do `souc`. ← *esta fatia começa aqui*
2. Computação especulativa (GPU ociosa a 0,08 ms) — fatia futura, sobre este canal.
3. Trama tipada em `Knowledge[T]` + GUM — fatia futura.
4. N agentes como cidadãos de primeira classe — o loomd já é isso.

O que **não** se constrói: editor de texto, LSP genérico, autocomplete, temas, extensões.
*"Não compita em teclado; compita em verdade."*

## §1 Arquitetura

**Um servidor, um lock por lane.** Módulo novo `src/ide.rs`. Ele **não conhece a tabela de
tradução do ACP** — publica na trama pelos mesmos `AgentEvent`. A costura é a trama, como já é
para `acp.rs` e `transcript.rs`.

```
loomd ──escreve──▶ .agents/claude-1/.claude/ide/<porta>.lock   (token A)
                   .agents/claude-2/.claude/ide/<porta>.lock   (token B)
                   .agents/claude-3/.claude/ide/<porta>.lock   (token C)
                            │
   claude (tmux) lê o lock e conecta ──▶ WS 127.0.0.1:<porta>
                            │
                   openDiff · getDiagnostics · …  ──▶ trama
```

**Papéis opostos no mesmo processo, de propósito:** o loomd é **cliente ACP** para `claude-4` e
**servidor de IDE** para as lanes TUI. Dirigir e servir são coisas diferentes, e o operador quer
as duas.

**`ideName: "Sounio Mission Control"`.** Não me passo por OpenVSCode Server. Quando o agente
perguntar quem é a IDE (`/ide`), a resposta é honesta — e é o nome que ele mostra.

**`workspaceFolders` leva a worktree da lane**, não vazio. A extensão escreveu `[]` porque não tinha
pasta aberta; o loomd sabe exatamente qual árvore é de quem, e dizer isso ao agente é informação de
graça — é o mesmo dado que `getOpenEditors` e o confinamento de caminho usam.

**Lock órfão: o loomd cuida só do que é dele.** Ao subir, ele limpa locks **nos diretórios por lane
que ele gerencia** (`.agents/<lane>/.claude/ide/`), verificando o `pid` do arquivo contra processos
vivos. Ao morrer, o lock fica — e é o `pid` que permite ao próximo saber que é lixo.

⚠️ **O lock de 07-ago no HOME compartilhado NÃO é tocado.** Ele foi escrito pela extensão do
openvscode-server, não pelo loomd. Apagar lock de outro servidor seria arriscar derrubar uma IDE
viva de alguém — o `pid` morto de hoje pode ser um `pid` vivo amanhã. Aquele lock entra nesta fatia
como **fixture do teste** de detecção de órfão, e como a evidência de que órfãos acontecem. Nada
mais.

## §2 Os oito métodos

**O escopo é o núcleo de cinco.** Não doze com sete respostas vazias.

| método (tool MCP) | argumentos | resposta do loomd |
|---|---|---|
| **`getDiagnostics`** | `uri`, `tab_name` | **verdade do compilador**: `souc` + gates — §3, é o coração |
| **`openDiff`** | `old_file_path`, `new_file_path`, `new_file_contents` | aceita e publica `DiffProposed` na trama |
| **`getWorkspaceFolders`** | — | a worktree **daquela** lane; é a fonte do confinamento do §4 |
| **`openFile`** | `path`, `preview` | registra a intenção na trama; **não age** |
| **`close_tab`** | `tab_name` | aceito, registrado, ignorado |

**Os sete de fora, e o motivo agora é medido, não opinião:** `getCurrentSelection`,
`getLatestSelection`, `checkDocumentDirty`, `saveDocument`, `closeAllDiffTabs`, `getOpenEditors` e
`executeCode` **não são servidos pelo plugin oficial do JetBrains** — e o `claude` funciona com ele.
Logo não são exigidos pelo protocolo. `tools/list` anuncia só o que existe, e o agente se adapta ao
que foi anunciado.

Duas decisões declaradas:

- **`openFile` registra sem agir.** A operação de *protocolo* funcionou; a trama registra que o
  agente **pediu**, nunca que foi feito. "Ok" para ação que não aconteceu é a UI mentirosa que esta
  linhagem de fatias tem como inimiga declarada.
- **`executeCode` ausente, não stub** — e o argumento ficou mais forte que "é perigoso": **nem o
  plugin oficial do JetBrains o serve**. Servido pelo loomd, executaria no cluster. Fatia própria,
  atrás de aprovação explícita, como patch e comando já ficam.

**Não anunciar é melhor que responder vazio.** Um `getCurrentSelection` que devolve nada faz o
agente gastar um turno perguntando; um `tools/list` que não o anuncia faz o agente nem tentar.

## §3 `getDiagnostics` como autoridade

```
getDiagnostics(uri) → souc check <arquivo>  (+ gates de stdlib quando o alvo é stdlib)
                    → Diagnostic{ severity, range, message, source: "souc" }
```

Nenhuma ferramenta comercial faria isso para uma linguagem de um usuário — custo marginal infinito
para elas, um binário que já existe para ele.

### 🚨 O pré-requisito: o `souc` chama erro de aviso

Registrado em memória e verdadeiro: **nome inexistente produz `warning` e `xor eax,eax`**, e o
`make build` trunca a saída em 1 MiB. Repassar isso faria a IDE responder **"limpo" sobre código
que não roda** — e com autoridade maior que um aviso de terminal, porque o agente confia nesta
resposta.

A camada de IDE **promove** classes conhecidas de aviso para `Error`, sem esperar o compilador
mudar:

```rust
/// 🚨 O `souc` chama de `warning` o que é erro semântico. Repassar faria a IDE afirmar "limpo"
/// sobre código que não roda — e o agente confia nesta resposta mais do que num aviso de terminal.
pub fn promover_severidade(bruto: &DiagnosticoBruto) -> Severidade
```

### Silêncio ≠ limpo

Se o `souc` não pôde rodar — binário ausente, timeout, saída truncada — a resposta **não** é lista
vazia. É um diagnóstico dizendo **"não consegui verificar"**. Lista vazia significa "verifiquei e
está bom"; um agente que a recebe segue construindo sobre areia.

### Latência

`souc check` não é instantâneo e o agente espera. **Cache por `mtime`**, e nada além nesta fatia. A
computação especulativa no cluster é fatia futura, sobre este canal.

## §4 Segurança

**Um token por lane, não um por servidor.** Consequência arquitetural, não detalhe: com tokens
distintos, o servidor **sabe qual lane conectou** — sem isso as três seriam indistinguíveis, e não
haveria como atribuir o `openDiff` à lane certa na trama nem confinar caminho.

**Confinamento de caminho**, e a fonte é o próprio protocolo: `getWorkspaceFolders` já diz ao
agente qual é a árvore dele. Cada lane tem sua worktree (`/workspace/.wt/<lane>`). Requisição sobre
caminho fora dela é **recusada e registrada na trama** — nunca ignorada em silêncio. Uma lane
olhando a árvore de outra é o hazard que a Frota existe para avisar; aqui eu o criaria de dentro.

O resto copia o que a extensão já faz: escutar **só em `127.0.0.1`**, lock em **0600**, token no
cabeçalho `x-claude-code-ide-authorization`, e `executeCode` **ausente**.

## §5 Testes

Funções puras, onde mora a decisão:

| função | o que prende |
|---|---|
| `conteudo_do_lock(porta, token, lane)` | `ideName: "Sounio Mission Control"`, `transport: "ws"`, `pid` real |
| `lock_e_orfao(lock, pids_vivos)` | o lock de 07-ago (pid 321 morto) **é** órfão; pid vivo **não** é |
| `promover_severidade(bruto)` | aviso de nome inexistente **vira `Error`** |
| `caminho_permitido(lane, path)` | caminho fora da worktree é recusado |
| `diagnostico_de_falha(motivo)` | `souc` inacessível produz diagnóstico, **nunca lista vazia** |

**Mutações obrigatórias**, e o vermelho tem de vir de **asserção** — vermelho por erro de
compilação prova que o compilador cobra algo, não que o teste pega o defeito:

1. `promover_severidade` devolvendo o valor bruto → vermelho
2. `caminho_permitido` sempre `true` → vermelho
3. `souc` indisponível devolvendo lista vazia → vermelho *(a mentira mais perigosa da fatia)*
4. Token único para todas as lanes → o teste de identificação de lane fica vermelho

**Prova ao vivo:** numa lane real do tmux, `/ide` mostra **`Sounio Mission Control`** conectado;
pedir diagnóstico de um `.sio` com nome inexistente devolve **`Error`**, não `warning`. Se o agente
aceitar o erro e corrigir, a tese está provada no menor exemplo possível: **a IDE pessoal como
autoridade epistêmica entre um agente que especula e um compilador que não mente.**

## Riscos

- **O protocolo não é publicado.** Foi lido do bundle instalado (versão 2.1.225). Uma atualização
  da CLI pode mudar o contrato sem aviso. Mitigação: a prova ao vivo é o teste de contrato, e o
  `ideName` no lock deixa rastro de quem serviu.
- **Promover severidade é julgamento.** A lista de classes promovidas começa pequena (nome
  inexistente) e cresce com evidência. Promover errado gera falso positivo, que é melhor que falso
  negativo aqui — mas não é grátis.
- **`souc` lento degrada a experiência do agente.** Cache por `mtime` cobre o caso comum; o caso
  frio continua custando.
- **Um servidor para N lanes** é ponto único de falha para a função de IDE. Se ele cair, as lanes
  voltam ao que são hoje (sem IDE) — degradação, não quebra.

## Fora de escopo

- `executeCode` — fatia própria, atrás de aprovação.
- Computação especulativa no cluster (pré-compilar e pré-explicar a cada save).
- Trama tipada em `Knowledge[T]`/GUM.
- Transporte do ACP pelo crate `agent-client-protocol` e migração do `codex.rs` — **fatia seguinte,
  já pesquisada**: `gemini --acp` e `qwen --acp` são nativos (sem adaptador), mas nenhum está
  verificado contra ACP 2.0.0 (Qwen reportado em v1, `QwenLM/qwen-code#1502`), então compatibilidade
  se estabelece por handshake. Modelos locais (Ollama/vLLM/llama.cpp/LM Studio) não têm agente ACP
  conhecido nem adaptador genérico — **não resolvido**, não "não existe".
- Editor de texto, LSP genérico, autocomplete, temas.
