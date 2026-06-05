# Kimi UI Brief - Beagle Command Center v0.4.1

Kimi, voce esta assumindo o design/arquitetura do frontend do Beagle Command Center.
Leia primeiro estes documentos no mesmo diretorio:

- `HANDOFF.md`
- `API_MAP.md`
- `COMPONENT_INVENTORY.md`
- `CONTRACT.md`

## Contexto

O frontend atual e o Darwin Cluster Ops: um cockpit operacional para infraestrutura HPC, Proxmox, Slurm e Kubernetes.
Ele funciona para observar cluster health, doctors, status cards, acoes operacionais e ponte SSH/Slurm.

Mas o Beagle nao deve parecer apenas um dashboard HPC. O Beagle e um exocortex cientifico pessoal com:

- pipeline adversarial ATHENA/HERMES/ARGOS
- memoria GraphRAG
- observer fisiologico, incluindo HRV
- jobs cientificos PBPK, heliobiology e scaffolds
- input conversacional com agentes
- gate de Action Ledger para acoes destrutivas

## Objetivo da UI

Transformar o Darwin Cluster Ops em um Beagle Command Center sem reescrever tudo do zero.

A UI nova deve preservar a base operacional existente, mas mudar o centro de gravidade:

- de "cluster dashboard" para "scientific exocortex"
- de "status infra" para "pipeline cognitivo vivo"
- de "cards de ops" para "thread + triad + memoria + fisiologia + ledger"

## O que Codex mantem

Codex/ops mantem:

- Cluster health API
- doctors execution
- SSH/Slurm bridge
- Action Ledger
- REST `/api/*`
- WebSocket/event bus comum em `/ws/events` quando implementado

Nao quebre estes contratos sem combinar.

## O que voce deve projetar/criar

Crie ou especifique os seguintes modulos de frontend:

- Pipeline UI: Darwin -> Observer -> HERMES -> Triad
- Agent Thread: input do usuario, respostas de agentes, eventos e tool calls
- Triad Review: tres colunas ATHENA/HERMES/ARGOS com consenso, conflito e decisao
- Memory Graph Explorer: visualizacao navegavel de entidades, papers, hypotheses e links
- Physio HUD: HRV/observer em tempo real, com estado cognitivo/fisiologico
- Action Ledger Gate: confirmacao e auditoria para acoes destrutivas ou irreversiveis
- Scientific Doctors: doctors com contexto cientifico, nao apenas infra

## Restricoes tecnicas

- Framework atual: SolidJS + Vite.
- Nao assumir React a menos que seja uma migracao explicitamente planejada.
- O cockpit atual roda em `beagle/apps/project-cockpit`.
- O backend do cockpit e Node/Express.
- O Beagle Core e Rust/Axum em `localhost:8080`.
- O frontend atual de `/projects/cluster` consome principalmente a API ops do Express, nao o Beagle Core diretamente.
- `/cognitive` ja conversa com Beagle Core, mas ainda nao e o Command Center final.
- Autenticacao atual passa por bridge/token local; documentada em `API_MAP.md`.

## Interface-alvo

Use esta interface comum:

```json
{
  "type": "string",
  "payload": {},
  "timestamp": "2026-05-22T00:00:00Z",
  "agent_id": "athena|hermes|argos|observer|darwin"
}
```

Canal:

- REST: `/api/*`
- WebSocket: `/ws/events`

## Perguntas de design para responder

1. Qual e a primeira tela ideal do Beagle Command Center?
2. Como mostrar o pipeline cognitivo sem virar um fluxograma morto?
3. Como integrar cluster health sem deixar infra dominar a experiencia?
4. Como o usuario conversa com agentes e, ao mesmo tempo, ve memoria/triad/physio?
5. Qual layout suporta trabalho cientifico real por horas?
6. Como representar conflito ATHENA/HERMES/ARGOS de forma visualmente clara?
7. Como o Action Ledger aparece no fluxo sem virar friccao constante?

## Entregavel desejado de Kimi

Proponha:

- arquitetura de telas
- mapa de componentes
- fluxo principal do usuario
- layout responsivo desktop-first
- estados vazios, loading, erro e degraded mode
- componentes SolidJS que devem ser modificados ou criados
- ordem incremental de implementacao sem reescrever tudo

Se sugerir mudancas de backend, separe claramente em:

- obrigatorias
- opcionais
- futuras

Nao apague a parte ops. Absorva-a como uma camada do exocortex.
