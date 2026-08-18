# Estado em 2026-08-18 — espinha de memória e Fase 2

**Para o agente que estiver trabalhando nos crates aspiracionais.** Escrito por uma sessão
Claude Code que passou as últimas ~12 h na espinha de memória (`apps/memory-pg`), no cockpit e
no iOS. Tudo abaixo foi **medido**, não presumido; onde eu contradigo um documento de plano,
digo qual medição me levou a isso.

---

## 1. Leia isto antes de apagar ou reescrever qualquer coisa

O plano do exocórtex (`.claude/plans/reactive-fluttering-frost.md`, Fase 3) manda **REMOVER a
fachada aspiracional**, não reimplementá-la. A frase literal é *"Deletar > substituir"* e
*"Não reimplementar IIT 'de verdade'. Não é pré-requisito de nenhum elo."*

**Se a sua tarefa é refazer esses crates, isso pode estar em conflito direto com uma decisão
já tomada pelo dono.** Confirme com ele antes de investir. Reconstruir o que foi decidido
remover é o pior desperdício possível: some depois, e some com trabalho junto.

---

## 2. O que eu VERIFIQUEI sobre a "fachada" — e onde o plano está desatualizado

Rodei `grep` no repo inteiro antes de repetir qualquer alegação. Resultado:

### `services/sounio-inference/app.py` — **é real, não é fachada**

O plano descreve esse arquivo como fachada (`cognitive_fractal_recurse` como série geométrica,
`phi.compute` rotulado de "IIT-4"). **Não encontrei nada disso.** O que encontrei foram
endpoints substantivos:

```
/v1/smt/check        /v1/gum/propagate      /v1/causal/dsep
/v1/pcs/reason       /v1/theorem/prove
```

mais `_compile_and_run()`, que compila e executa Sounio de verdade. 24 KB de código com
conteúdo. **Não apague este arquivo.** Ou a fachada já foi removida, ou o plano descrevia
outra coisa.

### `crates/beagle-fractal/` — **tem 829 linhas de Rust real**

`entropy_lattice.rs`, `fractal_node.rs`, `holographic_storage.rs`, `self_replication.rs`.
Não avaliei a qualidade nem se as alegações teóricas se sustentam — só constato que **não é
casca vazia**. Se for reescrever, é decisão de mérito, não de "isto não existe".

### As ferramentas MCP `cognitive_*` — **essas sim, anunciadas sem corpo**

```
cognitive_meta_phi   phi_of_phi   joint_phi   tool_rhythm_phi   cognitive_fractal_recurse
```

`grep -rl` em `*.py *.ts *.mjs *.rs` no repo inteiro: **ZERO arquivos** para os cinco. E no
entanto estão registradas e visíveis como ferramentas MCP (`mcp__beagle-cognitive__*`).

Elas são servidas por um runtime **fora do repositório** (`~/.beagle/mcp-runtime`), o que
explica por que o grep não as encontra. **É aqui que a Fase 3 se aplica de fato**: ferramenta
anunciada sem implementação é alegação órfã — exatamente o que o sistema de proveniência
existe para marcar.

---

## 3. O que mudou nas últimas horas — evite colisão

Mergeado hoje (PRs #51, #52, #53, #54, #55):

| área | o que |
|---|---|
| `apps/memory-pg/` | **mudança pesada** — extração, guardas, Fase 2, alarmes. Migrações 014–016. |
| `apps/project-cockpit/server/` | `memory-ingest.mjs`, `mobile-routes.mjs` — nota avulsa + modalidade |
| `beagle-ios/BeagleSuite/Sources/` | `BeagleCore/*`, `BeagleCockpit/MultimodalComposer.swift`, `Companion/ChatScreen.swift` |
| `k8s/memory-pg/` | 3 CronJobs + 1 Deployment novos |
| `docs/` | pré-registro congelado + registro de decisões |

Ramos de destino: `reconcile/unify-beagle`, `voz-com-emocao`, `integration/companion-tronco`.

**Se você mexer em `apps/memory-pg`, puxe antes.**

---

## 4. Invariantes vivos — quebrar qualquer um destes corrompe ciência, não só código

Estes não são estilo. Cada um veio de um defeito medido em produção hoje:

1. **`docs/PREREG_FASE2_DIRECAO_v1.md` é IMUTÁVEL.** Seu SHA-256 está em `agreement.mjs` e é
   conferido a cada julgamento. **Uma linha em branco a mais derruba o pipeline** — de
   propósito. Mudar direção exige `direcao-v2` com motivo escrito.

2. **Duas guardas de auto-relato, e nenhuma cobre a outra.** `speakerIsSubject()` (quem
   falou) e `subjectIsSelf()` (de quem é o estado). Sem a segunda, "Você estava confuso" —
   sobre o companion — virava relato sobre o corpo dele. Medido: 3 de 9 em canal elegível.

3. **`valence` é inelegível para corroboração.** A única fonte é `HKStateOfMindType`, que é
   ele declarando o próprio humor num app. Mesma boca, dois microfones.

4. **Fato sem `statement` não entra.** É o texto que vai ao índice semântico; sem ele o fato
   nasce invisível. Antes eram 66% do que um modelo produzia.

5. **O esquema no prompt tem que ser JSON válido.** Era abreviado, o modelo copiava o
   esqueleto literalmente, e o registro ia para a DLQ. Há teste que faz `JSON.parse` no
   exemplo do prompt.

6. **Nada é apagado para "limpar".** Linha de DLQ sobrevive ao reprocessamento; correção de
   classificação desmarca, não deleta. Ver `docs/FASE2_DECISOES.md`.

---

## 5. Rodando em produção agora — não reimplante por cima sem olhar

```
memory-pg-graph-worker       3/3   qwen2.5:14b   (faixa `bulk`)
memory-pg-graph-worker-voz   1/1   r1-distill-70b via roteador (faixa `voice`)
vllm-r1 / vllm-hunyuan-7b    servindo no r740
CronJobs: physio-join :17 · judge-agreement :37 · fleet-health e graph-health */30
```

Imagem atual: `memory-pg-embed-worker:p31-sujeito-9bf8668c`.

⚠️ **Aprendi hoje na pele:** já implantei imagem construída de um commit local que nunca foi
empurrado — código em produção que não estava no git. Se construir, **empurre antes**.

---

## 6. Uma armadilha de operação que vai te pegar

O `r740` (nó das GPUs) vive com **99% da CPU reservada e ~26% usada**. Reservas fictícias
bloqueiam serving: achei `buildkitd` reservando 48 cores e usando 1 milicore, e `slurm-pilot`
reservando 8 e usando 1.

Se um pod de GPU não escalona por CPU, **o problema quase nunca é falta de CPU real** — é
reserva inflada de outro workload. Baixe o `requests`, mantenha o `limits`.

---

## 7. Como me alcançar

Não consegui te mandar mensagem direta: você não aparece no `ListAgents` desta sessão (que só
enxerga sessões Claude), e o `coord-mcp` (ClusterIP `:8900`) não é alcançável do host. Este
arquivo é o canal.

Se precisar de contexto que não está aqui, o dono da sessão pode pedir — ele está lendo.
