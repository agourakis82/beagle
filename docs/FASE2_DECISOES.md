# Fase 2 — registro de decisões de condução

Decisões sobre **como o estudo é conduzido**, que não fazem parte da regra congelada.

O pré-registro (`PREREG_FASE2_DIRECAO_v1.md`) é imutável por hash — editá-lo faria o
julgamento parar, de propósito. Este arquivo é o outro lado: append-only, datado, para as
escolhas que mudam o que é **observado** sem mudar como é **julgado**.

Sem isto, uma decisão deliberada vira, meses depois, indistinguível de um descuido.

---

## 2026-08-17 — Aceitar o substrato estreito; NÃO induzir relato

**Observado.** Dos 33 auto-relatos com canal, a distribuição é:

| canal | n | elegível para corroboração |
|---|---|---|
| `valence` | 20 | **não** — única fonte é `HKStateOfMindType`, ele declarando o próprio humor |
| `arousal` | 7 | sim |
| `pain` | 3 | **não** — sem medida objetiva |
| `fatigue` | 2 | sim |
| `oncall` | 1 | **não** — contexto, não estado |

**Quase dois terços do que ele relata é `valence`** — "vontade de chorar", "a fumaça me
alivia", "sentiu angústia". Exatamente o canal sem medida independente. Os canais testáveis
(`arousal`, `fatigue`, `sleep`) somam 9 de 33.

**Isto é um achado, não um defeito:** ele fala muito mais sobre como se sente do que sobre
estados com correlato fisiológico mensurável. A estreiteza estava escondida enquanto o funil
contava apenas "auto-relatos".

**A alternativa recusada.** Fazer o companion perguntar ocasionalmente sobre sono e cansaço
produziria relato em canal elegível e alargaria o substrato depressa.

**Recusada porque seria intervenção.** O companion perguntar "como você dormiu?" muda o que
ele relata e quando — vira variável dentro do próprio experimento, e o efeito da pergunta
ficaria misturado com o efeito que se quer medir. Pior: seria uma intervenção introduzida
DEPOIS de ver que o substrato era estreito, isto é, escolhida para melhorar o número.

**Decisão: aceitar o substrato estreito e esperar acumular.** Nenhuma pergunta induzida.
O relato continua sendo o que ele falaria de qualquer forma.

**Consequência aceita, declarada agora e não depois:** o rendimento será lento. Terminada a
fila histórica, a taxa passa a ser a da fala espontânea dele em canais testáveis — poucos por
semana, talvez menos. Um n pequeno demais para conclusão agregada é um resultado possível
deste desenho, e foi escolhido de olhos abertos.

**Se um dia isto for revisto**, a revisão entra aqui com data, e a série passa a ter duas
épocas — igual ao confundidor já declarado na §6 do pré-registro.

---

## 2026-08-18 — Desmarcar 27 auto-relatos cujo SUJEITO não era ele

**O que motivou.** O primeiro veredito da Fase 2 saiu `INELEGIVEL` sobre a frase *"A
probabilidade posterior de que as propriedades da ontologia…"* — texto técnico classificado
como relato emocional. Medindo, **3 de 9** auto-relatos em canal **elegível** eram falsos
positivos, todos com a mesma forma: o falante era ele, o **sujeito** não.

A guarda `speakerIsSubject` pergunta se ELE FALOU. Não perguntava se o **estado era dele** — e
a corroboração confronta a fisiologia DELE. `subjectIsSelf()` passou a exigir isso, por lista
branca derivada dos sujeitos reais medidos.

**A guarda protege o que vem; não desfaz o que entrou.** Havia 27 auto-relatos gravados que a
regra nova recusa, 3 deles em canal elegível — vivos, e elegíveis pelo caminho antigo.

**Decisão dele: desmarcar os 27.** `self_report`, `state_channel` e `state_polarity` limpos.
**Nenhum fato foi apagado**: texto, proveniência, hora e vínculos ficam intactos. O fato apenas
deixa de se apresentar como relato sobre o corpo dele — correção de classificação, não
reescrita de história.

Os valores anteriores ficam abaixo, para que a correção seja auditável fora do banco.

### Os 27, com o que carregavam antes

