# Sistema de design do Companion no Figma

Arquivo: <https://www.figma.com/design/dgN7JrAPdQnvKzccdBrlW5>
(“Beagle Companion — sistema e telas”. Arquivo **próprio**, sem interseção com o que o Codex usa.)

## O princípio

Nada aqui foi desenhado por cima do app. Cada cor, medida e tamanho de tipo foi
**extraído de** `BeagleSuite/Sources/BeagleCore/Theme.swift` e conferido valor a
valor. Se o Figma e o código discordarem, o código ganha — e o Figma está errado.

Cada variável carrega o acessor Swift real no `code syntax` (iOS), então o Dev Mode
mostra `BeagleTheme.truthObserved`, não um hexadecimal solto.

## O que existe

| Camada | Conteúdo |
|---|---|
| Variáveis (coleção `Beagle`, modos Claro/Escuro) | 12 cores + 5 tintas + 11 números de espaço/raio |
| Estilos de texto | os 15 casos de `BeagleFont`, em SF Pro (o mono é IBM Plex Mono — SF Mono não existe no Figma) |
| Componentes | Selo de verdade (4 variantes) · Fala (2) · Linha de dado · Faixa de estado · Campo de entrada (2) |
| Telas | Conversa, montada com instâncias, nos dois modos |

## Duas decisões que valem registrar

**A fala dele não é balão.** É carta: largura cheia, entrelinha 145%, sem moldura.
O balão é do usuário, encostado à direita. A assimetria é o ponto — quem fala com
você não fica dentro de uma caixa.

**Alpha mora na variável, nunca no paint.** `createInstance()` do Figma **descarta a
opacidade do paint**: o componente-mestre fica a 14% e toda instância nasce sólida.
Foi medido, não suposto (mestre `op: 0.14`, instância `op: 1`). Por isso existem
`verdade/*-fundo` e `marca/âmbar-fundo`, com a alpha dentro do valor da variável.
Quem for criar um componente tingido daqui pra frente: use essas, não opacidade de
paint.

## Code Connect — pronto, mas não publicado

Os templates `*.figma.ts` deste diretório emitem **SwiftUI** e apontam para as views
que já existem:

| Figma | Swift |
|---|---|
| Selo de verdade | `BeagleCore/Components.swift` → `TruthBadge` |
| Fala | `BeagleCockpit/Companion/MessageBubble.swift` |
| Campo de entrada | `BeagleCockpit/Companion/ChatComposer.swift` |

`send_code_connect_mappings` recusou os três com **“Published component not
found”**. Não é erro dos templates: o arquivo está na pasta de **Rascunhos** e o
Code Connect só liga a componentes **publicados numa biblioteca de equipe**.

Para destravar: mover o arquivo dos Rascunhos para um projeto de equipe e publicar
a biblioteca. Depois disso os três mapeamentos sobem sem alteração.

`Linha de dado` e `Faixa de estado` **não têm** contraparte Swift ainda — foram
desenhadas a partir do contrato de UI (`companion-ui-design/SCREEN_MAP.md`), que as
decide mas nunca as construiu. Não há mapeamento para elas porque não seria verdade.

---

# A presença — linguagem visual

A primeira versão deste sistema era correta e feia. O motivo não foi gosto: eu
desenhei a tela **sem a presença**. O app tem o cão primordial em vídeo e a
`AuroraPresence` por trás do chat; as minhas telas tinham fundo chapado com texto
por cima. Tirei a matéria viva e deixei o esqueleto tipográfico.

A página `Presença` do arquivo tem a versão refeita, composta com o pôster real
(`Resources/Presence/lp-madrugada.png`).

## Como a tela é montada, de baixo para cima

