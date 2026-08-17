-- 012_occurred_at_imputed.sql
-- A hora do evento veio do texto ou foi deduzida do instante da fala?
--
-- Quando o sujeito fala de si no presente ("estou ansioso hj"), o instante da
-- fala É o instante do estado, e usá-lo não é adivinhar. Mas nem todo relato é
-- assim. Medido nos auto-relatos sem hora do corpus:
--
--   "Estou ansioso hj"              presente — a hora da fala serve
--   "Peito apertado de angústia"    presente — serve
--   "acordei com o peito apertado"  ACORDOU HÁ HORAS — a hora da fala erra
--
-- Com janela de ±60min contra a fisiologia, errar por horas não é ruído: é
-- confrontar o relato com o corpo de outro momento.
--
-- Por isso a hora imputada é MARCADA em vez de indistinguível. A Fase 5 pode
-- então escolher: usar só horas declaradas (mais preciso, menos n) ou incluir as
-- imputadas (mais n, menos preciso). Essa escolha pertence ao pré-registro, e
-- ela só existe se a distinção estiver gravada.
--
-- Sem esta coluna, a alternativa seria descartar os relatos sem hora — perdendo
-- material real — ou carimbá-los em silêncio, que é pior: uma análise não teria
-- como saber que parte do seu n foi deduzido.
--
-- Aditivo + idempotente.

ALTER TABLE facts ADD COLUMN IF NOT EXISTS occurred_at_imputed boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN facts.occurred_at_imputed IS
  'true = occurred_at veio do instante da fala (registro), não do texto do relato';

-- O índice da Fase 2 continua o mesmo; quem quiser só horas declaradas filtra
-- por occurred_at_imputed = false.
CREATE INDEX IF NOT EXISTS facts_self_report_declarado_idx
  ON facts (state_channel, occurred_at)
  WHERE self_report AND state_channel IS NOT NULL AND occurred_at IS NOT NULL
        AND NOT occurred_at_imputed;
