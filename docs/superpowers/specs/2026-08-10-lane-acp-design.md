# Lane ACP — dirigir um Claude por protocolo aberto

**Data:** 10-ago-2026
**Repo:** `beagle`, branch `reconcile/unify-beagle`
**Crate:** `crates/loomd`
**Antecessor:** [Sessão de protocolo na lane](2026-07-20-agent-multiplexer-design.md) — entregue e provada com o
`codex app-server`. Esta é a fatia seguinte: o mesmo nível de supervisão para um Claude.

## O problema

O Loom supervisiona duas classes de lane, e a diferença entre elas é grande:

| | como o loomd sabe o que está acontecendo | `confidence` |
|---|---|---|
| `codex-4` | protocolo (`codex app-server`, JSON-RPC) | `exact` |
| `claude-1`, `claude-2`, `claude-3` | raspando a tela do tmux | `inferred` |

Raspar tela é o que este projeto passou meses provando ser insuficiente: título OSC, heurística de
prompt, e nenhuma noção de diff, aprovação ou custo. As três lanes Claude estão vivas e trabalhando
(2720, 2453 e 639 linhas de conversa hoje) e o loomd praticamente não sabe o que elas fazem.

## A descoberta que definiu o desenho

A primeira versão deste desenho ia escrever um `claude.rs` à mão contra
`claude --print --input-format stream-json`, espelhando o `codex.rs`. Isso foi abandonado quando o
operador apontou o Zed: **o Zed não fala `stream-json`. Ele fala ACP** — Agent Client Protocol, um
protocolo aberto de JSON-RPC feito para "editor dirige agente", cujo SDK de referência é um crate
Rust (`agent-client-protocol` 2.0.0, 3,5M downloads).

Medido, não suposto:

- adaptador: **`@agentclientprotocol/claude-agent-acp` 0.66.0**. O pacote com marca Zed
  (`@zed-industries/claude-code-acp` 0.16.2) está **deprecado** — renomeado.
- a pilha é ACP → `@anthropic-ai/claude-agent-sdk` → CLI. O `stream-json` também é Node; a diferença
  é só se o Node fala protocolo aberto ou dialeto privado.
- enquadramento: **ND-JSON** (uma linha por mensagem), não framing LSP.
- exige Node ≥ 22. **Rodou em v20.19.2** no censo — fora de suporte, funcionando. Registrado como
  risco, não como impedimento.

**O que decide a favor do ACP não é elegância, é aritmética.** ACP é uma tradução para N agentes:
Codex e Gemini têm adaptador ACP. Hoje há um `codex.rs` artesanal; um `claude.rs` artesanal seria o
segundo, e o terceiro viria em um mês. Com ACP, a lane nova custa configuração, não código novo.

E a tabela de tradução vem **declarada**: 13 variantes de `session/update` num schema de 262
definições. O `codex.rs` foi derivado de um censo cru e ainda carrega a armadilha dos IDs
não-uniformes (`thread.id` aninhado vs `threadId` plano). Aqui o schema é o contrato.

## O censo

Cliente ND-JSON escrito à mão de propósito — o SDK esconderia justamente o que se queria medir.
Tarefa real (ler, escrever, rodar shell) num repo git de rascunho, com a credencial do operador.

| rodada 1 (modo padrão) | | rodada 2 (`set_mode: default`) | |
|---|---|---|---|
| `agent_message_chunk` | 11 | `tool_call_update` | 28 |
| `tool_call_update` | 11 | `usage_update` | 16 |
| `usage_update` | 10 | `agent_message_chunk` | 14 |
| `tool_call` | 3 | `tool_call` | 7 |
| `available_commands_update` | 1 | **`session/request_permission`** | **3** |
| | | `config_option_update` | 1 |
| **42 linhas no fio** | | **70 do agente** | |

### 🚨 O achado que justifica ter medido

**O adaptador nasce em `bypassPermissions`.** `session/new` devolveu
`currentModeId: "bypassPermissions"`, e na rodada 1 o `session/request_permission` **não disparou uma
única vez**. O próprio SDK avisa no stderr:

```
[CLAUDE_SDK_CAN_USE_TOOL_SHADOWED] canUseTool will not be invoked:
permissionMode 'bypassPermissions' auto-approves every tool call
```

