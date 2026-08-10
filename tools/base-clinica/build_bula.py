#!/usr/bin/env python3
"""Monta a base clínica citável offline a partir dos labels aprovados (openFDA/DailyMed).

Princípio: a base NÃO ensina o modelo. Ela guarda o texto VERBATIM da bula, com
citação verificável, para o app colar no prompt. O número tem que vir do documento.

Dois cortes, um código, uma FONTE:
  --completo    todos os ativos distintos do dump local — base do SERVIDOR.
  --formulario  só os fármacos de FORMULARIO, casados contra o MESMO dump — telefone.

A garantia do desenho é "mesmo número, mesma fonte, mesma citação, em todo
lugar". Por isso os dois cortes leem do MESMO dump local (mesmo export_date),
passam pela MESMA função de gravação (grava_farmaco) e pela MESMA regra de
escolha do melhor rótulo (peso/melhor). Se um corte lesse da API pública e o
outro do dump, o mesmo fármaco poderia ter texto diferente nos dois — a
openFDA atualiza rótulos entre a data do dump e o dia em que a API é
consultada — e a Task 9 (teste de paridade entre as duas bases) falharia, ou
pior, passaria por sorte hoje e quebraria depois. Fonte diferente é a
divergência mais grosseira possível, mais grave que normalização diferente.

O caminho via API pública (--via-api) continua existindo, mas só atrás dessa
flag explícita: serve para completar um fármaco que falte no dump (a API tem
dados mais novos que o export_date do dump), nunca como caminho padrão.
"""
import argparse
import datetime
import glob
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from formulario import FORMULARIO

API = "https://api.fda.gov/drug/label.json"
# Dump local baixado pela Task 1 (14 partições, ~8,2 GB, export_date 2026-08-08).
# Os DOIS cortes leem daqui por padrão — é o que garante "mesma fonte".
DUMP_PADRAO = "/home/devsounio/openfda-labels"

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

ESQUEMA = """
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
"""


def limpa(txt):
    txt = re.sub(r"\s+", " ", txt or "").strip()
    return txt


def busca(generico):
    """Busca na API pública. USADA SÓ com --via-api: não é o caminho padrão de
    nenhum corte (ver docstring do módulo — fonte diferente é a divergência
    mais grosseira possível). Útil para completar um fármaco ausente no dump,
    que pode ter rótulo mais novo que o export_date baixado."""
    q = urllib.parse.quote(f'openfda.generic_name:"{generico}"')
    url = f"{API}?search={q}&limit=5"
    req = urllib.request.Request(url, headers={"User-Agent": "beagle-offline-bula/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8")).get("results", [])


def peso(rec, alvo):
    """Quanto este rótulo serve como resposta para o ativo `alvo` ISOLADO.

    Sem isto, 'metformin hydrochloride' devolvia o rótulo do ZITUVIM
    (sitagliptina + metformina) e a posologia recuperada era a da combinação.
    Produto combinado é bula legítima, mas responde outra pergunta. Usada
    pelos dois cortes — é a MESMA regra de escolha do melhor rótulo.
    """
    alvo_n = alvo.lower()
    of = rec.get("openfda", {}) or {}
    genes = [g.lower() for g in (of.get("generic_name") or [])]
    d = " ".join(rec.get("dosage_and_administration", []) or [])
    p = " ".join(rec.get("use_in_specific_populations", []) or [])
    base = len(d) * 2 + len(p)
    # produto isolado ganha de combinação, sempre
    combinado = any(" and " in g or "," in g for g in genes) or len(genes) > 1
    exato = any(g == alvo_n for g in genes)
    return (0 if combinado else 1, 1 if exato else 0, base)


def melhor(resultados, alvo):
    """O label do fármaco ISOLADO e mais completo, dentre uma lista de candidatos."""
    return max(resultados, key=lambda r: peso(r, alvo)) if resultados else None


def extrai_campos(r):
    """Reduz um registro do dump aos campos que grava_farmaco/peso realmente usam.

    O dump tem campos enormes que não usamos (ex.: spl_product_data_elements,
    texto legal completo). Guardar só o necessário nos dicionários de
    'melhor até agora' (no máximo ~15 mil entradas vivas) é o que mantém
    memória baixa mesmo processando 8,2 GB um arquivo por vez.
    """
    of = r.get("openfda") or {}
    campos = {"openfda": of, "set_id": r.get("set_id", ""), "effective_time": r.get("effective_time", "")}
    for chave, _ in SECOES:
        v = r.get(chave)
        if v:
            campos[chave] = v
    return campos


