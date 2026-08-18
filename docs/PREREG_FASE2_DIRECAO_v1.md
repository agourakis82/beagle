# Pré-registro — Direção da concordância entre auto-relato e fisiologia

**Versão:** `direcao-v1`
**Congelado em:** 2026-08-17
**Sujeito:** n-de-1, Demetrios
**Escopo:** Fase 2 do plano do exocórtex — corroboração multimodal

---

## 0. Por que este documento existe, e por que AGORA

A tabela `fact_measurements` anexa, a cada auto-relato, a medida fisiológica que existia no
instante do evento. Ela é **direção-livre de propósito**: guarda `baseline_pct`, o percentil do
valor na distribuição dele nos 90 dias anteriores, e não diz se isso concorda com o relato.

Dizer que concorda exige uma direção. Escolher a direção **depois** de ver os dados é pesca, e
transformaria qualquer resultado em confirmação.

**Este documento é escrito antes de a polaridade do auto-relato existir no banco.** Hoje
`facts` guarda `state_channel` (sono, ativação, fadiga…) mas **não guarda o sinal** — sabe-se
que ele falou de sono, não se disse que dormiu mal ou bem. Sem o sinal nenhuma direção é
aplicável, e portanto **nenhuma concordância pode ter sido observada por ninguém, nem por
acidente, no momento em que estas direções foram fixadas.** Essa é a garantia mais forte
disponível aqui, e é a razão de a ordem ser esta: congelar primeiro, instrumentar depois.

---

## 1. O que se afirma

Para cada canal de auto-relato, existe uma medida fisiológica **primária** e uma direção
esperada. A afirmação é:

> Quando ele relata um estado, a medida primária daquele canal, no instante do relato, cai na
> cauda **pré-especificada** da distribuição dele mesmo — mais frequentemente do que o acaso.

Isto é falsificável nos dois sentidos: a medida pode cair na cauda oposta.

---

## 2. As direções

`baseline_pct` ∈ [0,1] é o percentil do valor medido dentro da distribuição **dele**, nos 90
dias que antecedem o evento. `ALTO` significa cauda superior; `BAIXO`, inferior.

| canal | polaridade do relato | medida PRIMÁRIA | direção | fundamento |
|---|---|---|---|---|
| `arousal` | ativado (tenso, agitado) | `HeartRate` | **ALTO** | ativação simpática eleva a FC |
| `arousal` | calmo, relaxado | `HeartRate` | **BAIXO** | |
| `fatigue` | cansado, exausto | `RestingHeartRate` | **ALTO** | fadiga e má recuperação elevam a FC de repouso |
| `fatigue` | descansado | `RestingHeartRate` | **BAIXO** | |
| `sleep` | dormiu mal / pouco | `SleepAnalysis` (duração) | **BAIXO** | relato de sono ruim acompanha menos sono registrado |
| `sleep` | dormiu bem / muito | `SleepAnalysis` (duração) | **ALTO** | |

### Medidas SECUNDÁRIAS (confirmatórias, nunca substitutas)

| canal | medida | direção |
|---|---|---|
| `arousal` | `HeartRateVariabilitySDNN` | **BAIXO** quando ativado (retirada vagal) |
| `fatigue` | `HeartRateVariabilitySDNN` | **BAIXO** quando cansado |

Uma secundária **não pode** ser usada para declarar concordância se a primária discordar ou
faltar. Ela só reforça. Permitir que qualquer medida do canal decida seria escolher, depois do
fato, a que deu certo.

### Sem direção pré-registrada — EXPLORATÓRIO

| canal | medida | por quê |
|---|---|---|
| `sleep` | `RespiratoryRate` | não tenho base para afirmar a direção da frequência respiratória em sono ruim neste sujeito. Pré-registrar uma direção em que não acredito seria tão desonesto quanto ajustá-la depois. |
| `arousal` | `RespiratoryRate` | idem: plausível que suba, mas não com confiança suficiente para valer como teste. |

