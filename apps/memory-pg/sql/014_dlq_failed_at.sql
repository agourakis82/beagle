-- 014_dlq_failed_at.sql
-- A DLQ nao registrava QUANDO a falha aconteceu.
--
-- `failed_graph.created_at` e COPIADO de `pending_graph` pelo INSERT do worker, logo e a hora
-- do ENFILEIRAMENTO, nao a da falha. Medido em 17-ago-2026: as 9 falhas ocorridas hoje
-- carregam created_at de 04-jul a 17-ago. Ou seja, a pergunta que a fila morta existe para
-- responder — "desde quando isto esta quebrando?" — nao tinha como ser respondida por ela.
--
-- Mesma familia do defeito que motivou a 007: um mecanismo de diagnostico que existe, parece
-- completo, e nao cobre a pergunta. A 007 deu o PORQUE; esta da o QUANDO.
--
-- `failed_at` fica NULO nas linhas historicas de proposito. Preencher com `now()` no backfill
-- carimbaria toda a DLQ antiga com a data da migracao — uma hora inventada, que e pior que
-- ausencia: ausencia se ve, invencao nao. NULO aqui significa "nao sei quando", que e a
-- verdade sobre elas.
--
-- Aditiva + idempotente.

ALTER TABLE failed_graph ADD COLUMN IF NOT EXISTS failed_at timestamptz;

-- Para "o que quebrou nas ultimas N horas" sem varrer a tabela inteira.
CREATE INDEX IF NOT EXISTS failed_graph_failed_at_idx
  ON failed_graph (failed_at DESC NULLS LAST);