É o análogo exato do achado do censo do codex (70 de 107 eventos eram delta descartada): **um padrão
que apaga silenciosamente uma classe inteira de eventos.** Escrito por dedução, a tela de aprovação
teria ficado sem fonte e a conclusão seria "ACP não emite permissão".

Também importa para a política: o padrão do adaptador é **mais permissivo** que o `auto` que as lanes
já usam (`settings.json` → `permissions.defaultMode: "auto"`).

### O que o protocolo entrega pronto

- **O diff, já computado**, no pedido de permissão:
  `{"type":"diff","path":"…","oldText":"…","newText":"…"}`. No codex isso foi garimpado.
- **Opções com semântica**: `kind: reject_once | allow_once | allow_always`. E o "Always Allow"
  declara em `_meta` o que faz: `set permission_mode acceptEdits`, `lifetime.scope: session` — dá para
  escrever na tela o efeito real do botão. Nota: `options[0]` era **`reject_once`**; escolher por
  posição nega tudo.
- **Custo por turno**: `usage_update` → `used: 38718 / size: 1000000`, `cost.amount: 0.3728 USD`.
  Não existe hoje em nenhum lugar da plataforma.
- **Continuidade de sessão nativa**: `resume`, `fork`, `list`, `load`, `close`, `delete` anunciados em
  `agentCapabilities.sessionCapabilities`. Era a principal objeção contra o `stream-json` — como manter
  sessão num processo que morre a cada turno.

### O que exige cuidado

- **`tool_call` abre `pending`; `tool_call_update` fecha** — 35 mensagens para 7 ferramentas, média de
  5. Mesma assimetria do codex, mas tipada: título refina, `content` chega, e só então
  `status: completed` + `rawOutput`.
- **`fs/read_text_file` nunca disparou.** Declarar a capacidade não redireciona as leituras do agente;
  ele usa a ferramenta `Read` dele. Essa capacidade serve a editor com buffer sujo, que não é o caso.
- Deltas de fala são **30%** do fluxo (contra ~65% no codex). O alvo de coalescência aqui é
  `tool_call_update`, não delta de fala.

## Decisões do operador

| | |
|---|---|
| **Escopo** | Lane **nova** (`claude-4`), as 3 existentes intactas — mesmo padrão do `codex-4`. |
| **Permissão** | **`default`**: `request_permission` fica visível no Mission Control. `auto` foi medido em 0 pedidos na Task 1 e descartado — o classificador aprova sozinho, deixando a tela sem fonte. Diverge de propósito do `defaultMode: auto` das 3 lanes TUI: ali o operador olha o terminal, aqui olha a Frota (ver §2). |
| **Observação das 3 atuais** | Ligar junto. *Revisado depois de medir:* transcript em vez de hooks (ver §3). |
| **Protocolo** | ACP, não `stream-json` — decidido depois de ele apontar o Zed. |

## §1 Arquitetura

A inversão importa: **o adaptador é o servidor, o loomd é o cliente.** É o papel que o Zed ocupa.

```
loomd (Rust)                        claude-agent-acp (Node)        claude
  src/acp.rs ──ND-JSON/stdio────▶    session/prompt          ──▶    (SDK)
             ◀──session/update───    agent_message_chunk
             ◀──session/request_permission  (fica pendurado)
```

**Módulo novo `src/acp.rs`.** Conhece ACP e **nada** sobre o formato da trama: emite valores `Evento`
e para aí. Essa costura já existe — é o que `codex.rs` faz —, então `trama.rs` não muda de contrato.

**Uma extração, e só ela.** Com `codex.rs` e `acp.rs` passam a existir dois supervisores de processo
filho idênticos (spawn, backoff, respawn) → extrair para `src/supervisao.rs`. É a única mudança em
código que já funciona. **O `codex.rs` não é reescrito**; está provado.

### Rotas

As rotas existentes servem a lane nova, com uma exceção que é declarada e não escondida:

| rota | codex | ACP |
|---|---|---|
| `/prompt` | `thread/prompt` | `session/prompt` |
| `/interrupt` | `turn/interrupt` | `session/cancel` |
| `/turns` | trama | trama (idêntico) |
| `/steer` | `turn/steer` — **redireciona o turno em curso** | **não existe.** ACP anuncia `promptQueueing: true`: outro prompt **enfileira**. |

