// apps/project-cockpit/server/bula-store.mjs
//
// Consulta a base clinica verbatim. Espelha BulaStore do app (Swift) — mesma
// tabela, mesma busca FTS5, mesmo formato de citacao.
//
// POR QUE ESPELHAR EM VEZ DE INVENTAR: a garantia do desenho e que ele recebe o
// MESMO numero, da MESMA fonte, com a MESMA citacao, no telefone e no relogio,
// com rede e sem. Duas implementacoes de busca sao duas chances de divergir — e
// divergir aqui e dois numeros diferentes para a mesma pergunta.
//
// Este modulo NAO sabe o que e um LLM e nao conversa com ninguem: recebe texto,
// devolve trecho ou nada. E por isso que ele e testavel sozinho, e ele e a peca
// de que depende a seguranca clinica.
//
// COMO CONSULTA: o Node 20 (versao rodando no pod) nao tem `node:sqlite`
// (chegou so no Node 22), e o pod nao tem `better-sqlite3` nem o CLI do
// sqlite3. Tem python3 com sqlite3 da stdlib e FTS5 com o MESMO tokenizador
// do app (`unicode61 remove_diacritics 2`) — verificado no pod por execucao.
// Consultar por ele (spawn de `bula_consulta.py`) custa ~40ms, ruido diante
// dos 10+ segundos de uma resposta de chat, e evita subir o runtime inteiro
// para Node 22 ou compilar modulo nativo no meio do plano. A logica de
// casamento (normalizacao, paradas, casamento estrito por prefixo) mora no
// auxiliar Python — este arquivo so orquestra o spawn e formata o retorno.

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const AUXILIAR = join(dirname(fileURLToPath(import.meta.url)), "bula_consulta.py");

/** Roda o auxiliar Python e devolve o JSON. Erro vira null: base indisponivel e
 *  um estado que o chamador trata, nao uma excecao que derruba o chat. */
function perguntar(caminho, operacao, argumento = "") {
  try {
    const saida = execFileSync("python3", [AUXILIAR, caminho, operacao, argumento],
      { encoding: "utf8", timeout: 5000, maxBuffer: 8 * 1024 * 1024 });
    return JSON.parse(saida);
  } catch {
    return null;
  }
}

/** Abre (valida) a base. Nao guarda conexao nenhuma — cada consulta e um spawn
 *  novo do auxiliar Python, entao "Base" aqui e so o caminho ja verificado.
 *  Caminho inexistente ou sqlite sem a tabela `farmaco` (nao e uma base
 *  clinica) devolvem null, nunca lancam: base ausente e um estado que quem
 *  chama trata (responde marcado, sem fonte), nao uma excecao que derruba o
 *  chat. */
export function abrirBase(caminho) {
  if (typeof caminho !== "string" || !caminho) return null;
  const ok = perguntar(caminho, "abrir");
  if (ok !== true) return null;
  return { caminho };
}

/** Devolve o trecho verbatim de um farmaco, ou null se nao achou (ou achou
 *  errado e recusou por casamento estrito). */
export function consulta(base, pergunta) {
  if (!base) return null;
  return perguntar(base.caminho, "consulta", pergunta ?? "");
}

/** Devolve ate `limite` trechos de PCDT relevantes, ou [] (nunca lanca, nunca
 *  null — quem chama pode sempre iterar o retorno). */
export function consultaPCDT(base, pergunta, limite = 2) {
  if (!base) return [];
  const resultado = perguntar(
    base.caminho, "pcdt", JSON.stringify({ pergunta: pergunta ?? "", limite }));
  return Array.isArray(resultado) ? resultado : [];
}

/** Devolve o carimbo de proveniencia da base (versao do dump, data do build,
 *  quantidade de farmacos, hash de conteudo), ou null se a base nao abriu. */
export function carimbo(base) {
  if (!base) return null;
  return perguntar(base.caminho, "carimbo");
}
