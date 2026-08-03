#!/usr/bin/env python3
"""Reconstrói bula.sqlite a partir do formulário DELE casado com o corpus do FDA.

A lista de 727 medicamentos vem do darwin-MFC — é o que importa na prática dele.
O conteúdo vem só do rótulo aprovado. O nome guardado é o PORTUGUÊS dele, que é
como ele vai digitar às 3h da manhã.
"""
import json, os, pickle, re, sqlite3

AQUI = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(AQUI, "bula.sqlite")
import casar  # reaproveita norm() e o índice re-chaveado

SECOES = [
    ("dosage_and_administration", "Posologia e administração"),
    ("dosage_forms_and_strengths", "Apresentações"),
    ("use_in_specific_populations", "Populações especiais (renal, hepático, idoso, gestação)"),
    ("contraindications", "Contraindicações"),
    ("boxed_warning", "Advertência em tarja preta"),
    ("warnings_and_cautions", "Advertências e precauções"),
    ("drug_interactions", "Interações"),
    ("overdosage", "Superdose"),
]
MAX_SEC = 9000


def limpa(t):
    return re.sub(r"\s+", " ", t or "").strip()


def main():
    casados = json.load(open(os.path.join(AQUI, "casados.json")))
    idx = casar.indice_cacheado()
    print(f"casados: {len(casados)} | índice: {len(idx)}")

    if os.path.exists(DB):
        os.remove(DB)
    db = sqlite3.connect(DB)
    db.executescript("""
      CREATE TABLE farmaco (
        id INTEGER PRIMARY KEY, nome_pt TEXT NOT NULL, generico TEXT NOT NULL,
        marcas TEXT, set_id TEXT, versao TEXT, fonte TEXT, citacao TEXT, atc TEXT);
      CREATE TABLE secao (
        id INTEGER PRIMARY KEY, farmaco_id INTEGER NOT NULL REFERENCES farmaco(id),
        chave TEXT NOT NULL, titulo TEXT NOT NULL, texto TEXT NOT NULL);
      CREATE VIRTUAL TABLE busca USING fts5(
        nome_pt, generico, marcas, texto, farmaco_id UNINDEXED, secao_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2');
      CREATE INDEX idx_secao_farmaco ON secao(farmaco_id);
    """)
    ok = sem_dose = 0
    for nome_pt, c in sorted(casados.items()):
        entrada = idx.get(c["chave"])
        if not entrada:
            continue
        _peso, rec, generico = entrada
        if not rec.get("dosage_and_administration"):
            sem_dose += 1
            continue
        of = rec.get("openfda", {}) or {}
        set_id = (of.get("spl_set_id") or [rec.get("set_id", "")] or [""])[0] or ""
        versao = rec.get("effective_time", "") or ""
        marcas = ", ".join((of.get("brand_name") or [])[:6])
        data = f", versão {versao[:4]}-{versao[4:6]}-{versao[6:8]}" if len(versao) == 8 else ""
        link = f" — https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid={set_id}" if set_id else ""
        citacao = f"Bula aprovada (FDA/DailyMed) — {generico}{data}{link}"
        cur = db.execute(
            "INSERT INTO farmaco (nome_pt, generico, marcas, set_id, versao, fonte, citacao, atc)"
            " VALUES (?,?,?,?,?,?,?,?)",
            (nome_pt, generico, marcas, set_id, versao, "openFDA/DailyMed SPL", citacao, c.get("atc")))
        fid = cur.lastrowid
        for chave, titulo in SECOES:
            txt = limpa(" ".join(rec.get(chave, []) or []))[:MAX_SEC]
            if not txt:
                continue
            sc = db.execute("INSERT INTO secao (farmaco_id, chave, titulo, texto) VALUES (?,?,?,?)",
                            (fid, chave, titulo, txt))
            db.execute("INSERT INTO busca (nome_pt, generico, marcas, texto, farmaco_id, secao_id)"
                       " VALUES (?,?,?,?,?,?)",
                       (nome_pt, generico, marcas, txt, fid, sc.lastrowid))
        ok += 1
    db.commit()
    db.execute("INSERT INTO busca(busca) VALUES('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"BASE: {ok} fármacos ({sem_dose} sem posologia), {os.path.getsize(DB)/1e6:.1f} MB")


if __name__ == "__main__":
    main()
