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
