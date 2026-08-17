-- 010_demote_machine_self_reports.sql
-- Corrige os auto-relatos que a máquina fez sobre si mesma.
--
-- Antes da guarda de falante (`speakerIsSubject`), a extração marcava
-- `self_report=true` com base só no texto. Os QUATRO primeiros auto-relatos com
-- canal que chegaram ao banco vinham de registros `role=assistant`,
-- `prov_actor=model_generated` — eram o companion falando:
--
--   "o corpo está mais acelerado que o de costume"
--   "não tenho humor, tenho postura"
--   "você me disse que estava irritado comigo"
--
-- Se ficassem, a Fase 2 confrontaria a prosa do companion com a HRV de um
-- humano e chamaria o resultado de corroboração.
--
-- A regra é a mesma da guarda em código, aplicada ao que já foi gravado: um
-- auto-relato só sobrevive se o registro de origem for fala DELE. `role` manda;
-- sem `role`, o `prov_actor` decide.
--
-- O FATO NÃO É APAGADO. Muda o que ele pode sustentar, não se existe — mesma
-- disciplina de `valid_to` em vez de DELETE que o resto do grafo já segue.
--
-- Idempotente: rodar de novo não muda nada, porque a condição já não casa.

UPDATE facts f
   SET self_report = false,
       state_channel = NULL
  FROM records r
 WHERE r.id = f.source_record_id
   AND f.self_report
   AND NOT (
     CASE
       WHEN NULLIF(btrim(lower(r.metadata->>'role')), '') IS NOT NULL
         THEN btrim(lower(r.metadata->>'role')) = 'user'
       ELSE r.prov_actor = 'user_stated'
     END
   );