def _varre_dump(diretorio, visitante):
    """Esqueleto comum de varredura: abre as 14 partições UMA DE CADA VEZ (nunca
    o dump inteiro em memória) e chama `visitante(r)` para cada registro. Usado
    pelos dois coletores abaixo (--completo e --formulario), para que a leitura
    do dump em si também seja uma única implementação."""
    arquivos = sorted(glob.glob(os.path.join(diretorio, "*.json")))
    for n, caminho in enumerate(arquivos, 1):
        with open(caminho, encoding="utf-8") as f:
            d = json.load(f)
        for r in d.get("results", []):
            visitante(r)
        del d  # libera o arquivo (até ~700 MB) antes de abrir o próximo
        print(f"  dump {n}/{len(arquivos)}: {os.path.basename(caminho)}", flush=True)


def todos_os_ativos_do_dump(diretorio):
    """Varre o dump local e devolve {chave: (peso, campos, nome_original)}.

    chave = openfda.generic_name[0], em minúsculas — a MESMA definição usada
    pelo medidor da Task 1 (medir_ampla.py), para que a contagem bata.

    ACHADO DA TASK 1 A CORRIGIR AQUI: o medidor usava essa chave e ficava com o
    PRIMEIRO registro visto. Isso é inofensivo para medir tamanho, mas seria o
    mesmo bug do ZITUVIM se fosse usado para construir: se o produto combinado
    aparecer no dump antes do produto isolado, e os dois compartilharem
    generic_name[0] (a ordem dos sinônimos na lista não é estável), o
    combinado venceria por chegar primeiro. Por isso aqui NÃO ficamos com o
    primeiro: para cada chave, comparamos todos os candidatos com melhor() —
    a MESMA função de escolha que --formulario chama, não uma reimplementação
    paralela de max() por cima de peso() — e ficamos com o de maior peso
    (isolado > combinado, e mais completo entre os isolados).
    """
    melhores = {}  # chave -> (campos, nome_original)

    def visitante(r):
        of = r.get("openfda") or {}
        nomes = of.get("generic_name") or []
        if not nomes:
            return
        nome = nomes[0]
        chave = nome.strip().lower()
        if not chave:
            return
        campos = extrai_campos(r)
        atual = melhores.get(chave)
        if atual is None:
            melhores[chave] = (campos, nome)
            return
        # melhor() de verdade, nao um max reimplementado na mao: os dois
        # cortes precisam usar a MESMA funcao de escolha, nao so a mesma
        # peso() por baixo. Comparamos [candidato atual, candidato novo] e
        # ficamos com o vencedor (identidade de objeto decide qual dos dois
        # -- atual ou novo -- ganhou, para herdar o nome_original certo).
        vencedor = melhor([atual[0], campos], chave)
        nome_vencedor = nome if vencedor is campos else atual[1]
        melhores[chave] = (vencedor, nome_vencedor)

    _varre_dump(diretorio, visitante)
    return melhores


def _compila_padroes_de_termo(alvos):
    """Um padrão por alvo, casando por PALAVRA INTEIRA (limite \b), não por
    substring solta.

    Achado de revisão: 'epinephrine' é substring de 'norepinephrine
    bitartrate', e 'omeprazole' é substring de 'esomeprazole magnesium' —
    fármacos DIFERENTES, não uma associação do mesmo ativo (que é o caso que
    peso()/melhor() sabem resolver, priorizando o isolado). Com substring
    solta, os dois entrariam como candidatos ao alvo errado; hoje eles
    resolvem certo só porque o rótulo isolado correto tem generic_name igual
    ao alvo (exato bate em peso()) — sorte estrutural, não garantia. Se a
    grafia ou o sal diferisse, o fármaco errado venceria em silêncio.
    \b em regex já exige transição letra<->não-letra (espaço, vírgula,
    hífen, início/fim de string) dos dois lados do alvo, então
    'epinephrine' não casa dentro de 'norepinephrine' (não há fronteira
    entre 'nor' e 'epinephrine', são todas letras), mas casa dentro de
    'sitagliptin and metformin hydrochloride' com o alvo 'metformin
    hydrochloride' (fronteira no espaço antes e no fim da string)."""
    return {alvo: re.compile(r"\b" + re.escape(alvo) + r"\b") for alvo in alvos}


