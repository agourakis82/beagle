#!/usr/bin/env python3
"""
Bulas BRASILEIRAS (ANVISA) para a base clínica offline.

POR QUE: hoje a base tem rótulo americano (DailyMed/FDA) e protocolo do
Ministério (PCDT). Falta o que ele tem NA MÃO no hospital — a bula nacional, com
as apresentações e concentrações que existem aqui. Quando a bula americana e a
brasileira divergem, ele precisa das duas para decidir, e o companion é obrigado
a mostrar a divergência em vez de escolher por ele.

O CAMINHO (descoberto em 06-ago-2026):
  1. A API exige `Authorization: Guest`. Sem esse cabecalho: 403. Foi so isso que
     bloqueou a tentativa anterior.
  2. GET /api/consulta/bulario?filter[nomeProduto]=<pt> devolve os registros.
  3. Cada registro traz `idBulaProfissionalProtegido`: um JWT que VALE 5 MINUTOS
     (nbf/exp com 300s de diferenca). O `jti` dentro dele e o id real da bula.
  4. O PDF sai de /api/consulta/medicamentos/arquivo/bula/parecer/<jti>/
     usando aquele JWT — que precisa ser usado NA HORA. Guardar a listagem para
     baixar depois nao funciona: o token expira.

CUIDADO COM O SERVIDOR: o portal da ANVISA e fragil e devolve 503 sob rajada.
Este script vai devagar de proposito (PAUSA entre chamadas, recuo exponencial em
503) e e retomavel — se parar no meio, rodar de novo continua de onde parou.
Nao aumente a velocidade: derrubar um servico publico para montar uma base
pessoal e inaceitavel, e alem disso o 503 volta mais lento do que a pausa custa.
"""

import base64
import json
import os
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
import urllib.error

from formulario import FORMULARIO

BASE = "https://consultas.anvisa.gov.br/api/consulta"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
PAUSA = 2.5
PAUSA_CURTA = 1.2
MAX_TENTATIVAS = 4

DESTINO = os.environ.get("ANVISA_DB", "bula.sqlite")
PDF_DIR = os.environ.get("ANVISA_PDFS", "pdfs-anvisa")


