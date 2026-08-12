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
