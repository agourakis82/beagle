#!/usr/bin/env python3
"""Auxiliar de consulta a base clinica verbatim, chamado pelo bula-store.mjs.

POR QUE ISTO EXISTE EM PYTHON, E NAO EM JS: o Node 20.20.2 do pod nao tem
`node:sqlite` (so chega no Node 22), e o pod nao tem `better-sqlite3` nem o
CLI `sqlite3` instalados. O que o pod TEM e python3 com o modulo sqlite3 da
stdlib, com FTS5 funcionando com o MESMO tokenizador do app iOS
(`unicode61 remove_diacritics 2`). Por isso o bula-store.mjs faz spawn deste
script em vez de ler o sqlite direto -- ~40ms de custo, ruido diante dos 10+
segundos de uma resposta de chat, contra subir o runtime inteiro do cockpit
para Node 22 ou compilar um modulo nativo no meio do plano.

Este script NAO SABE o que e um LLM e nao conversa com ninguem: recebe
(caminho da base, operacao, argumento), devolve UM JSON no stdout e sai. Erro
vira excecao nao tratada (saida != 0) de proposito -- quem trata "base
indisponivel vira null" e o `perguntar()` do lado do bula-store.mjs, que
envolve a chamada num try/catch. Aqui, silenciar o erro so esconderia bug.

Operacoes:
  abrir     -> true (ou lanca, se a base nao abre / nao tem tabela farmaco)
  consulta  -> {nomePT, generico, citacao, texto} | null   (argumento = pergunta)
  pcdt      -> [{texto, citacao}, ...]                     (argumento = JSON {pergunta, limite})
  carimbo   -> {versaoDump, data, farmacos, hash} | null   (argumento ignorado)
"""
import json
import re
import sqlite3
import sys
import unicodedata

# Palavras que NUNCA devem virar termo de busca de farmaco -- espelha a mesma
# lista de paradas do app Swift, para o mesmo texto produzir o mesmo resultado
# dos dois lados.
PARADAS = frozenset([
    "para", "dose", "doses", "posologia", "quanto", "quantas", "de", "do", "da",
    "com", "sem", "em", "no", "na", "o", "a", "um", "uma", "paciente", "adulto",
    "renal", "hepatico", "endovenoso", "oral", "profilaxia", "tratamento",
])


def normalizar(texto):
    """Minusculo, sem acento, so [a-z0-9 ], espacos colapsados -- mesma
    normalizacao do bula-store.mjs, para casar exatamente as mesmas palavras
    dos dois lados."""
    s = (texto or "").lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def termos_de(pergunta):
    return [p for p in normalizar(pergunta).split(" ") if len(p) >= 4 and p not in PARADAS]


def op_abrir(db):
    # So confirma que a base e clinica de verdade (tem a tabela farmaco), nao
    # so um sqlite qualquer que por acaso abriu.
    db.execute("SELECT 1 FROM farmaco LIMIT 1").fetchone()
    return True


def op_consulta(db, pergunta):
    for palavra in termos_de(pergunta):
        linha = db.execute(
            """SELECT f.id, f.nome_pt, f.generico, f.citacao
                 FROM farmaco f
                WHERE lower(f.generico) LIKE ?1 OR lower(f.nome_pt) LIKE ?1
                ORDER BY length(f.generico) ASC
                LIMIT 1""",
            (palavra + "%",),
        ).fetchone()
        if not linha:
            continue
        fid, nome_pt, generico, citacao = linha
        # CASAMENTO ESTRITO: o generico do produto tem que COMECAR pelo termo
        # buscado. Similaridade solta ja fez aciclovir casar com GANCICLOVIR e
        # metformina trazer a associacao com sitagliptina -- entregar a bula
        # errada e pior que nao entregar nenhuma. Nao relaxar esta regra, mesmo
        # que ela deixe passar em branco algum farmaco cujo nome generico esteja
        # em ingles na base (ex.: "aciclovir" casa via nome_pt, mas o generico
        # gravado e "acyclovir" -- o prefixo nao bate e a consulta devolve null
        # em vez de arriscar). Ver task-3-report.md.
        g = normalizar(generico)
        if not g.startswith(palavra[:4]):
            continue
        secoes = db.execute(
            "SELECT titulo, texto FROM secao WHERE farmaco_id = ? ORDER BY id LIMIT 4",
            (fid,),
        ).fetchall()
        if not secoes:
            continue
        texto = "\n\n".join(f"{titulo}\n{corpo}" for titulo, corpo in secoes)
        return {"nomePT": nome_pt, "generico": generico, "citacao": citacao, "texto": texto}
    return None


def op_pcdt(db, argumento):
    dados = json.loads(argumento) if argumento else {}
    termos = termos_de(dados.get("pergunta", ""))
    limite = int(dados.get("limite") or 2)
    if not termos:
        return []
    try:
        linhas = db.execute(
            """SELECT p.texto, p.citacao
                 FROM pcdt_busca b
                 JOIN pcdt p ON p.id = b.pcdt_id
                WHERE pcdt_busca MATCH ?
                LIMIT ?""",
            (" OR ".join(termos), limite),
        ).fetchall()
        return [{"texto": texto, "citacao": citacao} for texto, citacao in linhas]
    except sqlite3.Error:
        # Base sem a tabela pcdt_busca (ex.: base de teste da Task 3 nao roda o
        # build_pcdt.py) e um estado legitimo, nao um erro: nao ha PCDT ali.
        return []


def op_carimbo(db):
    linhas = db.execute("SELECT chave, valor FROM carimbo").fetchall()
    m = dict(linhas)
    if not m:
        return None
    return {
        "versaoDump": m.get("versao_dump"),
        "data": m.get("data"),
        "farmacos": m.get("farmacos"),
        "hash": m.get("hash"),
    }


def main():
    caminho, operacao = sys.argv[1], sys.argv[2]
    argumento = sys.argv[3] if len(sys.argv) > 3 else ""
    # mode=ro: o auxiliar so le. Uma base aberta em RO tambem falha rapido e
    # limpo quando o caminho nao existe, em vez de criar um arquivo vazio.
    con = sqlite3.connect(f"file:{caminho}?mode=ro", uri=True)
    try:
        if operacao == "abrir":
            resultado = op_abrir(con)
        elif operacao == "consulta":
            resultado = op_consulta(con, argumento)
        elif operacao == "pcdt":
            resultado = op_pcdt(con, argumento)
        elif operacao == "carimbo":
            resultado = op_carimbo(con)
        else:
            raise ValueError(f"operacao desconhecida: {operacao}")
    finally:
        con.close()
    print(json.dumps(resultado, ensure_ascii=False))


if __name__ == "__main__":
    main()
