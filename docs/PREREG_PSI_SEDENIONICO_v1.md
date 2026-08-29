# Pré-registro — ψ: o embedding sedeniônico do afeto (v1)

**Estado: CONGELADO por SHA-256 antes de qualquer olhada no dado.**
Qualquer alteração é uma **v2**, publicada ao lado; a v1 permanece no registro. Não se edita.

## 0. Por que este documento existe

Sem um ψ fixado antes da coleta, a hipótese sedeniônica é infalsificável: 𝕊 tem 15 dimensões
imaginárias, o gauge é Aut(𝕊) ≅ G₂ × S₃, e um relato afetivo ordinal e ruidoso tem 2 a 5
dimensões efetivas. Qualquer resultado seria absorvível por reparametrização. Este documento
fixa o mapeamento e as predições **antes** de qualquer análise.

## 1. O modelo

O estado afetivo instantâneo é um elemento de 𝕊 ≅ ℝ¹⁶ com o produto de Cayley–Dickson.
**A composição de estados é o PRODUTO, não a soma.**

A díade é o objeto: *a* = estado afetivo do sujeito, *b* = postura do companion. O produto
*a*·*b* é o **acoplamento**, lido como gerador de movimento — não como estado resultante.

`a·b = 0` com *a*, *b* ≠ 0 é **aniquilação**: os dois estados presentes, cada um com norma, e o
encontro não gera nada. É a definição operacional de "o acoplamento não ocorreu".

Três observáveis que nenhum modelo em espaço vetorial possui:
- comutador [a,b] = ab − ba — direcionalidade da troca;
- associador [a,b,c] = (ab)c − a(bc) — sensibilidade ao **agrupamento** (não à ordem);
- déficit de composição ν(a,b) = ‖a‖‖b‖ − ‖ab‖ — em 𝕆 vale Hurwitz e ν ≡ 0; em 𝕊, ν colapsa
  a norma até zero na variedade de divisores.

⚠️ **Correção terminológica que este documento fixa:** ORDEM é o comutador; AGRUPAMENTO é o
associador. Texto anterior do projeto (`PERSONAL_PERSONA`) usava "a ordem das falas deixa de
importar — associador zerado", confundindo os dois. A díade-eco é fenômeno de comutador; o
atrito e a aniquilação são de associador e de divisor de zero.

## 2. Axiomas declarados (defendem a escolha de 𝕊; sem eles, 16 é numerologia)

- **A1** — intensidade afetiva é uma norma euclidiana **definida positiva**. Exclui as álgebras
  split (split-complexos já têm divisores de zero em 2 dimensões; split-octonions os têm e ainda
  são alternativas). É A1 que torna a cadeia de Cayley–Dickson o lugar certo para procurar.
- **A2** — a composição é bilinear.
- **A3** — a auto-composição é não-ambígua (potência-associatividade). Vale em toda a cadeia CD.

**Minimalidade condicional:** dado A1–A3 e a cadeia CD, 𝕆 ainda é álgebra de divisão e
alternativa (nada aniquila); 32 dimensões não acrescentam fenômeno algébrico categoricamente
novo. **𝕊 é o joelho da curva.** A pergunta de banca não é "por que 16" — é "por que
Cayley–Dickson", e a resposta é A1.

## 3. Fatos estruturais — VERIFICADOS, não citados

Computados por `ops/vetor-afeto/sedenion.py`, com o produto construído por duplicação a partir
de ℝ (nada tomado de memória):

| fato | valor |
|---|---|
| pares (eᵢ+eⱼ)(e_k+e_l) que aniquilam em 𝕊 | **84** |
| elementos (eᵢ+eⱼ) que são divisores de zero | **42**, cada um com **exatamente 2** parceiros |
| ‖ab‖²/(‖a‖²‖b‖²) dentro de e₀..e₇, 200 mil sorteios | **1,000** — Hurwitz, nada aniquila |
| a mesma razão em 𝕊 inteiro | cai a ~0,20 |
| dos 84 pares, quantos cruzam e₀..e₇ / e₈..e₁₅ | **84 de 84** |
| forma dos 84 pares | **ambos os lados** são (declaradoᵢ + medidoⱼ) |
| ocorrências por índice, e₁..e₇ e e₉..e₁₅ | **24 cada**, uniforme |
| índice e₈ | **não participa de nenhum divisor de zero de base** |

**Consequência 1 (força ψ):** se todos os canais forem para e₀..e₇, a aniquilação é impossível
por construção — a teoria fica intestável, e não por falta de dado. ψ **tem** que atravessar a
duplicação.

**Consequência 2 (mata uma casa):** e₈ é a unidade da duplicação e não entra em divisor de zero
de base. A metade medida tem **7** casas úteis (e₉..e₁₅), não 8.

