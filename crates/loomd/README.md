# loomd — supervisor de sessões de agente

Não é multiplexer de terminal. Um multiplexer resolve o problema de 1984 (muitas telas, um
monitor); o problema aqui é de 2026: **muitas sessões de agente, uma atenção**.

A frota tinha um classificador que lia a tela das lanes com expressão regular a cada 12 s e
adivinhava se o agente estava trabalhando ou esperando você. Custou testes vermelhos descobrir
que `Worked for 5m` no Codex é separador de turno **concluído** enquanto `Cooked for 2m` no
Claude é spinner **ao vivo**. Isso não é fragilidade de heurística: é a camada errada. O agente
sabia exatamente em que estado estava, desenhou isso em pixels ANSI, e nós tentávamos reconstruir
do outro lado o que tinha sido destruído no meio.

## Duas fontes, um vocabulário

| | Codex | Claude Code |
|---|---|---|
| transporte | `app-server` (JSON-RPC, stdio) | hooks HTTP |
| somos donos do processo? | **sim** | **não** — é configuração |
| alcança lane que já rodava? | não | **sim** |
| aprovação | RPC tipado (respondemos veredito) | evento (fatia 1 só observa) |

O produto real é a **tabela de tradução** (`src/event.rs`): `waitingOnApproval` do Codex e
`permission_prompt`/`agent_needs_input` do Claude são a mesma verdade. Sete grafias de "esperando
humano" viram um vocabulário.

Todo evento carrega `confidence`: `exact` (veio de protocolo) ou `inferred` (veio de tela, para a
lane de compatibilidade que ainda não existe). **Nenhuma ação destrutiva pode disparar em
`inferred`.**

## Rodar

Compile **dentro do pod**: o t560 tem glibc 2.41 e o pod 2.39, então binário feito no t560 não
roda lá. `cargo` 1.95 já existe no workspace.

```bash
kubectl -n beagle exec -it sounio-workspace-control-0 -c workspace-ssh -- su -s /bin/bash openvscode-server
B=/workspace/.home/openvscode-server
export PATH="$B/.cargo/bin:$B/bin:$B/.local/node-v20.20.2-linux-x64/bin:$B/.local/bin:$PATH"
export HOME=$B/.agents/codex-1          # a auth do codex vive no HOME da lane
cd /workspace/.loomd && cargo build --release

export LOOMD_ADDR=127.0.0.1:4400
export LOOMD_TRAMA=/workspace/.loomd/trama.jsonl
export LOOMD_CODEX_LANES=lab-1          # VAZIO por padrão: não adota lane sem alguém mandar
export LOOMD_CWD=/workspace/sounio
export LOOMD_CODEX_ARGS="-c model_reasoning_effort=high -c approval_policy=untrusted -c sandbox_mode=workspace-write"
./target/release/loomd
```

⚠️ `model_reasoning_effort` — o config das lanes usa `max`, que a versão instalada não conhece
(`unknown variant 'max'`) e isso quebra o cache de modelos. Passe `high` via `LOOMD_CODEX_ARGS`.

### Rotas

| | |
|---|---|
| `POST /hooks/claude/:lane` | destino dos hooks HTTP do Claude Code |
| `GET /v2/state` | estado por lane, derivado da trama |
| `GET /v2/trama?since=N&lane=X` | eventos; `since` é cursor |
| `POST /v2/lanes/:lane/prompt` | dirigir a lane sem terminal (**202**, o resto vem pela trama) |
| `POST /v2/lanes/:lane/approve` | aprovar **sem anexar** |

Ligar uma lane de Claude é só configuração — nada de daemon novo:

```json
{ "allowedHttpHookUrls": ["http://127.0.0.1:4400/*"],
  "hooks": { "PermissionRequest": [ { "hooks": [
    { "type": "http", "url": "http://127.0.0.1:4400/hooks/claude/claude-1", "timeout": 15 } ] } ] } }
```

Para testar sem tocar em `settings.json` de lane nenhuma, use `claude --settings '<json>'`.

## Durabilidade (o que atravessa um restart do daemon)

`Trama::open` **relê o rabo do `trama.jsonl`** e daí saem três coisas: o `seq`, o estado das lanes
e o `threadId` de cada uma. Não existe arquivo de estado paralelo — um segundo arquivo é uma
segunda verdade, e as duas divergem.

Consequências, medidas ao vivo em 09-ago-2026 (reinício do daemon com a lane `loom-1`):

* **`seq` monotônico através de reinícios.** Antes: `[1..8, 1..8, 1..8]` no arquivo real — três
  subidas com as mesmas chaves, e `?since=8` nunca mais entregava nada. Depois do restart o
  arquivo seguiu `…15, 16, 17…`, e um cursor tirado ANTES (`?since=15`) devolveu exatamente os
  eventos 16–24 de DEPOIS.
