-- 016_fact_agreement.sql
-- O VEREDITO: o auto-relato concorda com o corpo, sob a regra congelada?
--
-- Tabela própria, e não coluna em `facts`, por um motivo que não é organizacional: o veredito
-- é relativo a um PRÉ-REGISTRO. Se um dia houver `direcao-v2`, o mesmo fato terá dois
-- vereditos — um por regra — e ambos precisam continuar legíveis. Uma coluna forçaria
-- sobrescrever o passado toda vez que a regra mudasse, que é a forma mais limpa de apagar a
-- história de uma decisão metodológica.
--
-- ⚠️ GRAVA TODOS OS VEREDITOS, inclusive os que não servem:
--
--   CONCORDA      a medida caiu na cauda predita
--   DISCORDA      caiu na cauda oposta
--   INCONCLUSIVO  caiu na faixa central — ausência de evidência, NÃO apoio
--   INELEGIVEL    faltou independência, cobertura, linha de base ou polaridade
--   EXPLORATORIO  medida sem direção pré-registrada
--
-- Guardar só o que concorda transformaria a tabela num placar de vitórias, e contar linhas
-- daria uma taxa de acerto de 100% por construção. A contagem de DISCORDA é tão informativa
-- quanto a de CONCORDA — e mais, porque é ela que prova que a regra pode falhar.
--
-- `prereg_sha256` fica na LINHA, não só no código: quem ler esta tabela daqui a um ano precisa
-- poder verificar sob qual texto exato aquele veredito foi produzido, sem confiar em que o
-- arquivo no repositório seja o mesmo.
--
-- Aditivo + idempotente.

CREATE TABLE IF NOT EXISTS fact_agreement (
  fact_id        uuid NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
  prereg_version text NOT NULL,
  prereg_sha256  text NOT NULL,
  verdict        text NOT NULL,
  motivo         text NOT NULL,
  reforco        int  NOT NULL DEFAULT 0,   -- secundárias que concordaram com a primária
  channel        text,
  polarity       text,
  judged_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fact_id, prereg_version),
  CONSTRAINT fact_agreement_verdict_chk CHECK (verdict IN (
    'CONCORDA', 'DISCORDA', 'INCONCLUSIVO', 'INELEGIVEL', 'EXPLORATORIO'
  ))
);

CREATE INDEX IF NOT EXISTS fact_agreement_verdict_idx
  ON fact_agreement (prereg_version, verdict);