Semântica diferente sob o mesmo nome é armadilha: na lane ACP a UI diz **"enfileirar"**, nunca
"redirecionar".

**Rota nova: `POST /v2/lanes/:lane/decide`.** O `request_permission` é um pedido JSON-RPC pendurado
esperando resposta — diferente de todo o resto da trama, que é fluxo de mão única. O `acp.rs` guarda o
`id` pendente, publica o evento de aprovação, e a decisão vinda do Mission Control o responde. Sem
decisão, o turno fica parado — comportamento correto, que a tela mostra como **"esperando você"** e
nunca como "travado".

## §2 A tabela de tradução

| `session/update` | vira | por quê |
|---|---|---|
| `agent_message_chunk` | `Delta` (coalesce em RAM) | fala; política do codex reusada |
| `agent_thought_chunk` | `Delta` marcado como pensamento | pensamento não é resposta |
| `user_message_chunk` | `UserPrompt` | o prompt persistido de graça |
| `tool_call` (`pending`) | `ToolStart` | abre |
| `tool_call_update` **com** `status: completed` | `ToolEnd` + `rawOutput` | fecha |
| `tool_call_update` **sem** `status` | coalesce, **não persiste** | refino de título não é evento |
| `usage_update` | `Usage` (**tipo novo**) | custo e janela por turno |
| `plan` / `plan_update` / `plan_removed` | registrar, **sem UI** | não há tela de plano — YAGNI |
| `available_commands_update`, `config_option_update`, `current_mode_update`, `session_info_update` | ignorar, logar **uma vez** | logar uma vez é o que faz um evento novo aparecer em vez de sumir |

| `session/request_permission` | vira |
|---|---|
| `toolCall.kind: "edit"` | `ApprovalKind::Patch` + o `content[{type:"diff"}]` já pronto |
| `toolCall.kind: "execute"` | `ApprovalKind::Command` |
| outro | `ApprovalKind::Other` |
| `options[].kind` | os botões, por **semântica** — nunca por posição |

`ApprovalKind` já existe em `event.rs`. `Usage` é o único tipo novo: entra porque o custo chega sem
ser pedido e não existe em nenhum outro lugar. Escopo dele aqui é **persistir na trama e expor por
`/turns`** — desenhar isso na tela do Mission Control é trabalho de outra fatia, e este spec não o
promete.

**Não-negociável:** logo após `session/new`, enviar `session/set_mode` explícito. Sem essa linha, o
padrão `bypassPermissions` torna toda a tabela de aprovação acima código morto — e a única evidência
seria uma tela vazia.

### ⚠️ `auto` e `default` não são a mesma coisa, e o censo só provou uma

O modo pretendido é **`auto`**, para alinhar com o `defaultMode: auto` que as 3 lanes já usam. Mas o
`request_permission` foi medido em **`default`**. Os modos anunciados diferem no que fazem:

| modo | descrição do próprio adaptador |
|---|---|
| `auto` | "Use a model classifier to approve/deny permission prompts" |
| `default` | "Standard behavior, prompts for dangerous operations" |

Se o classificador do `auto` aprova sozinho, **`request_permission` pode não disparar** — e a tela de
aprovação volta a ficar sem fonte, pelo mesmo mecanismo do `bypassPermissions`, só mais discreto.

**Primeiro passo da implementação:** repetir o censo em `auto` e contar `request_permission`. O
resultado escolhe entre duas coisas que são um *trade-off do operador*, não uma decisão técnica:

- **`auto`** — menos interrupção, alinhado às lanes atuais, e possivelmente **nenhuma** decisão
  visível no Mission Control.
- **`default`** — cada decisão perigosa aparece na tela (medido: 3 pedidos numa tarefa de dois
  arquivos), ao custo de a lane parar esperando.

**MEDIDO (Task 1 do plano):** `auto` emitiu ZERO `request_permission` na mesma tarefa em que
`default` emitiu 3 — o classificador aprova sozinho e nada aparece na tela. O modo é **`default`**:
a lane para esperando decisão, e cada decisão perigosa fica visível no Mission Control. Isso
DIVERGE de propósito do `defaultMode: auto` das 3 lanes TUI, porque ali o operador está olhando o
terminal e aqui ele está olhando a Frota. Evidência em
`fixtures/2026-08-10-acp-censo-modo-auto.jsonl`.