* **O board não nasce cego.** `/v2/state` responde a lane no primeiro segundo, sem `--seed` e sem
  turno novo. (Era `{"lanes":[]}` até alguém falar.)
* **A subida FRIA retoma a thread.** O id vem da trama e o `thread/resume` sai no boot. Provado
  pelo conteúdo, não pelo log: o número dado à lane ANTES do restart foi respondido DEPOIS.
* Se o store do Codex não tiver mais aquela thread, a resposta de erro ao `thread/resume` faz o
  id ser **esquecido** — senão todo `turn/start` seguinte bateria num id morto, para sempre.

A releitura é de uma **janela do fim** (1 MiB, teto de 5 000 eventos em RAM): o custo do boot não
pode crescer com o histórico. O `seq` continua exato porque, a partir daqui, o maior está na
última linha. O jsonl legado mantém as chaves duplicadas que já tem — o diário é append-only e
reescrevê-lo para "consertar o passado" seria pior que a duplicata.

## Depurar

**`LOOMD_DEBUG=1` despeja o fio cru.** Use antes de deduzir: duas rodadas de raciocínio sobre a
forma das mensagens não acharam o que uma olhada no fio achou em uma.

## Armadilhas que já custaram caro

1. **`cargo test` NÃO atualiza `target/release/loomd`.** Uma rodada inteira de diagnóstico foi
   feita contra binário velho. `aceite.sh` recompila antes de medir; faça o mesmo.
2. **O `threadId` não é uniforme dentro do próprio protocolo:** `result.thread.id` em
   `thread/start`, `params.thread.id` em `thread/started`, `params.threadId` em
   `thread/status/changed` e `turn/diff/updated`. Use `event::thread_id`, que aceita as três.
3. **Cada família de aprovação tem o SEU enum.** `fileChange`/`commandExecution` querem `accept`;
   `execCommandApproval`/`applyPatchApproval` usam `ReviewDecision` (`approved`). Valor inválido é
   aceito em silêncio pelo transporte e **ignorado pelo agente** — um "aprovado" que não aprova.
   Ver `event::codex_approval_reply`.
4. **Não bloqueie o request HTTP esperando resposta assíncrona.** O axum descarta o future de um
   cliente que desconectou; foi assim que um `turn/start` deixou de ser enviado.
5. **`sandbox_mode=read-only` bloqueia a escrita mesmo com a aprovação concedida.** Para provar
   efeito, use `workspace-write`.
6. **Teste com caminho de `/tmp` fixo mente depois que `open` passou a reler.** Os testes da trama
   usavam `loomd-test-1.jsonl` e só passavam porque a versão antiga IGNORAVA o conteúdo do
   arquivo. Com a releitura, o resultado passaria a depender de quantas vezes a suíte já rodou
   naquela máquina. Use `arquivo_novo()`, que apaga antes.
7. **Retomar o `seq` pela ÚLTIMA linha não serve — tem que ser o MAIOR.** Numa subida mais curta
   que a anterior, o último é menor que o maior, e a próxima chave colide com uma que já existe.

## Deriva de versão

As CLIs atualizam quase todo dia e o operador quer estar na última. Então **nada aqui compara
número de versão**: o Codex descreve o próprio protocolo (`generate-json-schema`) e o Claude
declara `capabilities[]` no `system/init`. Evento desconhecido vira `Unknown`, é registrado, e
**não sobrescreve** um estado conhecido.

O guarda disso é `apps/project-cockpit/experiments/cli-canary.sh`, que mede o binário instalado e
falha alto se um campo de carga sumir. Rode antes de qualquer deploy do `loomd`.

## Orçamento (cláusula do Fable)

O `loomd` é Rust porque o andaime de supervisão é pequeno. **Se ele passar de ~500 linhas, ou se
aparecer um segundo bug de vivacidade em review, a evidência empírica venceu e isto se reescreve
em Elixir/OTP antes da lane 2 migrar.** Refaça a conta a cada rodada — o compromisso não vale
nada sem ela.

Medição de 09-ago-2026, **método declarado** (linhas não vazias e não comentadas, `awk` do
cabeçalho da função até o `}` de coluna 4): `spawn` + laço de reinício **33**, `run_once` **50** —
total **83**. A rodada anterior anotou 29 + 34 = 63 sem declarar o método; a diferença é grande
demais para vir das 4 linhas que a subida fria acrescentou, então **os dois números não são
comparáveis** e este é o novo marco zero. Continua abaixo do teto de ~500, e nenhum bug de
vivacidade novo apareceu nesta rodada.