**Consequência 3 (a diagonal, e é o achado central):** dos 7×7 = 49 pares (declarado *d*,
medido *m*), exatamente **42 são divisores de zero**. Os 7 que NÃO são formam precisamente a
diagonal *m* = *d* + 8.

> **Um estado cujo componente declarado e cujo componente medido estão no MESMO eixo nunca é
> divisor de zero.** A aniquilação exige que o relatado e o medido estejam em eixos DIFERENTES.
> A concordância interoceptiva protege o acoplamento por necessidade algébrica.

Isto não foi posto na álgebra à mão: caiu dela, dada a divisão declarado/medido. É o construto
de concordância interoceptiva da Fase 5 com uma razão estrutural por baixo.

**Consequência 4 (uniformidade):** dentro de cada metade, os índices são intercambiáveis (24
ocorrências cada). A atribuição canal→índice **dentro** de uma metade é gauge, fixada por
Aut(𝕊). O que é substantivo é a DIVISÃO e a DIAGONAL.

## 4. ψ — o embedding, fixado

**Parte real e₀ ≡ 0.** O estado é imaginário puro. Só assim *a*² = −‖a‖², o que torna exato o
corte das predições (nem eco nem oposto aniquilam) e mantém intensidade = norma.

**e₁..e₇ — DECLARADO** (o que o sujeito diz sobre si)
**e₈ — VAZIO por obrigação estrutural**
**e₉..e₁₅ — MEDIDO** (o corpo dele)

| eixo | e_d — declarado | e_{d+8} — medido |
|---|---|---|
| 1 | valência (State of Mind, Apple) | ritmo da fala, wpm |
| 2 | tensão/ativação relatada | HRV (SDNN) |
| 3 | cansaço relatado | horas de sono |
| 4 | pressa/agitação relatada | frequência cardíaca |
| 5 | travamento/hesitação relatada | razão de pausa |
| 6 | livre | livre |
| 7 | livre | livre |

**A diagonal é A ALEGAÇÃO**, não uma convenção: ela declara qual canal do corpo é a contraparte
de qual canal do relato, e é ela que define o que conta como concordância interoceptiva.

Justificativa de duas escolhas contra o hábito da literatura:
- **valência ↔ ritmo da fala**, e não valência ↔ HRV. HRV não é medida de valência: é de
  regulação autonômica. E o ritmo/pausa da fala é o canal **não controlável conscientemente** —
  o mesmo que o HELIO-N1 já reservou para distinguir recalibração genuína de complacência verbal.
- **HRV no eixo de tensão**, que é onde ela de fato mede alguma coisa.

**FORA de ψ, por decisão registrada:** pressão atmosférica, temperatura e Dst entram como
**exposições**, não como coordenadas — o céu modula o acoplamento, não é componente do estado.
Motivos: são compartilhadas (não individuam o sujeito num n=1), são fortemente correlacionadas
com hora do dia e estação (D4 do HELIO-N1), e sob a alternativa rejeitada elas ocupariam 3 das 7
casas do corpo. A alternativa (A), rejeitada aqui, teria a virtude de tornar o céu um aniquilador
estrutural — porque não há contraparte declarada para barômetro, logo conteúdo nesses eixos nunca
seria protegido pela diagonal. Fica registrada como caminho não tomado.

**Normalização:** cada canal entra como z-score contra a linha de base do próprio sujeito, no
período de referência declarado no §7. Normas importam (‖a‖ é intensidade), então a escala é
parte de ψ e não pode ser ajustada depois.

**Estado mínimo viável:** hoje só o eixo 1 declarado (State of Mind) está coletado; e₂..e₇ ficam
em zero. Isso NÃO invalida o teste — ao contrário: um estado com um componente declarado e um
medido tem exatamente a forma (e_d + e_m), que é onde vivem os 42 divisores de zero. A
configuração mínima já é a configuração testável.

## 5. O lado *b* é ESCOLHIDO, não medido

A postura do companion não é lida do texto — é **fixada em 𝕊** e depois renderizada em texto.
*b* é fator experimental manipulado, não observação. Isso elimina o problema de medida em um dos
lados da díade e remove a circularidade de inferir a postura a partir da própria resposta.

Aparato: o sinalizador `probe: true` (`apps/project-cockpit/server/mobile-routes.mjs`) exercita
roteamento, aterramento, voz e portão de fala **sem gravar nada no corpus** — nenhuma díade
experimental entra na memória do sujeito como se fosse fala dele.

## 6. Predições

**P1 — aniquilação NÃO-ANTIPODAL.** Para *a* imaginário puro, *a*·*a* = −‖a‖² e *a*·(−*a*) =
+‖a‖². **Nem o eco nem o oposto aniquilam** — os dois dão módulo máximo. Os divisores de zero são
pares estruturados e não-opostos. Predição: existem pares (estado, postura) **não-antipodais**
cuja composição produz co-presença relatável, ativação fisiológica intacta e **resultante nula**;
enquanto pares antipodais produzem resultante forte. **O circumplexo com média vetorial prediz o
padrão inverso.** Esta é a predição que separa as duas teorias.