| Camada | O que faz |
|---|---|
| fundo `#070608` | Quase-preto com azul. Preto puro em OLED “some” e mata a profundidade. |
| `brasa` | Três radiais em `SCREEN` centradas no coração do cão (0.52, 0.34). Luz que soma, não cor que cobre. |
| `presença viva` | Grupo mascarado: o pôster em `SCREEN` + máscara de alfa vertical. |
| `vinheta` | Radial larga em `MULTIPLY`, queda longa. Fecha a borda sem desenhar anel. |
| `escurecimento` | Rampa linear só na metade de baixo — onde há texto a proteger. |
| `fala` | Carta, 19pt, entrelinha 150%. Sem moldura, sem vidro. |
| `entrada` | Efeito `GLASS` nativo. Camada flutuante — o único lugar onde vidro é permitido. |
| grão | `NOISE` monotônico na moldura. Sem ele, gradiente escuro em OLED vira faixa. |

Paleta da presença lida do próprio pôster, **não** do tema: `#FF6A33` fogo,
`#FF9A5A` brasa, `#8C2A18` profundo. A presença é mais quente que a marca.

## Plugin API — o que é aceito de verdade

A tipagem publicada e o validador **discordam**. Medido contra o validador:

- Efeitos aceitos: `DROP_SHADOW`, `INNER_SHADOW`, `LAYER_BLUR`/`BACKGROUND_BLUR`
  (`blurType: 'NORMAL' | 'PROGRESSIVE'`), `NOISE` (`MONOTONE`/`DUOTONE`/`MULTITONE`),
  `TEXTURE`, `GLASS`, `SHADER`.
- `NOISE` **rejeita** `blendMode`, embora a tipagem o declare.
- `GLASS` exige `radius` **além de** `refraction`, `depth`, `lightIntensity`,
  `lightAngle`, `dispersion`.
- Blur progressivo aceita `startRadius`/`startOffset`/`endOffset` — mas **não**
  `endRadius`; a amplitude vai em `radius`.
- Os shaders da biblioteca da conta (`list_shader_fills` / `list_shader_effects`
  do MCP) **não** são importáveis pelos ids do MCP: `importShaderById` só aceita
  ids de `figma.listAvailableShaders()`, que volta vazio até os shaders serem
  adicionados ao arquivo pela interface. **Bloqueio pendente** — destravar dá
  acesso a Bloom, Nebula, Pattern refraction (IOR + frost), Gradient map em OKLab
  e Dither com blue noise.

## Três armadilhas que custaram iterações

1. **Máscara é a camada de BAIXO.** `figma.group([mascara, cao])` não garante
   z-order; a máscara tem que ir para o índice 0 do grupo, senão ela não mascara
   nada e o retângulo do pôster aparece inteiro, com costura visível nas bordas.
2. **Arte emissiva sobre preto pede `SCREEN`.** O preto dela desaparece e as
   costuras somem sozinhas.
3. **Não use `MULTIPLY` para “apagar” borda.** Esmagar para preto puro deixa a
   região mais escura que o fundo do frame — cria exatamente a borda que se queria
   remover. Alfa é trabalho de máscara, não de cor.

## O que a pesquisa mudou (iOS 26)

- **Vidro pertence à camada flutuante de navegação.** Nunca na camada de conteúdo,
  nunca vidro sobre vidro. Balão de fala e linha clínica ficam em preenchimento e
  vibrância; o campo de entrada é a superfície de vidro legítima.
- Duas variantes apenas: **Regular** e **Clear**. Clear só sobre conteúdo rico em
  mídia **com camada de escurecimento explícita** — que é o caso desta tela.
- **`TextRenderer` + `TextAttribute`** (iOS 18+) resolve prosa íntima e valor
  clínico monoespaçado **dentro do mesmo `Text`**; um renderer `Animatable` por
  `elapsedTime` é a revelação do streaming.
- `GlassEffectContainer` com `spacing` é o botão concreto de fusão orgânica;
  `glassEffectID` + `@Namespace` faz a metamorfose entre estados.
- **Shader em tela cheia NÃO é gratuito** — a alegação de viabilidade universal foi
  refutada 3-0. O orçamento é o prazo do quadro, medível no Instruments 26.
