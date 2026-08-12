# A Sessão à altura do chat — custo, fala e o efeito do steer

**Data:** 11-ago-2026
**Repo:** `beagle` (loomd) + `beagle-ios` no Mac (branch `integration/mission-control-ui`)
**Crates/alvos:** `crates/loomd`, `BeagleCore/Fleet`, `BeagleWorkbenchKit/Fleet`
**Antecessora:** [Lane ACP](2026-08-10-lane-acp-design.md) — entregue, em produção.

## O problema

Depois da fatia anterior a trama carrega coisas que a tela ignora. Medido na trama de produção:

```
agent_message   659   ← a tela JÁ desenha
tool_call      1146   ← desenha
tool_result    1112   ← desenha
usage             ?   ← IGNORADA: cai no `default: return nil` de SessionStore.passo(de:)
```

E há duas afirmações falsas na tela:

- A caixa da Sessão diz **"guiar o turno em curso…"** e o botão diz **GUIAR**. Verdade no codex
  (`turn/steer` redireciona); **mentira na lane ACP**, que só tem `promptQueueing` e **enfileira**.
- A caixa de prompt aparece em **todas** as lanes. Em `claude-1/2/3` (tail, observação read-only)
  `POST /prompt` devolve **404 — "lane não é supervisionada pelo loomd"**. O operador digita e toma
  erro.

O operador disse: *"o chat do Claude Code é legal"*. O que o torna bom é nomeável — conversa como
superfície principal, texto aparecendo enquanto é gerado, ferramenta recolhida e expansível, diff
inline, custo visível sem pedir. **A distância até lá não é arquitetura.** `SessionStep` já tem os
seis tipos, `store.streaming` já existe, `Turno.agrupar` já agrupa, e o arquivo já usa 13 recursos
de acabamento. Falta ligar três dados e polir quatro coisas.

## Decisões do operador

| | |
|---|---|
| **Custo** | Nos **dois** lugares: rodapé de cada turno na Sessão **e** acumulado no chip da lane. Ele aceitou o custo de dois lugares que precisam concordar — logo, **uma fonte só**. |
| **Steer** | O rótulo diz a verdade **antes do clique**, não depois. Exige o backend expor o que a lane aceita. |
| **Lanes de leitura** | **No escopo.** "O que esta lane aceita" passa a ser um conceito com três respostas. |

## §1 O campo que o backend precisa ganhar

Um campo, e ele serve às três decisões:

```rust
/// O que ESTA lane aceita. A tela lê isto para nunca oferecer o que devolve 404, e para dizer
/// "enfileirar" onde enfileira e "redirecionar" onde redireciona.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Aceita {
    /// codex: `turn/steer` redireciona o turno em curso.
    Redireciona,
    /// ACP: não há steer; `promptQueueing` enfileira para depois.
    Enfileira,
    /// tail: o loomd só LÊ o transcript. `/prompt` e `/steer` devolvem 404.
    SomenteLeitura,
}
```

Exposto em cada lane de `/v2/state`, derivado de **onde a lane vive** no `main()`: mapa codex →
`Redireciona`, mapa ACP → `Enfileira`, `LOOMD_TAILS` → `SomenteLeitura`.

**Isto aposenta o campo `efeito`** que a rota `/steer` devolve. Ele existia para confessar *depois*
o que aconteceu; com a classe conhecida *antes*, a confissão deixa de ser necessária. O `efeito`
permanece (é barato e é confirmação), mas **a tela decide pelo `aceita`**.

### 🚨 Capacidade não se deduz do nome nem de prosa

O modelo Swift já tem `LaneFamily.of(sid)`, que deriva família do **prefixo do sid**. Isso não
serve aqui: `claude-1` (tail) e `claude-4` (ACP) dão **ambas** `.claude` e se comportam de forma
oposta. Família não é capacidade.

E existe o mesmo anti-padrão já no código, que esta fatia corrige por estar mexendo nele:

```swift
public var isAbsent: Bool {
    state == .exited && detail.localizedCaseInsensitiveContains("não existe no tmux")
}
```