def casa_formulario_no_dump(diretorio, formulario):
    """Acha, no MESMO dump local, o melhor rótulo para cada par (nome_pt,
    generico) de FORMULARIO.

    Casa por PALAVRA INTEIRA (ver _compila_padroes_de_termo) do genérico-alvo
    contra os itens de openfda.generic_name — aproxima a busca por frase que
    a API pública usava (`openfda.generic_name:"{generico}"`), sem os falsos
    positivos de substring embutida em outra palavra. É por isso que
    'metformin hydrochloride' também bate no rótulo combinado 'sitagliptin
    and metformin hydrochloride' do ZITUVIM (frase inteira, fronteira de
    palavra dos dois lados): melhor() resolve isso priorizando o produto
    isolado — a MESMA função de escolha que --completo chama.
    """
    alvos = sorted({generico.lower() for _, generico in formulario})
    padroes = _compila_padroes_de_termo(alvos)
    melhores = {}  # alvo -> campos

    def visitante(r):
        of = r.get("openfda") or {}
        genes = [g.lower() for g in (of.get("generic_name") or [])]
        if not genes:
            return
        campos = None  # só extrai se algum alvo bater, poupa trabalho
        for alvo in alvos:
            if not any(padroes[alvo].search(g) for g in genes):
                continue
            if campos is None:
                campos = extrai_campos(r)
            atual = melhores.get(alvo)
            melhores[alvo] = campos if atual is None else melhor([atual, campos], alvo)

    _varre_dump(diretorio, visitante)
    return melhores


def grava_farmaco(db, nome_pt, generico, rec):
    """Insere um fármaco e suas seções, se o rótulo tiver posologia utilizável.

    Chamada IDÊNTICA pelos dois cortes — é o ponto de convergência que garante
    que servidor e telefone normalizam e escolhem seção do mesmo jeito.
    Devolve True se gravou, False se o rótulo não tinha o mínimo utilizável.
    """
    if not rec.get("dosage_and_administration"):
        return False
    of = rec.get("openfda", {}) or {}
    set_id = (of.get("spl_set_id") or [rec.get("set_id", "")])[0] if (of.get("spl_set_id") or rec.get("set_id")) else ""
    versao = rec.get("effective_time", "") or ""
    marcas = ", ".join((of.get("brand_name") or [])[:6])
    citacao = (f"Bula aprovada (FDA/DailyMed) — {generico}"
               + (f", versão {versao[:4]}-{versao[4:6]}-{versao[6:8]}" if len(versao) == 8 else "")
               + (f" — https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid={set_id}" if set_id else ""))
    cur = db.execute(
        "INSERT INTO farmaco (nome_pt, generico, marcas, set_id, versao, fonte, citacao) VALUES (?,?,?,?,?,?,?)",
        (nome_pt, generico, marcas, set_id, versao, "openFDA/DailyMed SPL", citacao))
    fid = cur.lastrowid
    for chave, titulo in SECOES:
        txt = limpa(" ".join(rec.get(chave, []) or []))
        if not txt:
            continue
        txt = txt[:MAX_SEC]
        sc = db.execute("INSERT INTO secao (farmaco_id, chave, titulo, texto) VALUES (?,?,?,?)",
                        (fid, chave, titulo, txt))
        db.execute("INSERT INTO busca (nome_pt, generico, marcas, texto, farmaco_id, secao_id) VALUES (?,?,?,?,?,?)",
                   (nome_pt, generico, marcas, txt, fid, sc.lastrowid))
    return True


def gravar_carimbo(db, versao_dump):
    """O carimbo é o que permite dizer, com FATO, se um fármaco também existe na
    base local — em vez de supor. É o que sustenta o aviso de 'isto não vai te
    acompanhar offline'."""
    db.execute("CREATE TABLE IF NOT EXISTS carimbo (chave TEXT PRIMARY KEY, valor TEXT)")
    n = db.execute("SELECT COUNT(*) FROM farmaco").fetchone()[0]
    # Hash do CONTEUDO, nao do arquivo: dois builds do mesmo dump tem que bater.
    h = hashlib.sha256()
    for (g,) in db.execute("SELECT generico FROM farmaco ORDER BY generico"):
        h.update((g or "").encode("utf-8"))
    for chave, valor in [("versao_dump", versao_dump),
                         ("data", datetime.date.today().isoformat()),
                         ("farmacos", str(n)),
                         ("hash", h.hexdigest())]:
        db.execute("INSERT OR REPLACE INTO carimbo VALUES (?,?)", (chave, valor))
    db.commit()