def buscar(url, timeout=60, binario=False):
    """GET com recuo exponencial em 503. Devolve bytes ou None."""
    for tentativa in range(MAX_TENTATIVAS):
        req = urllib.request.Request(url, headers={
            "Authorization": "Guest",
            "User-Agent": UA,
            "Referer": "https://consultas.anvisa.gov.br/",
            "Accept": "*/*" if binario else "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                espera = PAUSA * (2 ** tentativa)
                print("      HTTP %d, esperando %.0fs" % (e.code, espera), flush=True)
                time.sleep(espera)
                continue
            return None
        except Exception:
            time.sleep(PAUSA * (2 ** tentativa))
    return None


def jti_de(token):
    """O id real da bula vive dentro do JWT."""
    try:
        p = token.split(".")[1]
        p += "=" * (-len(p) % 4)
        return json.loads(base64.urlsafe_b64decode(p))["jti"]
    except Exception:
        return None


def normalizar(s):
    s = (s or "").lower().replace("ç", "c")
    for a, b in (("áàãâ", "a"), ("éê", "e"),
                 ("í", "i"), ("óõô", "o"), ("ú", "u")):
        for ch in a:
            s = s.replace(ch, b)
    return re.sub(r"[^a-z0-9 ]+", " ", s).strip()


def melhor(registros, pt):
    """Escolhe o registro certo.

    A base americana ja ensinou o preco de errar isto: 'metformina' trouxe um
    produto de sitagliptina+metformina, e 'aciclovir' casou com GANCICLOVIR por
    similaridade de texto. Duas regras, nesta ordem:

      1. O nome do produto tem que COMECAR com o farmaco pedido. Associacao
         ('dipirona + escopolamina') nao serve quando se pediu o isolado.
      2. Entre os que passam, o nome mais CURTO — que e o isolado.
    """
    alvo = normalizar(pt)
    partes = alvo.split()
    primeiro = partes[0] if partes else alvo
    pedido_composto = len(partes) > 1
    candidatos = []
    for r in registros:
        nome = normalizar(r.get("nomeProduto"))
        if not nome.startswith(primeiro):
            continue
        if "+" in (r.get("nomeProduto") or "") and not pedido_composto:
            continue
        candidatos.append((len(nome), r))
    if not candidatos:
        return None
    candidatos.sort(key=lambda x: x[0])
    return candidatos[0][1]


def texto_do_pdf(caminho):
    try:
        from pypdf import PdfReader
    except ImportError:
        from PyPDF2 import PdfReader
    try:
        leitor = PdfReader(caminho)
    except Exception:
        return []
    paginas = []
    for n, pag in enumerate(leitor.pages, 1):
        try:
            t = pag.extract_text() or ""
        except Exception:
            t = ""
        t = re.sub(r"[ \t]+", " ", t)
        t = re.sub(r"\n{3,}", "\n\n", t).strip()
        if len(t) >= 120:
            paginas.append((n, t))
    return paginas


def main():
    db = sqlite3.connect(DESTINO)
    db.executescript("""
      CREATE TABLE IF NOT EXISTS anvisa (
        id INTEGER PRIMARY KEY,
        nome_pt TEXT NOT NULL,
        produto TEXT NOT NULL,
        empresa TEXT,
        registro TEXT,
        pagina INTEGER NOT NULL,
        texto TEXT NOT NULL,
        citacao TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS idx_anvisa_nome ON anvisa(nome_pt);
    """)
    db.commit()

    os.makedirs(PDF_DIR, exist_ok=True)
    ja = set(r[0] for r in db.execute("SELECT DISTINCT nome_pt FROM anvisa"))
    if ja:
        print("retomando: %d farmacos ja na base" % len(ja), flush=True)

    ok = vazio = falhou = 0
    for i, (pt, _generico) in enumerate(FORMULARIO, 1):
        if pt in ja:
            continue
        print("[%d/%d] %s" % (i, len(FORMULARIO), pt), flush=True)

        q = urllib.parse.quote(pt)
        bruto = buscar(BASE + "/bulario?count=20&page=1&filter%5BnomeProduto%5D=" + q)
        if not bruto:
            print("      listagem falhou", flush=True); falhou += 1; time.sleep(PAUSA); continue
        try:
            registros = json.loads(bruto).get("content", [])
        except Exception:
            falhou += 1; time.sleep(PAUSA); continue
        if not registros:
            print("      sem registro na ANVISA", flush=True); vazio += 1; time.sleep(PAUSA); continue

        r = melhor(registros, pt)
        if not r:
            print("      nenhum casamento seguro entre %d" % len(registros), flush=True)
            vazio += 1; time.sleep(PAUSA); continue

        token = r.get("idBulaProfissionalProtegido") or ""
        jti = jti_de(token)
        if not jti:
            falhou += 1; time.sleep(PAUSA); continue

        time.sleep(PAUSA_CURTA)
        pdf = buscar(BASE + "/medicamentos/arquivo/bula/parecer/%s/?Authorization=%s"
                     % (jti, urllib.parse.quote(token)), timeout=120, binario=True)
        if not pdf or pdf[:4] != b"%PDF":
            print("      PDF nao veio (%d bytes)" % (len(pdf) if pdf else 0), flush=True)
            falhou += 1; time.sleep(PAUSA); continue

        caminho = os.path.join(PDF_DIR, re.sub(r"[^a-z0-9]+", "_", normalizar(pt)) + ".pdf")
        with open(caminho, "wb") as f:
            f.write(pdf)

        paginas = texto_do_pdf(caminho)
        if not paginas:
            print("      PDF sem texto extraivel (provavel digitalizacao)", flush=True)
            vazio += 1; time.sleep(PAUSA); continue

        citacao = ("ANVISA - bula profissional de %s (%s), registro %s"
                   % (r.get("nomeProduto"), r.get("razaoSocial"), r.get("numeroRegistro")))
        for n, t in paginas:
            db.execute(
                "INSERT INTO anvisa (nome_pt, produto, empresa, registro, pagina, texto, citacao)"
                " VALUES (?,?,?,?,?,?,?)",
                (pt, r.get("nomeProduto"), r.get("razaoSocial"),
                 r.get("numeroRegistro"), n, t, "%s, p. %d" % (citacao, n)))
        db.commit()
        ok += 1
        print("      OK - %d paginas de %s" % (len(paginas), r.get("nomeProduto")), flush=True)
        time.sleep(PAUSA)

    db.executescript("""
      DROP TABLE IF EXISTS anvisa_busca;
      CREATE VIRTUAL TABLE anvisa_busca USING fts5(
        nome_pt, produto, texto, anvisa_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2');
    """)
    db.execute("INSERT INTO anvisa_busca (nome_pt, produto, texto, anvisa_id)"
               " SELECT nome_pt, produto, texto, id FROM anvisa")
    db.commit()
    n = db.execute("SELECT COUNT(*) FROM anvisa").fetchone()[0]
    f = db.execute("SELECT COUNT(DISTINCT nome_pt) FROM anvisa").fetchone()[0]
    db.close()
    print("\nfarmacos com bula: %d | trechos: %d | ok=%d vazio=%d falhou=%d" % (f, n, ok, vazio, falhou))


if __name__ == "__main__":
    sys.exit(main())
