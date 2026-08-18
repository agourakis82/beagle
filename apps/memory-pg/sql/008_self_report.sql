-- 008_self_report.sql
-- Fase 2: o substrato que a corroboração multimodal precisa.
--
-- Medido no corpus antes de escrever isto: dos 54.739 fatos `user_stated`, os
-- predicados mais comuns são `contains`, `has_field`, `uses`, `implements`,
-- `has_syntax_rule`. São fatos sobre CÓDIGO. Apenas 63 mencionam corpo ou afeto.
-- O extrator nunca foi instruído a capturar estado próprio, então não capturou —
-- e sem isso não há nada que uma medida fisiológica possa corroborar.
--
-- Duas colunas, e a razão de cada uma:
--
--   self_report    o falante relatando sobre si mesmo, não sobre o mundo. Marcado
--                  na extração e não inferido depois: adivinhar isso a posteriori
--                  a partir do texto é exatamente a inferência de máquina que a
--                  quarentena de proveniência existe para manter fora do juízo.
--
--   state_channel  QUAL grandeza mensurável poderia testar a alegação. É o elo da
--                  independência entre modalidades: "dormi mal" é testável pelo
--                  canal `sleep`, "estava tenso" pelo `arousal`. Um auto-relato
--                  sem canal não é corroborável por medida, e dizer isso é mais
--                  honesto do que arranjar um canal plausível.
--
-- O vocabulário é FECHADO e vive aqui, no esquema, versionado. Um canal em texto
-- livre tornaria a junta impossível de auditar e deixaria o critério de
-- corroboração à mercê do humor do modelo em cada extração.
--
-- Aditivo + idempotente.

ALTER TABLE facts ADD COLUMN IF NOT EXISTS self_report   boolean NOT NULL DEFAULT false;
ALTER TABLE facts ADD COLUMN IF NOT EXISTS state_channel text;

ALTER TABLE facts DROP CONSTRAINT IF EXISTS facts_state_channel_chk;
ALTER TABLE facts ADD CONSTRAINT facts_state_channel_chk
  CHECK (state_channel IS NULL OR state_channel IN (
    'sleep',     -- duração/qualidade de sono          -> HKCategoryTypeSleepAnalysis
    'arousal',   -- ativação: tensão, agitação, calma  -> HRV/SDNN, FC de repouso
    'valence',   -- tom afetivo: bem/mal               -> HKStateOfMind
    'pain',      -- dor relatada                        -> (sem canal objetivo hoje)
    'fatigue',   -- cansaço, exaustão                   -> readiness, FC de repouso
    'oncall'     -- plantão: contexto, não estado       -> calendário/turno
  ));

-- Um auto-relato sem QUANDO não é corroborável: a corroboração é por evento, não
-- por tema. O índice serve exatamente à consulta da Fase 2 — achar auto-relatos
-- com canal e tempo para casar contra a série fisiológica.
CREATE INDEX IF NOT EXISTS facts_self_report_channel_idx
  ON facts (state_channel, occurred_at)
  WHERE self_report AND state_channel IS NOT NULL AND occurred_at IS NOT NULL;
