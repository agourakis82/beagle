-- 013_backfill_occurred_at.sql
-- Recupera os auto-relatos extraídos antes da regra do presente.
--
-- Cinco auto-relatos dele ficaram sem `occurred_at` — "Estou ansioso hj",
-- "Peito apertado de angústia", "acordei com o peito apertado" — porque o prompt
-- anterior mandava descartar fato sem hora explícita, e uma frase de 25
-- caracteres nunca diz quando. O prompt já foi corrigido; isto alcança o que foi
-- extraído antes.
--
-- ⚠️ REPROCESSAR NÃO RESOLVERIA. A inserção é idempotente por `content_sha256`:
-- re-extrair o mesmo fato cai em `ON CONFLICT DO NOTHING` e o `occurred_at` nulo
-- permaneceria. O conserto tem de ser sobre a linha existente.
--
-- A imputação é MARCADA, nunca silenciosa. "acordei com o peito apertado" acordou
-- horas antes de dizer, e com janela de ±60min contra a fisiologia isso confronta
-- o relato com o corpo de outro momento. A Fase 5 escolhe se aceita horas
-- imputadas; essa escolha só existe se a distinção estiver gravada.
--
-- Só toca auto-relato cujo registro é fala DELE — a mesma condição da guarda de
-- falante. Um relato da máquina não ganha hora, porque não deveria ser
-- auto-relato para começar.
--
-- Idempotente: a condição exige occurred_at IS NULL, que deixa de valer depois.

UPDATE facts f
   SET occurred_at = r.occurred_at,
       occurred_at_imputed = true
  FROM records r
 WHERE r.id = f.source_record_id
   AND f.self_report
   AND f.occurred_at IS NULL
   AND r.occurred_at IS NOT NULL
   AND (
     CASE
       WHEN NULLIF(btrim(lower(r.metadata->>'role')), '') IS NOT NULL
         THEN btrim(lower(r.metadata->>'role')) = 'user'
       ELSE r.prov_actor = 'user_stated'
     END
   );