## §3 As 3 lanes atuais — observação por transcript, zero configuração

Um `TranscriptTail` por lane: escolhe o `.jsonl` mais recente por mtime, lê a partir de um offset em
bytes persistido, e reabre quando a sessão roda para arquivo novo.

**O caminho tem uma pegadinha que quase derrubou este desenho:** cada lane tem **HOME próprio**. Não é
`~/.claude/projects/`, é:

```
/workspace/.home/openvscode-server/.agents/<lane>/.claude/projects/-workspace-sounio/<sessão>.jsonl
```

O diretório compartilhado está parado desde 06/08; os das lanes estão vivos (10/08 18:01, 18:24,
18:16). O primeiro palpite deste desenho apontava para o arquivo morto.

Tipos de linha, censados em 5.632 linhas reais de 13 transcripts do mesmo binário:

| linha | vira | |
|---|---|---|
| `assistant` (2421) | `AgentMessage` / `ToolStart` | o grosso |
| `user` (991) | `ToolEnd` quando traz `tool_result` | |
| `last-prompt` (315) | `UserPrompt` | |
| **`ai-title`** (298) | **o título do chip** | o Claude Code nomeia o que está fazendo — melhor que o título OSC raspado do tmux |
| `mode` (311), `permission-mode` (84) | mudança de modo | |
| `attachment`, `queue-operation`, `file-history-*`, `pr-link`, `system`, `agent-name` | registrar, sem UI | |

**O que compra:** as 3 lanes passam a `confidence: exact` **sem uma linha de configuração nelas** — o
`settings.json` com `defaultMode: auto` não é tocado, o TUI fica intacto, e as 5.632 linhas que já
existem entram na trama retroativamente.

**Isto substitui os hooks** aprovados antes da medição. A rota `/hooks/claude/:lane` e a tradução
`from_claude_hook` permanecem no código para o dia em que for preciso **interceptar**; para
**observar**, o arquivo já está lá, com fidelidade total em vez de só os pontos onde o hook dispara.

**Ressalva:** os tipos foram censados no diretório antigo. Mesmo binário, mesmo formato — mas o
primeiro passo da implementação é reconfirmar nos arquivos vivos, porque essa exata classe de
suposição já errou uma vez neste documento.

## §4 Supervisão, retomada e o vazamento

**A lane ACP** persiste o `sessionId` do `session/new`. No respawn, `session/load` — capacidade
anunciada (`loadSession: true`), então retomada é chamada de protocolo, não heurística.

**O vazamento.** Cada `request_permission` pendurado é um `id` JSON-RPC num mapa esperando resposta. Se
o filho morre no meio, ficam botões na tela do Mission Control que não respondem a ninguém, para
sempre. Portanto: **a morte do filho resolve toda aprovação pendente como cancelada, na trama, antes
do respawn.** É o único ponto deste design onde uma falha produz UI **mentirosa** em vez de UI
ausente — e por isso é o teste caro.

**O tail** não precisa de supervisão de processo, mas precisa de duas guardas que arquivo pede e
socket não: **truncamento** (offset maior que o arquivo → recomeçar do zero) e **rotação** (sessão
nova → arquivo novo).

## §5 Testes

**Replay dourado.** O `censo.jsonl` capturado vira fixture: 42 e 70 linhas de fio **real**, com diff,
aprovação e custo. O tradutor come o arquivo e a trama resultante é assertada. Rede de regressão feita
de dados medidos.

**As mutações que precisam matar** — declaradas porque o histórico deste projeto é de testes
teatrais:

1. Remover o `session/set_mode` → o padrão `bypassPermissions` volta → o teste que exige um evento de
   aprovação **tem que ficar vermelho**. Verde aqui significa teste teatral.