| sujeito | canal | sinal | frase |
|---|---|---|---|
| `você` | **arousal** | — | Você estava confuso. |
| `você` | **arousal** | — | Você está me ouvindo? |
| `Beagle` | **fatigue** | alta | Sim…. Tem muita coisa pra melhorar aqui no beagle ainda |
| `HRV` | valence | alta | Hrv está alta pro meu padrão, muitas vezes fica cravada em 10- 1 |
| `Sentimentos` | valence | — | Quero falar de sentimentos. |
| `Sounio` | valence | alta | A probabilidade posterior de que as propriedades da ontologia se |
| `Você` | valence | — | Como você está agora? |
| `choro` | valence | baixa | Choro está travado. |
| `fumaça` | valence | alta | Parece que a fumaça me alivia. |
| `interaction` | valence | — | Oi, como você tá hoje? |
| `sentimento estranho` | valence | — | Nada aparece….é sentimento estranho. |
| `voz` | valence | — | A voz não tá legal |
| `Busque na sua memória` | — | — | Busque na sua memória (recall/exocortex) entradas datadas de hoj |
| `G₂ bridge proposal` | — | — | The proposed experiment is technically feasible. |
| `IR/lower alternative` | — | — | The user suspects IR/lower alternative as a potential issue. |
| `Sounio` | — | — | O sistema Sounio relatou o status do check Stale Issue Cleanup c |
| `Sounio` | — | — | O sistema Sounio relatou o status do check Issue Triage como ski |
| `Sounio` | — | — | O sistema Sounio está monitorando a PR 1776 até que zero checks  |
| `Sounio` | — | — | O sistema Sounio relatou o status do check Impact como pending c |
| `Sounio` | — | — | O sistema Sounio relatou o status do check PR Triage como pendin |
| `acquisition reason lowerin` | — | — | The user suspects acquisition reason lowering as a potential iss |
| `exploração` | — | — | É exploração da minha própria exploração. |
| `parser/items alternative m` | — | — | The user requested the top 3 exact suspects with rationale. |
| `parser/items alternative m` | — | — | The user suspects parser/items alternative metric parsing as a p |
| `parser/items alternative m` | — | — | The user requested to focus on likely float/int mismatches only. |
| `person` | — | — | Um pouco angustiado, mas sem motivo aparente. |
| `pregabalina` | — | — | Costuma ajudar. |

Em **negrito**, os 3 que estavam em canal elegível — os que teriam entrado na corroboração.

---

## 2026-08-18 — Manter a lista branca de sujeito ESTREITA

**A escolha.** `subjectIsSelf()` aceita apenas um conjunto pequeno e medido de nomes
(`eu`, `I`, `me`, `self`, `myself`, `speaker`, `user`, `ele`, `sujeito`). Qualquer outro nome
é recusado por padrão.

**O custo, visível já no primeiro lote.** Ao desmarcar os 27, a tabela expôs um auto-relato
legítimo que a lista recusa:

> `person` — *"Um pouco angustiado, mas sem motivo aparente."*

É ele descrevendo o próprio estado, e a guarda o rejeita porque o extrator o nomeou `person`,
que é genérico demais para entrar na lista.

**A alternativa recusada.** Acrescentar `person` e formas parecidas ganharia cobertura. Foi
recusada porque `person` pode denotar qualquer um: aceitá-lo abriria a porta para um estado de
terceiro entrar no caminho da corroboração — que é o modo de falha que a guarda existe para
impedir.

**Decisão dele: manter estreita.** A assimetria é deliberada e vale registrar por escrito:

> Falso positivo **corrompe a ciência** — um estado alheio casado com a fisiologia dele.
> Falso negativo **só custa cobertura** — um relato verdadeiro que não é contado.
>
> Num n-de-1 onde o substrato já é estreito, essa troca dói. Foi escolhida assim mesmo.

**Consequência instrumentada, não apenas aceita.** Custo aceito não pode ser custo invisível:
`applyExtraction` passou a devolver `sujeitoAlheio`, e o worker imprime a contagem. Sem esse
número ninguém descobriria que a lista está comendo demais, e a decisão deixaria de ser
revisável — que é o oposto de tê-la registrado aqui.

**Se um dia for revisto**, entra aqui com data, e a série ganha duas épocas.
