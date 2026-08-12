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

### Estado das ligações

| componente | nodeId | ligado | template |
|---|---|---|---|
| Compositor da Sessão → `SessionView` | `6:28` | ✅ nas 5 variantes | ❌ `hasTemplate: false` |
| Chip de Lane → `LaneCard` | `10:44` | ❌ | template pronto |
| Rodapé do Turno → `rodapeDoTurno` | `11:23` | ❌ | template pronto |

**Dois cliques na UI destravam o resto** — nenhum deles tem API:

1. **Republicar a biblioteca.** O Chip e o Rodapé foram criados **depois** da primeira publicação,
   então `send_code_connect_mappings` recusa os dois com *"Published component not found"*.
2. **Desconectar o Code Connect do Compositor.** A primeira tentativa registrou mapeamento
   **simples** (sem trecho de código) por erro meu — usei `figma.currentInstance` e omiti o
   `import figma from 'figma'`, quando a API é `figma.selectedInstance`. Os dois caminhos de
   escrita agora recusam com *"already mapped… disconnect the existing mapping in the Figma UI
   first"*.

Feito isso, os três templates deste diretório sobem numa chamada e o Dev Mode passa a mostrar o
`SessionView(...)` real por variante, em vez de só o caminho do arquivo.

## O que funciona no Pro, e onde o contrato vive hoje

| Onde | O quê | Gate de plano? |
|---|---|---|
| Descrição do conjunto e de cada variante no Figma | símbolo Swift, arquivo e linha de cada decisão | não |
| `codeSyntax` iOS nas 40 variáveis | `BeagleTheme.truthObserved`, `BeagleSpacing.md`, … | leitura plena no Dev Mode é gated |
| Este diretório | template pronto para publicar | não |

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

Pendente: página de Tipo & Medida, Chip de Lane (com o limiar `< US$ 0,01`), rodapé do turno (com
`< 1%`), capa.
