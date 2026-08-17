-- 009_promote_funnel.sql
-- O funil da promoção, gravado a cada execução.
--
-- Havia 549.059 fatos, 550.838 linhas de apoio e ZERO corroborados. O número
-- sozinho não diz nada: pode ser critério exigente, extração parada, apoio que
-- não acumula. Só medindo estágio a estágio dá para saber onde o funil zera, e
-- foi assim que se descobriu que ele zera em 54.740 -> 0 — nenhum fato tem dois
-- apoiadores `user_stated`, então o critério de quórum nunca teve o que contar.
--
-- Gravar isto a cada ciclo é a disciplina de auto-incriminação: um estágio que
-- zera aponta o estágio. Sem a série, um zero em `corroborated` é indistinguível
-- de rigor — e foi lido como rigor por semanas.
--
-- REGRA DURA, escrita aqui porque é onde a tentação aparece: não afrouxar o
-- critério para o número subir. Zero corroborados com critério honesto vale mais
-- que dez mil com critério dobrado. Esta tabela existe para tornar o afrouxamento
-- visível — se `promoted` subir num ciclo em que `independent_support` não subiu,
-- alguém mexeu na régua.
--
-- Aditivo + idempotente.

CREATE TABLE IF NOT EXISTS promote_funnel (
  id             bigserial PRIMARY KEY,
  ran_at         timestamptz NOT NULL DEFAULT now(),
  criterion      text NOT NULL,   -- versão do critério que produziu estes números
  facts_total       bigint NOT NULL,
  with_support      bigint NOT NULL,  -- >= 1 linha em fact_supports
  with_user_support bigint NOT NULL,  -- >= 1 apoio user_stated
  independent_support bigint NOT NULL,-- satisfaz o critério de independência vigente
  promoted          bigint NOT NULL   -- de fato em corroborated/known
);

CREATE INDEX IF NOT EXISTS promote_funnel_ran_at_idx ON promote_funnel (ran_at DESC);
