-- 011_fact_measurements.sql
-- Fase 2: a junta entre o que ele disse e o que o corpo registrou.
--
-- ⚠️ ESTA TABELA NÃO DIZ QUE O FATO ESTÁ CORROBORADO.
--
-- Ela anexa a EVIDÊNCIA disponível: qual medida existia, na janela do evento, no
-- canal que poderia testar a alegação. Dizer se a medida CONCORDA com o relato
-- exige uma direção pré-registrada ("HRV mais baixa = mais ativação"), e escolher
-- essa direção depois de ver os dados é pesca. A promoção a `corroborated`
-- continua não acontecendo, e isso é deliberado: um zero honesto vale mais que
-- dez mil com critério dobrado.
--
-- O que a tabela permite é a pergunta anterior à corroboração, que hoje ninguém
-- consegue responder: para quantos auto-relatos dele existe medida independente
-- no instante certo? Sem isso, o pré-registro da Fase 5 seria escrito às cegas.
--
-- INDEPENDÊNCIA, e por que ela é uma coluna e não uma suposição:
--
--   `independent = true`   a medida vem de outra modalidade — o corpo registrando
--                          sozinho (frequência cardíaca, SDNN, respiração, sono).
--                          Erros não correlacionados com os do auto-relato.
--
--   `independent = false`  a "medida" é outro auto-relato por outra porta.
--                          HKStateOfMindType é o caso: ele declarando o próprio
--                          humor num app. Contar isso como corroboração seria
--                          exatamente a repetição que o plano proíbe — a mesma
--                          boca, dois microfones.
--
-- `mapping_version` fica na linha porque o mapa canal→medida é uma decisão
-- teórica, não um detalhe. Se ele mudar, as linhas antigas continuam legíveis
-- sob a regra que as produziu.
--
-- Aditivo + idempotente.

CREATE TABLE IF NOT EXISTS fact_measurements (
  fact_id         uuid NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
  channel         text NOT NULL,              -- canal do auto-relato (008_self_report)
  measure_type    text NOT NULL,              -- tipo HealthKit consultado
  window_minutes  int  NOT NULL,              -- meia-janela em torno do occurred_at
  n_samples       int  NOT NULL,              -- 0 é resultado: significa SEM cobertura
  mean_value      double precision,
  unit            text,
  baseline_pct    numeric,                    -- percentil do valor na distribuição DELE
  baseline_n      int,                        -- amostras que formaram a linha de base
  independent     boolean NOT NULL,
  mapping_version text NOT NULL,
  computed_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fact_id, measure_type, window_minutes)
);

CREATE INDEX IF NOT EXISTS fact_measurements_channel_idx
  ON fact_measurements (channel, independent);

-- n_samples = 0 é gravado de propósito: "não havia medida" é um achado, e apagar
-- a linha faria a ausência de cobertura desaparecer do funil.
CREATE INDEX IF NOT EXISTS fact_measurements_cobertura_idx
  ON fact_measurements (fact_id) WHERE n_samples > 0;