def parse_args():
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--completo", action="store_true",
                   help="todos os ativos distintos do dump local — base do SERVIDOR")
    g.add_argument("--formulario", action="store_true",
                   help="so os farmacos do formulario dele, casados contra o mesmo dump — base do TELEFONE")
    p.add_argument("--saida", required=True)
    p.add_argument("--dump", default=DUMP_PADRAO,
                   help="diretorio com as 14 particoes do dump openFDA (fonte padrao dos dois cortes)")
    p.add_argument("--via-api", action="store_true",
                   help="so com --formulario: usa a API publica da openFDA em vez do dump local. "
                        "NAO e o caminho padrao — existe so para completar um farmaco ausente no "
                        "dump (a API pode ter rotulo mais novo que o export_date baixado). Usar isto "
                        "como padrao quebraria a garantia de 'mesma fonte' entre servidor e telefone.")
    args = p.parse_args()
    if args.via_api and not args.formulario:
        p.error("--via-api so se aplica a --formulario")
    return args


def main():
    args = parse_args()
    if os.path.exists(args.saida):
        os.remove(args.saida)
    db = sqlite3.connect(args.saida)
    db.executescript(ESQUEMA)
    ok = falhou = 0
    faltantes = []

    if args.formulario and args.via_api:
        total = len(FORMULARIO)
        for i, (pt, generico) in enumerate(FORMULARIO, 1):
            try:
                res = busca(generico)
                rec = melhor(res, generico)
                if rec and grava_farmaco(db, pt, generico, rec):
                    ok += 1
                else:
                    faltantes.append(f"{pt} ({generico})")
                    falhou += 1
            except Exception as e:
                faltantes.append(f"{pt} ({generico}) -> {type(e).__name__}")
                falhou += 1
            if i % 25 == 0:
                db.commit()
                print(f"  {i}/{total}  ok={ok} falhou={falhou}", flush=True)
            time.sleep(0.28)  # respeita o limite de 1000 req/dia da API publica
    elif args.formulario:
        melhores = casa_formulario_no_dump(args.dump, FORMULARIO)
        total = len(FORMULARIO)
        for i, (pt, generico) in enumerate(FORMULARIO, 1):
            rec = melhores.get(generico.lower())
            if rec is None:
                faltantes.append(f"{pt} ({generico})")
                falhou += 1
                continue
            if grava_farmaco(db, pt, generico, rec):
                ok += 1
            else:
                faltantes.append(f"{pt} ({generico})")
                falhou += 1
            if i % 50 == 0:
                db.commit()
                print(f"  {i}/{total}  ok={ok} falhou={falhou}", flush=True)
    else:
        melhores = todos_os_ativos_do_dump(args.dump)
        total = len(melhores)
        for i, chave in enumerate(sorted(melhores), 1):
            rec, nome_original = melhores[chave]
            # Sem lista de traducao PT para 14 mil ativos: nome_pt fica o nome
            # generico original do dump (a base do servidor e para o backend
            # citar, nao para exibir direto na tela do paciente).
            if grava_farmaco(db, nome_original, chave, rec):
                ok += 1
            else:
                faltantes.append(nome_original)
                falhou += 1
            if i % 1000 == 0:
                db.commit()
                print(f"  {i}/{total}  ok={ok} falhou={falhou}", flush=True)

    db.commit()
    db.execute("INSERT INTO busca(busca) VALUES('optimize')")
    db.commit()
    db.execute("VACUUM")
    gravar_carimbo(db, versao_dump=os.environ.get("OPENFDA_VERSAO", "desconhecida"))
    db.close()
    mb = os.path.getsize(args.saida) / 1e6
    print(f"\nBASE: {ok} farmacos, {falhou} sem label utilizavel, {mb:.1f} MB -> {args.saida}")
    if faltantes and args.formulario:
        print("SEM COBERTURA (o app tem que recusar nesses):")
        for f in faltantes:
            print("  -", f)


if __name__ == "__main__":
    main()