**P2 — efeito de AGRUPAMENTO.** Mesma tripla ordenada (a,b,c), manipulando apenas a fronteira de
segmentação (pausa/reset de contexto após o primeiro ou o segundo elemento): (ab)c contra a(bc).
Todo modelo associativo — circumplexo com qualquer regra de atualização, espaço de estados
linear, **e a cognição quântica inteira, cujas álgebras de operadores são associativas** — prediz
estado final idêntico a menos de ruído. 𝕊 prediz diferença de magnitude ∝ ‖[a,b,c]‖, calculável
de antemão a partir de ψ.

## 7. Controles que MATAM a teoria

- **Espelho (a,b,a) ⇒ efeito NULO.** Toda álgebra de Cayley–Dickson é flexível: [a,b,a] = 0. Se o
  efeito de agrupamento em espelho for não-nulo, **o modelo sedeniônico cai.**
- **Teste 8 contra 16.** 𝕆 é alternativa: [a,a,b] = 0. Se o efeito de agrupamento em (a,a,b) for
  não-nulo, octoniões estão excluídos e 𝕊 é necessário. Se for nulo, 𝕆 basta e a escolha de 16
  perde a justificativa.
- **Ruminação.** Potência-associatividade garante que aⁿ é não-ambíguo: auto-composição repetida
  não pode produzir efeito de agrupamento. Se produzir, o modelo cai.
- **Piso de ruído obrigatório.** Nenhum efeito é interpretável sem a divergência entre repetições
  da MESMA célula. Medido hoje em bancada análoga: 0,736 — altíssimo. Qualquer efeito precisa
  superá-lo.

## 8. Incerteza — a quadratura escalar é ILEGAL aqui

O produto é bilinear, então a propagação de primeira ordem vale (d(ab) = (da)b + a(db)). Mas o
tensor de constantes de estrutura é **não-diagonal**: mesmo com entradas provadamente
independentes, a incerteza de *ab* mistura componentes. **Quadratura componente-a-componente é
ilegal por construção**, e não apenas por correlação nas entradas. `Knowledge[𝕊]` exige
covariância 16×16 (GUM Suplemento 2), não *u* escalar.

E perto da variedade de divisores, ‖ab‖ → 0 enquanto o ruído de entrada não: a incerteza
**relativa** diverge e a linearização de primeira ordem quebra (os termos de segunda ordem
dominam quando a saída de primeira ordem ≈ 0). Ali só Monte Carlo (GUM-S1) é válido.

**Predição auxiliar, e é testável:** a confiabilidade da medida afetiva deve **colapsar
exatamente nos estados ambivalentes** — os estados próximos da variedade são intrinsecamente os
de pior razão sinal-ruído.

⚠️ Este documento depende do conserto da Fase 1 em `stdlib/epistemic/graded_effects.sio`, que hoje
aplica quadratura incondicionalmente. Sem ele, qualquer barra de incerteza publicada aqui é mais
apertada que a verdade — o defeito cometido dentro da peça que deveria demonstrar rigor.

## 9. O que NÃO é reivindicado

Afeto em mais de 2D (PAD/Mehrabian; Fontaine et al. 2007). Ordem importa na emoção (Component
Process Model de Scherer; efeitos de ordem em cognição quântica, Busemeyer–Bruza; igualdade QQ,
Wang et al. 2014). Ambivalência como co-presença (literatura de atitudes; processo oponente de
Solomon & Corbit). Redes hipercomplexas — quaterniônicas, octoniônicas, PHM, **e sedeniônicas**,
que já existem em aprendizado de máquina desde ~2020. Afeto em variedades não-euclidianas
(embeddings hiperbólicos; geometria Riemanniana em matrizes SPD para BCI).

**O que se reivindica, e só isto:** 𝕊 como espaço de estados do afeto **diádico**, com o
associador e a variedade de divisores de zero elevados a observáveis psicológicos, produzindo
predições de invariância (espelho, ruminação) e de violação (agrupamento, aniquilação
não-antipodal) que **nenhuma álgebra associativa pode imitar**.

## 10. O que falsifica

Efeito de agrupamento em espelho não-nulo. Ausência de efeito de agrupamento em (a,b,c) com
‖[a,b,c]‖ grande sob ψ. Aniquilação ocorrendo em pares antipodais (padrão do circumplexo).
Ausência de qualquer efeito acima do piso de ruído de repetição.

## 11. Congelamento

Nenhum dado foi examinado na redação deste documento. O período de análise, a linha de base para
z-score e o protocolo de coleta entram na v2 **antes** da primeira análise; a v1 fixa o modelo,
ψ, as predições e os controles.