Medidas exploratórias são registradas e **nunca** contam para concordância.

### Excluídos da corroboração, por construção

| canal | motivo |
|---|---|
| `valence` | a única medida é `HKStateOfMindType` — **ele declarando o próprio humor num app**. É outro auto-relato por outra porta, não outra modalidade. A mesma boca com dois microfones. Marcado `independent = false` no código e **inelegível** aqui. |
| `pain` | sem canal objetivo disponível. |
| `oncall` | contexto, não estado. |

---

## 3. Por que a PRIMÁRIA de `arousal` é a FC e não a SDNN

A SDNN é a medida mais específica de ativação autonômica, e a escolha óbvia no papel. Aqui ela
é **secundária**, por um motivo medido: são ~5.000 amostras em sete anos, contra ~359.000 de
frequência cardíaca.

Uma medida que quase nunca existe no instante do evento não testa nada — ela produz
`n_samples = 0` e some do funil. Cobertura é condição para falsificabilidade: um teste que
raramente pode rodar não é um teste rigoroso, é um teste ausente.

A troca é declarada, não escondida: ganha-se poder e perde-se especificidade.

---

## 4. Regra de decisão

Por auto-relato, no canal declarado, usando **apenas** a medida primária:

```
ELEGÍVEL      independent = true  E  n_samples >= 1  E  baseline_n >= 30
CONCORDA      elegível E baseline_pct na cauda predita além de 0,70 (ALTO) ou 0,30 (BAIXO)
DISCORDA      elegível E baseline_pct na cauda OPOSTA além do mesmo limiar
INCONCLUSIVO  elegível E baseline_pct na faixa central [0,30 – 0,70]
INELEGÍVEL    qualquer das condições de elegibilidade falha
```

**Três saídas, não duas.** A faixa central é `INCONCLUSIVO` e **não** conta como apoio: um
resultado morno é ausência de evidência, e colapsá-lo em "não discorda" transformaria ruído em
confirmação.

`baseline_n >= 30` porque um percentil calculado sobre punhado de amostras não é percentil.

O limiar 0,70/0,30 é escolhido **antes** de qualquer contagem e não será ajustado. Se a
distribuição real tornar esse corte inadequado, isso vira um **desvio documentado**, não uma
reescolha silenciosa.

---

## 5. O que NÃO se afirma

- **Não** se afirma valor diagnóstico clínico.
- **Não** se afirma que a fisiologia é a verdade e o relato é o erro. São dois estimadores de
  um estado latente, cada um com seu ruído. Discordância é discordância, não "ele errou".
- **Não** se afirma causalidade em direção nenhuma.
- **Não** se afirma que concordância num evento corrobora um fato. Corroboração é sobre o
  padrão, não sobre a anedota. Um evento concordante é um evento concordante.
- **Não** se afirma independência entre eventos: plantões, dias e sono se correlacionam. A
  análise agregada terá de tratar isso, e este documento **não** a autoriza.

---

## 6. Confundidor declarado

A hora do dia move simultaneamente FC, SDNN, sono e a probabilidade de ele relatar cada estado.
É o confundidor primário e já está no pré-registro do HELIO-N1 (D4).

A linha de base de 90 dias **não** o elimina: ela normaliza pelo nível dele, não pelo horário.
Qualquer análise agregada sob este pré-registro deve estratificar por hora, ou declarar
explicitamente que não estratificou.

---

## 7. Como este documento é congelado

O hash SHA-256 **deste arquivo** é gravado em `agreement.mjs` como `PREREG_SHA256`, e cada
julgamento de concordância grava a versão `direcao-v1` na linha. Alterar o documento sem mudar
a versão faz o código e o registro discordarem — de propósito.

Mudança de direção exige **nova versão** (`direcao-v2`), com o motivo escrito, e **não**
reprocessa julgamentos antigos: eles continuam legíveis sob a regra que os produziu.
