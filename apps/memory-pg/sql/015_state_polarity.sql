-- 015_state_polarity.sql
-- O SINAL do auto-relato. Sem ele o pré-registro `direcao-v1` não pode rodar.
--
-- `facts` guardava `state_channel` — sabe-se que ele falou de SONO — e não guardava se disse
-- que dormiu mal ou bem. Direção sem sinal não se aplica a nada, e por isso todo julgamento
-- de concordância saía `INELEGIVEL`.
--
-- SEMÂNTICA, fixada para casar com a §2 do pré-registro. `alta` é sempre "mais do estado que
-- o canal nomeia", nunca "melhor" ou "pior" — bom e ruim mudam de lado conforme o canal, e um
-- vocabulário avaliativo faria o extrator escorregar:
--
--   arousal  alta = mais ativado (tenso, agitado)   baixa = calmo, relaxado
--   fatigue  alta = mais cansado, exausto           baixa = descansado
--   sleep    alta = dormiu MAIS/melhor              baixa = dormiu MENOS/pior
--   valence  alta = melhor humor                    baixa = pior
--             (registrado por completude; `valence` é INELEGÍVEL para corroboração)
--
-- Vocabulário FECHADO pelo mesmo motivo de `state_channel`: texto livre deixaria o critério à
-- mercê do humor do modelo em cada extração, e a corroboração é justamente o que não pode
-- depender disso.
--
-- ⚠️ NULO É O PADRÃO E É UM RESULTADO. Quando o texto não deixa o sinal claro, o extrator
-- OMITE em vez de chutar. Um palpite de moeda aqui não deixaria o julgamento indeciso — ele
-- produziria concordância ou discordância inventada em metade dos casos.
--
-- Por que isto não corrompe o pré-registro: o extrator lê APENAS o texto dele. Não vê a
-- frequência cardíaca, não vê a SDNN, não vê o percentil. Não pode ajustar a polaridade para
-- produzir acordo porque não sabe para que lado o acordo cairia. É o análogo possível de
-- cegamento num sistema de sujeito único.
--
-- Aditivo + idempotente.

ALTER TABLE facts ADD COLUMN IF NOT EXISTS state_polarity text;

ALTER TABLE facts DROP CONSTRAINT IF EXISTS facts_state_polarity_chk;
ALTER TABLE facts ADD CONSTRAINT facts_state_polarity_chk
  CHECK (state_polarity IS NULL OR state_polarity IN ('alta', 'baixa'));

-- Polaridade sem canal não julga nada, e canal sem polaridade é o estado anterior a esta
-- migração. O índice serve à consulta que o julgamento faz: auto-relatos prontos para confronto.
CREATE INDEX IF NOT EXISTS facts_prontos_para_confronto_idx
  ON facts (state_channel, state_polarity, occurred_at)
  WHERE self_report AND state_channel IS NOT NULL
    AND state_polarity IS NOT NULL AND occurred_at IS NOT NULL;
