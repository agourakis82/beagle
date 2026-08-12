# Figma ↔ código — Mission Control

Arquivo de design: **[Beagle Mission Control — Sovereign Dark](https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7)**
Fonte de verdade dos tokens: `beagle-ios/BeagleSuite/Sources/BeagleCore/Theme.swift`

## ✅ Code Connect está ATIVO (12-ago-2026)

O upgrade de plano destravou. A conta passou de equipe Pro para **organização**:

```
antes  →  team::1654179493326852903          tier: pro   (dois logins independentes confirmaram)
depois →  organization::1669203848746358212  tier: org   name: "Beagle"
```

O gate era mesmo de plano — nem escopo de token (testado com um segundo servidor MCP e
autenticação própria), nem falta de publicação (`list_file_components_for_code_connect` falhava
antes de olhar a publicação). Registro fica aqui porque o caminho até a conclusão é a parte útil:
**três endpoints medidos**, uma hipótese levantada e **eliminada por experimento**, e só então o
upgrade.

### Estado das ligações: os TRÊS ligados com template (12-ago-2026)

| componente | nodeId | ligado | template |
|---|---|---|---|
| Compositor da Sessão → `SessionView` | `6:28` | ✅ 5 variantes | ✅ snippet por variante |
| Chip de Lane → `LaneCard` | `10:44` | ✅ 5 variantes | ✅ |
| Rodapé do Turno → `SessionStore.rodapeDoTurno` | `11:23` | ✅ 5 variantes | ✅ |

No Dev Mode, cada variante mostra o `SessionView(...)` real com o `aceita` daquele estado —
`.redireciona`, `.enfileira`, `.somenteLeitura`, `nil` com link vivo, `nil` com
`.insistindo(motivo:tentativas:)`. Verificado por `get_code_connect_map`: `hasTemplate: true` nas
cinco, com o snippet renderizado.

### Como publicar (o que funcionou, e por quê a API não bastava)

A API MCP (`add_code_connect_map` / `send_code_connect_mappings`) **aceita** o campo `template` e
responde `success: true`, mas o template **não gruda** — `hasTemplate` fica `false` e só a referência
ao arquivo é registrada. Templates parserless sobem pelo **CLI oficial**:

```bash
cd beagle-ios/figma
npm install --no-save @figma/code-connect          # 1.5.2; node_modules é git-ignored
FIGMA_ACCESS_TOKEN="$(tr -d '[:space:]' < ~/.config/figma/token)"   npx figma connect publish --force --skip-update-check
```

Três coisas que só se descobrem lendo o pacote, não a documentação:

1. **Parserless se ativa OMITINDO a chave `parser`** — `CodeConnectParserlessConfig =
   BaseCodeConnectConfig & { parser: undefined }` (`dist/connect/project.d.ts`). Com um `parser`
   qualquer, o CLI tenta o parser nativo e ignora os templates.
2. O CLI reconhece template cru pelos diretivos **`// url=`, `// component=`, `// source=`** no
   cabeçalho (`dist/connect/raw_templates.d.ts` → `isRawTemplate`).
3. **`--dry-run` roda sem token** — valida parse, rótulo e a lista do que subiria antes de a
   credencial existir. Foi assim que a configuração ficou provada antes de pedir o token.

**`--force` é necessário se houver mapeamento criado pela UI/API** para o mesmo rótulo: o CLI avisa
`Warning: N node(s) already have UI-created Code Connect mappings` e não sobrescreve sem ele.

O token é um Personal Access Token (escopos Code Connect + File content), gravado em
`~/.config/figma/token` com permissão `600` no t560. Para revogar: Figma → Settings → Security →
Personal access tokens.

## Separador decimal do dinheiro — consertado (12-ago-2026)

O Figma renderizado expôs um defeito que a leitura do código só sugeria: `< US$ 0,01` (vírgula,
literal) aparecia na **mesma coluna** que `US$ 12.35` (ponto, de `String(format:)`, que é insensível
a locale). O app é inteiramente em pt-BR — a vírgula era a forma certa e os pontos eram o defeito.

Consertado em `SessionStore.swift` (Mac `1bfea9f7`): um helper único com `NumberFormatter` e locale
**explícito `pt_BR`** — nunca `Locale.current`, que faria o mesmo teste passar numa máquina e falhar
noutra. O limiar passou a ser **derivado** do helper em vez de literal, então não pode mais divergir.
Agrupamento de milhar ligado (`US$ 1.234,56`), e o teste de consistência olha o **último** separador
— porque em pt-BR o ponto é separador de milhar legítimo e proibir todo ponto proibiria o acerto
junto com o erro.

Duas descobertas do conserto que valem mais que ele:

- **O teste tolerante era o que deixava o defeito viver.** Três asserções usavam
  `contains("12.35") || contains("12,35")` — escritas para passar de qualquer jeito, nunca poderiam
  pegar a inconsistência. Agora exigem a vírgula e **proíbem** o ponto.
- **Uma mutação foi declarada inválida em vez de forjada.** Trocar o locale explícito por
  `Locale.current` **não** derrubou nada, porque este Mac está em `pt_BR` — o implementador disse
  isso e substituiu por forçar `en_US`, que prova a mesma coisa. Mutação que passa não é mutação.

