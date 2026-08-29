# ⚠️ ESTA BANCADA TESTOU O CIRCUMPLEXO, NÃO A HIPÓTESE SEDENIÔNICA

**Leia isto antes de citar qualquer número daqui.**

O que está medido abaixo é o **circumplexo de Russell** — valência × ativação como par de
escalares em ℝ². Não é o conceito do pesquisador, e é literalmente a arte prévia que ele não
pode reivindicar. Eu construí e rodei esta bancada supondo que "vetor de emoção" significasse o
par de escalares padrão. Não significa.

O conceito é: **afeto e acoplamento vivendo num espaço de estados sedeniônico**, onde a composição
é o PRODUTO de 𝕊 e `a·b = 0` com a,b ≠ 0 é aniquilação — o acoplamento que não ocorre. Em ℝ² não
há produto, logo o fenômeno de interesse não é sequer representável, e por isso esta bancada nunca
poderia achá-lo. Ver `docs/PREREG_PSI_SEDENIONICO_v1.md` (SHA-256
`005df7bd2b3362c1e62ab7d3728cadb6cec31196f1c3d0f30b1ad93cad795f19`).

**O que os números abaixo VALEM:** são uma refutação do circumplexo *neste sistema* — a valência,
como entregue hoje, não desloca a fala. Isso é um fato sobre o produto em produção e continua
verdadeiro.

**O que eles NÃO valem:** não dizem nada sobre a hipótese sedeniônica. Nem a favor, nem contra.

A varredura 2D (`varre-vetor.sh`, braços descritivo/diretivo) foi **abandonada em curso**, com 3
de 36 respostas, pelo mesmo motivo: estava medindo a versão errada do objeto.

---

# O circumplexo dirige a fala, ou só está no prompt?

Bancada montada em 28-ago-2026, a pedido dele: *"o desafio aqui é a minha fronteira de novelty…
conseguir expressar os vetores de emoção"*.

A pergunta não é retórica. No mesmo dia ficou medido que a `PERSONAL_PERSONA` **pedia**
discordância e obtinha zero em 166 respostas, e **pedia** concisão e produzia 6.742 caracteres.
Pedir não é obter. Uma alegação de que um vetor de afeto *dirige* a voz precisa da prova que a
persona não passou.

## O que existe hoje no sistema (lido, não suposto)

Não há vetor. Em `apps/project-cockpit/server/temporal-context.mjs`, `stateOfMindPtBR` colapsa a
valência (−1..1) em **cinco faixas** e devolve um adjetivo; havendo rótulo, o rótulo tem
preferência e a valência vira "textura". **Ativação não entra em lugar nenhum** deste caminho.
O que chega ao modelo é uma linha de texto dentro do bloco `## Agora`.

## Os dois testes

`varre-valencia.sh <saida> [reps]` — varre a valência mantendo tudo o mais congelado (fala, hora,
FC, HRV, sono) e grava as respostas cruas. Usa `probe: true`: exercita roteamento, aterramento e
portão de fala **sem gravar nada no corpus dele**. Sem isso, cada rodada plantaria auto-relatos
que ele nunca fez — que é exatamente o que a Fase 2 mede.

`mede-deslocamento.py <saida>` — três medidas, da mais fraca à mais forte:
1. **papagaio**: a resposta só repete o adjetivo da faixa?
2. **divergência** léxica entre valências, contra o piso de ruído das repetições da MESMA
   valência. Sem esse piso o número é indefensável: o modelo varia sozinho a cada chamada.
3. **monotonicidade**: a divergência cresce com |Δvalência|? Um eixo produz vizinhança.

`recuperacao-cega.sh <saida>` — o teste forte, imune à cegueira do léxico a TOM: um juiz que só
vê o texto tenta recuperar a valência. Juiz = `llamacpp-l4` do cluster (modelo puro, sem persona,
sem aterramento, sem captura). Ordem embaralhada com semente fixa, para ser repetível.

## Resultado (n=18 respostas, 3 repetições por valência)

| | |
|---|---|
| divergência entre valências diferentes | 0,732 |
| divergência entre repetições da mesma valência (ruído) | 0,736 |
| **efeito acima do ruído** | **−0,004** |
| correlação(\|Δvalência\|, divergência) | **+0,027** |
| recuperação cega | **4/15 = 27%** (acaso 20%; **p = 0,352**) |

O modelo varia mais consigo mesmo do que ao percorrer toda a escala. A correlação nula é a medida
que mais pesa: se a valência fosse um eixo, −0,8 estaria mais perto de −0,3 do que de +0,8. Não
está. E o juiz cego não recupera nada — 27% contra 20% de acaso é indistinguível do acaso.

**Veredito: a valência não desloca a fala. São cinco baldes rotulados, e o único efeito
mensurável é o adjetivo da faixa reaparecer no texto (7 de 15).**

## Limites, declarados

n pequeno (18 respostas, 15 no teste cego). O piso de ruído é altíssimo (0,736), então um efeito
sutil de tom poderia se esconder sob ele — é justamente por isso que existe o teste cego, que não
depende do léxico. A varredura foi de valência apenas: **ativação não foi testada porque não
existe no caminho**. E o juiz é um 14B local; um juiz mais forte poderia achar sinal que este não
acha, o que reforçaria o achado só se achasse.

## Por que isto importa para a fronteira de novidade

A alegação "voz dirigida por vetor de emoção" **hoje é falsa neste sistema**, e a bancada acima é
o que a torna verificável em vez de asseverável. Qualquer contribuição nessa direção precisa
passar por aqui primeiro — e um resultado nulo com método congelado vale mais que um efeito
alegado sem piso de ruído.

⚠️ Nota para quem for construir o vetor de verdade: valência e ativação **são correlacionadas**.
Compor incerteza sobre elas em quadratura publica limites mais apertados que a verdade — é o
defeito que a Fase 1 conserta em `graded_effects.sio`. Um vetor de afeto com barras de incerteza
só é defensável com aquele conserto junto.