Capacidade deduzida de **frase em português**. O comentário ao lado diz que o servidor declara isso
"so the client never has to infer it" — e o cliente infere, de string. Muda a redação no servidor e
o cliente quebra **em silêncio**. `aceita` chega **tipado** do servidor e é decodificado, nunca
inferido; e `isAbsent` passa a sair de um booleano do servidor pelo mesmo princípio.

## §2 O custo, de uma fonte só

`usage` **não é um passo da conversa** — custo não é fala, e desenhá-lo na linha do diálogo
poluiria o que o operador lê. Ele entra como dado do **turno**:

```swift
/// Custo e janela de contexto do turno. Não é passo desenhado: é rodapé.
case uso(id: Int, contextoUsado: Int, contextoTeto: Int, usd: Double, at: Date)
```

`Turno` ganha `uso: UsoDoTurno?` derivado dos passos que ele agrupa. O **rodapé** mostra
`duração · contexto · USD`. O **chip** da Frota soma os `uso` dos turnos daquela lane.

**Uma fonte, duas telas.** O chip não recalcula de forma própria: soma o mesmo `Turno.uso` que o
rodapé exibe. Dois cálculos independentes divergem, e aí o operador não sabe em qual acreditar.

### Fatos medidos sobre o `usage` que o desenho tem de honrar

Contados nas fixtures do censo ACP:

- **`cost.amount` vem `None` em 15 dos 16 eventos** de um turno; só o último traz o número. Somar
  ingenuamente todos os `usage` de um turno funciona **por acidente** (os outros são zero) — mas o
  código deve pegar o **último com custo**, não somar.
- **`used`/`size` são absolutos e monotônicos** dentro do turno (31.578 → 38.718). O rodapé mostra
  o **último**, não a soma.
- O teto varia por agente: 1.000.000 no Claude, **258.400** no Codex via ACP. O rodapé mostra
  proporção, não número absoluto sozinho.
- **Não sabemos** se `cost.amount` é do turno ou acumulado da sessão — o turno de dois prompts que
  responderia isso nunca executou (a `claude-4` está com credencial expirada). O chip soma por
  turno **assumindo custo-por-turno**, e isso fica **declarado como suposição a verificar**, não
  como fato.

## §3 O steer que para de mentir

O rótulo e o texto de apoio saem de `aceita`:

| `aceita` | botão | placeholder |
|---|---|---|
| `Redireciona` | **GUIAR** | "guiar o turno em curso…" |
| `Enfileira` | **ENFILEIRAR** | "enfileirar para depois deste…" |
| `SomenteLeitura` | *(sem botão)* | *(sem caixa)* |

Função **pura**, para ser assertável sem UI:

```swift
/// O rótulo do gesto de guiar, derivado do que a lane aceita.
/// 🚨 Um botão que diz GUIAR numa lane que ENFILEIRA mente no momento da decisão — pior que
/// contar depois, porque o operador já agiu.
public static func rotuloDeGuiar(_ aceita: Aceita) -> String
```

## §4 A lane de leitura, e o que ela mostra no lugar

Em `SomenteLeitura` a caixa de prompt e os botões **não existem** — não desabilitados, ausentes.
Controle morto sem explicação é o defeito que esta casa já pagou para aprender. No lugar, uma linha
que diz **o que a lane é e onde falar com ela**:

> 👁 observada pelo transcript — fale com ela pelo terminal

Isso é honesto e acionável: a lane está viva, o loomd a lê, e o caminho para dirigi-la existe (o
terminal), só não é aqui.

## §5 O acabamento que faz virar "chat"

Quatro coisas, todas sobre o que já desenha. **A Sessão não é reescrita.**

1. **Ferramenta recolhida por padrão**, expansível. Hoje o cabeçalho do turno conta ferramentas e o
   corpo lista todas abertas — o inverso do que faz uma conversa ser legível.
2. **Diff inline com aceitar/rejeitar no lugar**, em vez de patch cru. O diff já vem pronto do
   protocolo; o que falta é a afordância ao lado dele.
3. **Rodapé do turno**: `duração · contexto · USD` (§2).
4. **Erro de protocolo visível.** O `Kind::Error` que passou a existir hoje (resposta de `error` do
   JSON-RPC, antes engolida) precisa cair em `case .failure`. Se não cair, continua invisível na
   tela **estando no diário** — que é a metade pior de "o diário não mente".