Os componentes do Figma foram atualizados para as strings novas: o desenho não pode mostrar o que o
app já não mostra.

## Substituições de fonte — declaradas, não escondidas

O Figma **não** renderiza a face do app. As duas trocas estão na descrição de cada estilo:

- **`SF Pro`** — ✅ **RESOLVIDO em 11-ago-2026.** Antes de o Figma Desktop ser instalado no Mac, a
  família era **listada** e `loadFontAsync` **não** reclamava, mas as glifos mediam **largura zero**:
  inutilizável, e tudo saía invisível. Com o desktop instalado ela passou a medir (283 px numa
  string de teste) e a rampa de UI voltou para **SF Pro**, a face real do app. A substituição por
  Inter foi desfeita e o aviso removido dos 12 estilos — aviso que deixou de valer vira mentira na
  direção oposta.
- **`SF Mono`** — ❌ **continua ausente**, mesmo com o Figma Desktop instalado. A rampa de dado usa
  **JetBrains Mono**. Monospace aqui não é estética: o sistema reserva monoespaçada para **dado**
  (número, medida, identificador). `SF Compact` também é listada e também mede zero.

## Armadilha que já custou duas rodadas

`figma.createAutoLayout()` nasce com preenchimento **branco**. Invisível no tema claro, bloco opaco
no escuro — e só aparece quando se valida no tema em que o app roda. Sempre limpar `fills` nos
contêineres intermediários, deixando superfície apenas onde ela é intencional.

## Estado

Ledger com todos os IDs: `$CLAUDE_JOB_DIR/tmp/design-system-state-beagle-mc-2026-08-11.json`

Feito: fundações de cor (26 tokens, modos Claro/Escuro, semânticos por **alias**), medidas (grid de
8 + 5 raios), 15 estilos de texto, página de fundações de cor nos dois modos, e o conjunto
**Compositor da Sessão** com os 5 estados.

**Completo.** Capa, Fundações de Cor (dois modos lado a lado), Fundações de Tipo & Medida (o
especímen APLICA os 15 estilos, e as barras/raios têm largura e canto LIGADOS às variáveis), e os
três conjuntos de variantes — Compositor da Sessão, Chip de Lane, Rodapé do Turno — todos com Code
Connect e snippet por variante.

### Armadilhas do Plugin API que já custaram rodadas aqui

| sintoma | causa |
|---|---|
| bloco branco no escuro, invisível no claro | `figma.createAutoLayout()` nasce com fill **branco** |
| `setBoundVariable` recusa em `fills`/`strokes` | binding de cor vai no **paint**: `setBoundVariableForPaint` devolve paint **novo** |
| texto cortado depois da 2ª linha | `resize()` **reverte** `textAutoResize` para `FIXED` — chame `resize` **antes** |
| `FILL can only be set on children of auto-layout frames` | o **pai** tem de ser auto-layout; `createFrame` simples não serve |
| glifos invisíveis, `width == 0` | fonte listada mas não renderizável — **medir `t.width > 0`** depois de escrever |

## Dívidas quitadas — 12-ago-2026

**`turns` da lane ACP reportava 0 para sempre.** Medido no diário: `claude-4` tinha **7**
`user_prompt` e **zero** `turn_started`, e o contador só olhava `TurnStarted` — que lane ACP nunca
emite. O operador mandara sete pedidos e a tela dizia zero. A regra ingênua (contar em
`TurnStarted | UserPrompt`) **dobraria** nas lanes de codex, que emitem os dois adjacentes; o
conserto **adapta ao vocabulário da lane** — se ela já emitiu `TurnStarted`, conta por ele; se nunca,
conta por `UserPrompt` — com uma guarda para o caso em que um `UserPrompt` chega **antes** do primeiro
`TurnStarted` e o turno seria contado duas vezes. t560 `9ec1c3e6`, 110 testes, 3 mutações vermelhas
por asserção.

**Provado ao vivo** depois do rebuild: `claude-4` foi de `turns: 0` para `turns: 7`, e `codex-4` (1) e
`loom-1` (14) não se moveram.

**O chip de custo não marcava dado velho.** Era, nas palavras da review, *"o número mais perigoso de
estar errado sem aviso"* — e ficou pior quando o servidor passou a **congelar** o último custo ao
perder a fonte exata: o valor podia estar velho **por construção**, sem prazo. Agora o chip marca, a
decisão sai de função pura, e o rótulo de acessibilidade fala a idade. Mac `73926bfa`, 178 XCTest, 3
mutações vermelhas por asserção.

A marca escolhida foi o sufixo **`· antigo`** mais a laranja que o `observationAge` já usa duas linhas
acima — e o implementador **recusou** minha sugestão de usar `BeagleTheme.truthStale`, com medição:
sobre este vidro escuro ele fica *mais apagado* que o branco a 60%, o que deixaria o número **menos**
legível em vez de mais suspeito. Opacidade menor não é sinal; é ruído mais fraco.

Segue aberta apenas a dívida do `isAbsent`, que deduz capacidade de **prosa** em português — e a frase
vem do `LanePoller` do project-cockpit (Node), não do `loomd`, então consertar é outra fatia.