2. Trocar `allow_always` por `options[0]` → tem que quebrar (`options[0]` é `reject_once`).
3. Persistir `tool_call_update` sem `status` → eventos por ferramenta saltam de 2 para 5 → quebrar.
4. Matar o filho com aprovação pendente → toda pendência resolvida; sobrar uma é vermelho.
5. Apontar o `TranscriptTail` para `~/.claude/projects/` em vez de `.agents/<lane>/` → tem que
   quebrar. É o erro que este documento cometeu.

**O que os testes não cobrem:** que o `claude-4` produz trabalho bom. Isso é o operador olhando a
tela. Os testes cobrem a tradução e o não-vazamento.

## Riscos

- **Node ≥ 22 exigido, medido em v20.** Funciona, fora de suporte. Se quebrar, o conserto é pinar Node
  22 na lane — o workspace já tem Node pinado como prática.
- **O adaptador é um processo Node.** Não é "Rust puro". Mas o `stream-json` também é Node; a escolha
  é entre protocolo aberto e dialeto privado, não entre Node e não-Node.
- **`bypassPermissions` como padrão do adaptador** pode voltar a valer se uma versão futura ignorar o
  `set_mode`. Mutação 1 é a rede: o teste vira vermelho.
- **`/steer` com semântica divergente** entre as duas classes de lane. Mitigado por rótulo na UI, não
  por código — e portanto depende de a tela dizer a verdade.
- **A extração de `supervisao.rs` toca o `codex.rs`, que está provado.** Escopo mínimo: mover, não
  redesenhar; a suíte do codex tem de continuar verde sem edição.

## Fora de escopo

- Reescrever `codex.rs` sobre ACP. Funciona; o valor da migração é opcional e não é este trabalho.
- Tela de plano (`plan`/`plan_update` ficam registrados sem UI).
- O loomd como **servidor MCP de IDE** (`~/.claude/ide/<porta>.lock`, `openDiff`, `getDiagnostics`),
  que permitiria mostrar diffs das 3 lanes TUI sem tirar o TUI. É complementar e fica para depois.
- `fs/read_text_file` / `terminal/*` como capacidades do cliente — medido que não são exercidas.

## Resultado (Task 8 do plano)

**Provado ao vivo em 11-ago-2026**, `claude-4` dirigida por ACP, contra uma instância de loomd de
teste (porta 127.0.0.1:4405, trama própria, produção na 4400 intocada durante toda a tarefa) — em
duas passadas. A primeira encontrou dois defeitos reais que nenhuma fixture das Tasks 1-7 pegava.
A segunda, depois desses dois defeitos serem consertados (`c018fb47`, `e5a5cd44`) com teste e
mutação vermelha por asserção, voltou à prova ao vivo — porque foi ela que os achou, e suíte verde
não prova que a fala aparece num turno de verdade — e fechou os dois.

### O que está provado, final

- **Handshake.** `initialize` → `session/new` → `session/set_mode` como última chamada do
  handshake (mutação §1 do §5), confirmado ao vivo três vezes ao longo das duas passadas.
- **Turno.** Um prompt de leitura real produziu `session_started`, `user_prompt`, `tool_call`,
  `tool_result` e `usage` (com custo em USD), todos `confidence: exact`.
- **`agent_message` com texto real, íntegro, não vazio.** Depois do fix `e5a5cd44`, o mesmo
  prompt (*"Liste os arquivos de stdlib/epistemic/ e diga em uma frase o que cada um faz."*)
  produziu **dois** `agent_message` no mesmo turno: um **antes** do primeiro `tool_call`
  (`"I'll look at the directory."`, 27 caracteres, seq 3302, antes do seq 3303) e um no fechamento
  do turno (6676 caracteres, a tabela completa dos 59 arquivos de `stdlib/epistemic/`, seq 3316).
  Numa sessão seguinte, mais dois turnos produziram mais dois `agent_message` (359 e 241
  caracteres) — quatro no total, nenhum vazio, todos `confidence: exact`, texto conferido no
  campo `text` (não só `detail`). A fala antes da ferramenta — exatamente o que `limpar_delta`
  descartava antes do fix — está registrada.