## §6 Testes

**Lado Rust** — inline, em `crates/loomd`, como as 89 existentes:

| função | o que prende |
|---|---|
| `aceita_da_lane(codex, acp, tails, lane)` | mesma lane em dois conjuntos já é recusada pela guarda existente; cada conjunto dá a variante certa |
| serialização de `Aceita` | `/v2/state` carrega `aceita: "somente_leitura"` para lane de tail |

**Lado Swift** — em `BeagleCoreTests`, que já existe e roda por `swift test`:

| função | o que prende |
|---|---|
| `rotuloDeGuiar(_:)` | `Enfileira` → "ENFILEIRAR"; `Redireciona` → "GUIAR" |
| decodificação de `LaneSnapshot` | `aceita` vem do JSON; **não** é derivado de `sid` |
| `UsoDoTurno` a partir de passos | pega o **último com custo**, não a soma; contexto é o último valor |
| `SessionStore.passo(de:)` | `kind: "error"` → `.failure`; `kind: "usage"` → `.uso` |

**Mutações obrigatórias**, e o vermelho tem de vir de **asserção** — vermelho por não compilar
prova que o compilador cobra algo, não que o teste pega o defeito:

1. `rotuloDeGuiar` devolvendo "GUIAR" para tudo → vermelho *(é a mentira que a fatia existe para matar)*
2. `aceita` derivado de `LaneFamily.of(sid)` em vez do JSON → o teste de `claude-1` vs `claude-4` fica vermelho
3. `UsoDoTurno` **somando** os custos em vez de pegar o último → vermelho
4. `kind: "error"` voltando a cair em `nil` → vermelho

**Prova ao vivo:** na Sessão de `claude-4`, um turno mostra rodapé com USD real; o chip mostra o
acumulado e os dois **concordam**; em `claude-1` não há caixa de prompt, e há a linha de
observação; e o botão diz **ENFILEIRAR** na `claude-4` e **GUIAR** na `codex-4`.

## Riscos

- **Duas telas com o mesmo número** podem divergir. Mitigado por fonte única (`Turno.uso`), e o
  teste de concordância é parte da prova ao vivo.
- **`cost.amount` pode ser acumulado da sessão**, não do turno. Se for, o chip vai somar duas vezes.
  Declarado como suposição; a verificação exige a `claude-4` executando turno, o que hoje está
  bloqueado por credencial expirada.
- **O fonte do Mac é o vivo**, e diverge do t560. A branch `mac/integration-mission-control-ui` foi
  buscada para o t560 em 11-ago; qualquer trabalho tem de sair de lá, nunca da cópia velha.
- **Rótulo honesto no botão não impede erro de outra origem**: a rota ainda pode falhar. O `efeito`
  na resposta segue existindo como confirmação.

## Fora de escopo

- `loomd` como autoridade de IDE — [spec própria](2026-08-11-loomd-como-ide-design.md), pronta.
- Transporte do ACP pelo crate `agent-client-protocol` e migração do `codex.rs`.
- Consertar a credencial da `claude-4` — operacional, não de código.
- Reescrever a Sessão, trocar o layout, ou tocar na aba Terminais.

## Resultado — 11-ago-2026

### Provado

**O campo chega, medido nas 6 lanes de produção.** `/v2/state` do `loomd` em
`sounio-workspace-control-0:4400`:

```
claude-1/2/3  aceita=somente_leitura     codex-4, loom-1  aceita=redireciona
claude-4      aceita=enfileira           usd numérico em 6/6, confidence=exact
```

**A cadeia inteira, exercitada contra o código deployado.** O app não fala com o `loomd`: o caminho é
`app → cockpit (/ws/loom) → loomd:4400`. Rodei `loomdCard` e `fuseFleet` **dentro do pod do cockpit
já atualizado** (imagem `aceita-e08f362e`), alimentados com o `/v2/state` real: `aceita` presente em
6/6 e `usd` numérico em 6/6 após a fusão.

