# Figma ↔ código — Mission Control

Arquivo de design: **[Beagle Mission Control — Sovereign Dark](https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7)**
Fonte de verdade dos tokens: `beagle-ios/BeagleSuite/Sources/BeagleCore/Theme.swift`

## 🚫 Code Connect está bloqueado — e não é contornável por código

Medido em 11-ago-2026 contra a conta real:

```
whoami                        → tier: "pro",  seat: "Full"
get_code_connect_suggestions  → "You need a Dev or Full seat on an Organization or
add_code_connect_map            Enterprise plan to use Code Connect."
```

Os **três** endpoints falham — `get_code_connect_suggestions`, `add_code_connect_map` e
`list_file_components_for_code_connect`. Code Connect exige **Organization ou Enterprise**; `Pro`
não basta, mesmo com assento `Full`.

### A hipótese de escopo de token foi ELIMINADA (12-ago-2026)

Havia uma ressalva honesta em aberto: se a equipe vivesse **dentro** de uma organização e o token
OAuth alcançasse só a equipe, o gate seria do token e não da conta. **Testado e descartado.**

O plugin oficial da Figma traz um **segundo servidor MCP, com autenticação própria e independente**.
Fizemos um login OAuth novo do zero (com túnel reverso, porque o `redirect_uri` aponta para o
`localhost` da máquina onde o Claude Code roda, não a do navegador). Resultado idêntico:

```
servidor A (claude.ai Figma)   whoami → team::1654179493326852903  tier: pro  seat: Full
servidor B (plugin oficial)    whoami → team::1654179493326852903  tier: pro  seat: Full
                               get_code_connect_suggestions → mesmo erro de plano
```

Duas autenticações independentes reportam **um único plano**, e ele é uma **equipe Pro** — não uma
organização (o prefixo é `team::`, não `organization::`). Nem o plugin oficial nem o DesignAgent
contornam: os dois atuam do lado do **cliente**, e o gate é do **servidor**. Só o upgrade resolve.

### ✅ Publicação: feita (12-ago-2026)

A biblioteca **está publicada** — o outro pré-requisito do Code Connect está cumprido, confirmado por
`search_design_system`, que só devolve o que está publicado:

```
library : Beagle Mission Control — Sovereign Dark
libKey  : lk-94e81045d9910ce0cfa35536cef023f96b92c3cb...
compKey : 190a94d7e57f9c21ab47ea59e687b5593ec03e17   (component_set "Compositor da Sessão")
varSet  : 3585feff430e0c4534032cf8636ac87a2d9951f6   (coleção "Cor")
```

Ou seja: **falta só o plano.** `list_file_components_for_code_connect` nem chega a olhar a
publicação — o gate de plano barra antes dele.

`CompositorDaSessao.figma.ts` existe para que o mapeamento **não se perca e possa ser revisado
agora**. No dia em que o plano subir, ele publica sem reescrita.

## O que funciona no Pro, e onde o contrato vive hoje

| Onde | O quê | Gate de plano? |
|---|---|---|
| Descrição do conjunto e de cada variante no Figma | símbolo Swift, arquivo e linha de cada decisão | não |
| `codeSyntax` iOS nas 40 variáveis | `BeagleTheme.truthObserved`, `BeagleSpacing.md`, … | leitura plena no Dev Mode é gated |
| Este diretório | template pronto para publicar | não |

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