- **A colisão de id não volta, testada exatamente no ponto onde quebrava.** Um turno foi forçado
  a pedir quatro aprovações na mesma sessão (`date`, `whoami`, `pwd`,
  `echo quatro > .../quatro.txt`, cada uma como chamada de ferramenta separada). O 3º pedido — id
  `2` do adaptador, o mesmo número reservado a `ID_SESSAO` — apareceu na trama como
  `awaiting_approval` com `approval_id: "2"` e o comando real (`echo quatro > ...`), foi
  respondido por `POST /v2/lanes/claude-4/approve {"approval_id":"2","allow":true}` → `ok`, e
  `quatro.txt` apareceu no disco. Nada travou. Antes do fix, esse exato cenário (3ª aprovação da
  sessão) engolia o pedido e pendurava o turno para sempre — reproduzido nas duas passadas para
  comparação direta.
- **Aprovação com `diff` (§2 do spec).** Provado na primeira passada e reconfirmado: um prompt de
  escrita gerou `awaiting_approval` com `approval_kind: "patch"` e `diff` pronto em campo tipado
  (`--- NOTA_LANE.md ... +Esta lane é dirigida por protocolo ACP.`); `POST .../approve` respondeu
  `ok`; o arquivo apareceu com o conteúdo exato do diff.
- **Os 3 tails.** `claude-1` (1137 eventos), `claude-2` (1648) e `claude-3` (513), todos
  `confidence: exact`, lidos só de `LOOMD_TAILS` — zero linha de configuração nas lanes.
- **Binário verificado por valor, não por confiança no `cargo build`.** `sha256sum` do binário
  antes (`38c5ceba...`) e depois (`a347397a...`) do rebuild no pod confirmou que o binário rodando
  na porta 4405 era de fato o novo, com `classificar()` e `descarregar_fala()` presentes no fonte
  sincronizado (checksums do fonte no t560 e no pod idênticos, byte a byte).

### Os dois defeitos — achados pela prova ao vivo, não por review

Nenhum dos dois apareceu nos testes das Tasks 1-7. As fixtures usadas nelas vieram de um turno
curto e não reproduziam a forma real do tráfego do adaptador Node 22 vivo — nem o fato de que o
adaptador numera seus próprios `session/request_permission` numa sequência independente da nossa
(colisão só aparece na 3ª aprovação de uma sessão), nem o fato de que ele só emite
`agent_message_chunk`, nunca a variante completa. Um teste unitário com fixture sintética não
tinha como pegar nenhum dos dois — só um turno de verdade, contra o adaptador de verdade, achou.

1. **Colisão de id JSON-RPC (`c018fb47`).** `acp.rs` reservava `ID_SESSAO = 2` para a resposta da
   própria chamada `session/new`/`session/load`, e `on_message` casava por `id == 2` antes de
   olhar se a mensagem tinha `method` (pedido) ou não (resposta). Na 3ª aprovação de uma sessão
   — id do adaptador == 2 — a mensagem caía no ramo errado e era descartada em silêncio; o
   adaptador ficava esperando para sempre por uma resposta que nunca viria, e o turno travava
   permanentemente. Reproduzido ao vivo duas vezes na primeira passada. Corrigido extraindo a
   decisão para `classificar()`, função pura que decide por `method` antes de `id` — a regra do
   JSON-RPC (mensagem com `method` é sempre pedido, nunca resposta).
2. **Fala descartada (`e5a5cd44`).** O adaptador real só emite `agent_message_chunk`; a variante
   completa que `event.rs` sabia traduzir nunca chega. O desenho anterior coalescia os chunks em
   RAM esperando por um evento completo que não existe, e pior: `limpar_delta` era chamado a cada
   `tool_call`, descartando qualquer fala que tivesse vindo antes da ferramenta. Resultado: a
   trama registrava `tool_call`, `tool_result`, `usage` — nunca o que o agente disse. Corrigido
   com `Trama::tomar_delta` (tira-e-limpa numa operação) e `descarregar_fala()`, chamada em dois
   pontos: quando um `tool_call` chega (a fala anterior é enunciado completo) e no fim do turno
   (a resposta de `session/prompt`, que não tem outro gatilho).

**O dado mais valioso desta fatia não é que a lane funciona — é que "passou nos 68 testes" e
"funciona contra o adaptador de verdade" continuaram sendo, por duas vezes seguidas, afirmações
diferentes. As duas vezes que divergiram, foi a prova ao vivo que pegou, não o review nem a
suíte.**
