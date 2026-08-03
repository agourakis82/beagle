#!/usr/bin/env python3
"""Monta a base clínica citável offline a partir dos labels aprovados (openFDA/DailyMed).

Princípio: a base NÃO ensina o modelo. Ela guarda o texto VERBATIM da bula, com
citação verificável, para o app colar no prompt. O número tem que vir do documento.
"""
import json, re, sqlite3, sys, time, urllib.parse, urllib.request, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from formulario import FORMULARIO

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bula.sqlite")
API = "https://api.fda.gov/drug/label.json"

# Só o que muda conduta no plantão. Bula inteira não cabe e não ajuda.
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
MAX_SEC = 9000  # corta seção gigante; guarda o começo, que é onde está a dose


def limpa(txt):
    txt = re.sub(r"\s+", " ", txt or "").strip()
    return txt


def busca(generico):
    q = urllib.parse.quote(f'openfda.generic_name:"{generico}"')
    url = f"{API}?search={q}&limit=5"
    req = urllib.request.Request(url, headers={"User-Agent": "beagle-offline-bula/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8")).get("results", [])


def melhor(resultados, alvo):
    """O label do fármaco ISOLADO e mais completo.

    Sem isto, 'metformin hydrochloride' devolvia o label do ZITUVIM
    (sitagliptina + metformina) e a posologia recuperada era a da combinação.
    Produto combinado é bula legítima, mas responde outra pergunta.
    """
    alvo_n = alvo.lower()

    def peso(rec):
        of = rec.get("openfda", {}) or {}
        genes = [g.lower() for g in (of.get("generic_name") or [])]
        d = " ".join(rec.get("dosage_and_administration", []) or [])
        p = " ".join(rec.get("use_in_specific_populations", []) or [])
        base = len(d) * 2 + len(p)
        # produto isolado ganha de combinação, sempre
        combinado = any(" and " in g or "," in g for g in genes) or len(genes) > 1
        exato = any(g == alvo_n for g in genes)
        return (0 if combinado else 1, 1 if exato else 0, base)

    return max(resultados, key=peso) if resultados else None


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript("""
      CREATE TABLE farmaco (
        id INTEGER PRIMARY KEY, nome_pt TEXT NOT NULL, generico TEXT NOT NULL,
        marcas TEXT, set_id TEXT, versao TEXT, fonte TEXT, citacao TEXT);
      CREATE TABLE secao (
        id INTEGER PRIMARY KEY, farmaco_id INTEGER NOT NULL REFERENCES farmaco(id),
        chave TEXT NOT NULL, titulo TEXT NOT NULL, texto TEXT NOT NULL);
      CREATE VIRTUAL TABLE busca USING fts5(
        nome_pt, generico, marcas, texto, farmaco_id UNINDEXED, secao_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2');
      CREATE INDEX idx_secao_farmaco ON secao(farmaco_id);
    """)
    ok = falhou = 0
    faltantes = []
    for i, (pt, generico) in enumerate(FORMULARIO, 1):
        try:
            res = busca(generico)
            rec = melhor(res, generico)
            if not rec or not rec.get("dosage_and_administration"):
                faltantes.append(f"{pt} ({generico})")
                falhou += 1
                continue
            of = rec.get("openfda", {}) or {}
            set_id = (of.get("spl_set_id") or [rec.get("set_id", "")])[0] if (of.get("spl_set_id") or rec.get("set_id")) else ""
            versao = rec.get("effective_time", "") or ""
            marcas = ", ".join((of.get("brand_name") or [])[:6])
            citacao = (f"Bula aprovada (FDA/DailyMed) — {generico}"
                       + (f", versão {versao[:4]}-{versao[4:6]}-{versao[6:8]}" if len(versao) == 8 else "")
                       + (f" — https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid={set_id}" if set_id else ""))
            cur = db.execute(
                "INSERT INTO farmaco (nome_pt, generico, marcas, set_id, versao, fonte, citacao) VALUES (?,?,?,?,?,?,?)",
                (pt, generico, marcas, set_id, versao, "openFDA/DailyMed SPL", citacao))
            fid = cur.lastrowid
            for chave, titulo in SECOES:
                txt = limpa(" ".join(rec.get(chave, []) or []))
                if not txt:
                    continue
                txt = txt[:MAX_SEC]
                sc = db.execute("INSERT INTO secao (farmaco_id, chave, titulo, texto) VALUES (?,?,?,?)",
                                (fid, chave, titulo, txt))
                db.execute("INSERT INTO busca (nome_pt, generico, marcas, texto, farmaco_id, secao_id) VALUES (?,?,?,?,?,?)",
                           (pt, generico, marcas, txt, fid, sc.lastrowid))
            ok += 1
        except Exception as e:
            faltantes.append(f"{pt} ({generico}) -> {type(e).__name__}")
            falhou += 1
        if i % 25 == 0:
            db.commit()
            print(f"  {i}/{len(FORMULARIO)}  ok={ok} falhou={falhou}", flush=True)
        time.sleep(0.28)
    db.commit()
    db.execute("INSERT INTO busca(busca) VALUES('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    mb = os.path.getsize(OUT) / 1e6
    print(f"\nBASE: {ok} fármacos, {falhou} sem label utilizável, {mb:.1f} MB -> {OUT}")
    if faltantes:
        print("SEM COBERTURA (o app tem que recusar nesses):")
        for f in faltantes:
            print("  -", f)


if __name__ == "__main__":
    main()