**Testes.** `loomd` 102 verdes (era 92); cockpit 299 (era 291, com uma falha pré-existente e alheia em
`fetchSounioState`); `beagle-ios` 120 XCTest + 147 Swift Testing. Cada asserção nova foi validada por
**mutação com vermelho por asserção** — vermelho por erro de compilação foi recusado como prova.

**App instalado com prova de frescor**: `pid=4652 build=202608112159 janelas=1`, sem abortar — o
script compara o início do processo com o mtime do binário justamente porque, em 10-ago, três rodadas
de conserto foram testadas num build antigo.

### Dois defeitos que só a execução real revelou

Ambos da mesma família: **o sistema sabia e a tela não recebia.**

1. **Ordem, no `loomd`.** `Trama::open` **rehidrata** as lanes do diário; `declarar_com` usava
   `or_insert_with`, que só age em chave inexistente. Com diário cheio, a declaração era
   silenciosamente inútil e as 6 lanes vinham `aceita: None`. O teste de fumaça passou porque a trama
   estava **vazia**. Conserto: `and_modify` tocando **só** o campo `aceita` — recriar a `LaneState`
   zeraria o custo acumulado, que sobrevive de propósito ao respawn do filho.

2. **A camada Node comia os campos.** `loomdCard` monta o card campo a campo e `fuseFleet` copia uma
   **lista explícita**; nenhuma das duas incluía `aceita` nem `usd`. Servidor certo, app certo, tela
   cega — num arquivo cujo próprio comentário avisa que o patch de lane única é onde um campo novo
   passa a aparecer "só às vezes".

E dentro do segundo conserto, uma assimetria que quase passou: no ramo sem fonte exata, `aceita: null`
está certo (capacidade é afirmação sobre o **presente** e pode ter mudado; não saber empurra a tela
para o lado seguro), mas `usd: 0` estava errado — custo é **fato cumulativo do passado**, e zerar faz
a tela afirmar "esta lane não custou nada" quando ela só perdeu quem confirmava o gasto. Como o chip
esconde zero, o número desapareceria no campo que decide se se para uma lane cara. Agora congela o
último valor conhecido.

### Não provado, e por quê

- **Rodapé com USD num turno real** (critério 4): a `claude-4` está com **credencial expirada** —
  prompts entram na trama e o turno não executa. Não declarado provado por inspeção de código.
- **A concordância chip ↔ rodapé** (critério 5) depende do mesmo turno: com `usd = 0` em todas as
  lanes, os dois concordam trivialmente, o que não é prova.
- **Os rótulos na tela** (critérios 1–3) estão provados como **função pura** (`rotuloDeGuiar`,
  `dicaDaCaixa`, `semCaixa`) e o dado que os alimenta chega. A afirmação visual em si não foi
  asserida: a introspecção por acessibilidade não expõe o conteúdo SwiftUI.

### Suposição declarada, ainda aberta

`cost.amount` é tratado como custo **do turno**. Se for acumulado da sessão, o total soma duas vezes.
Verificar exige um turno de dois prompts na `claude-4` — bloqueado pela mesma credencial.

### Dívidas registradas

- `isAbsent` deduz capacidade de **prosa** em português. Deliberadamente não tocado: a frase vem do
  `LanePoller` do project-cockpit, não do `loomd`.
- A `SessionView` não tem referência reativa ao cliente de estado: socket morto congela o `aceita` sem
  sinal visual, e silêncio de transporte é lido como silêncio do agente.
- O chip de custo não herda `isStale`/`confidence`, e o congelamento do `usd` cria um dado que pode
  ser velho **por construção**, sem prazo visível.
- O painel `tmux` chamado `loomd` ainda carrega a configuração **antiga** (só `loom-1,codex-4`, sem
  lanes ACP e sem tails). O processo vivo subiu por `subir-loomd.sh`, que tem a configuração completa;
  religar pelo painel traria a frota mutilada.
- Havia **quatro** `loomd` vivos, três deles de teste, supervisionando `claude-4` e `codex-4` — as
  mesmas lanes da produção, na mesma worktree. Candidato concreto às lanes caindo ao longo do dia.
  Agora há um só.
