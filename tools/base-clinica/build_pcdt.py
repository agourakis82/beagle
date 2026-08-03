#!/usr/bin/env python3
"""Camada brasileira: PCDT do Ministério da Saúde / CONITEC, verbatim.

Mesmo princípio da bula: nada é reescrito. Guarda o PARÁGRAFO como está no PDF
oficial, com título do documento, PÁGINA e URL — citação que ele abre e confere.
Difere da camada FDA em duas coisas que importam: é português e é a conduta que
o SUS realmente manda seguir.
"""
import json, os, re, sqlite3, sys, urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(AQUI, "bula.sqlite")
PDFS = os.path.join(AQUI, "pcdt_pdf")
MAX_MB = 45

# O que aparece num plantão de clínica médica adulta. PCDT cobre muita doença
# rara de dispensação; incluir tudo seria peso sem uso.
RELEVANTES = [
    "acidente vascular", "anemia", "diabete", "dislipidemia", "doença de chagas",
    "doença celíaca", "doença de crohn", "dor crônica", "epilepsia", "esquizofrenia",
    "hanseníase", "hepatite", "hipertensão arterial", "hipertensão pulmonar",
    "insuficiência adrenal", "infecções sexualmente", "distúrbio mineral",
    "lúpus", "manejo da infecção pelo hiv em adultos", "miastenia", "osteoporose",
    "profilaxia pós-exposição", "prevenção da transmissão vertical",
    "tromboembolismo venoso", "psoríase", "guillain", "nefrótica primária em adultos",
    "sobrepeso e obesidade", "tabagismo", "retinopatia diabética", "vasculite",
    "ovários policísticos", "insuficiência pancreática", "espondilite", "artrite reativa",
]

# Um parágrafo só entra se tiver número de conduta. Texto narrativo não ajuda
# às 3h da manhã e infla o banco.
TEM_DOSE = re.compile(
    r"\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|g|UI|mL|ml|comprimidos?|cápsulas?)\b|"
    r"\bmg/kg\b|\bmg/dia\b|\bmg/m2\b|\bUI/kg\b", re.I)
SECAO = re.compile(
    r"(tratamento|esquema|posologia|dose|f[áa]rmac|medicament|conduta|profilaxia|manejo)", re.I)



# O PDF do MS tem layout 2D; achatar uma tabela cola cabeçalho de coluna em
# prosa e pode encostar um número na linha errada. Só entra parágrafo que se
# comporta como frase de conduta — o resto é descartado, mesmo tendo "mg".
CONDUTA = re.compile(
    r"\b(dose|doses|posologia|administrar|administra[çc][ãa]o|iniciar|manter|"
    r"aumentar|reduzir|via oral|intravenos|intramuscular|subcut[âa]ne|"
    r"\d+\s?x\s?/?\s?dia|/dia|por dia|a cada \d+\s?h|comprimido|amp[oó]la)\b", re.I)


def prosa_de_conduta(b):
    if not CONDUTA.search(b):
        return False
    frases = b.count(". ")
    if frases < 2:                      # tabela achatada quase não tem ponto final
        return False
    palavras = b.split()
    if not palavras:
        return False
    maiusculas = sum(1 for w in palavras if w[:1].isupper())
    if maiusculas / len(palavras) > 0.22:   # cabeçalho de coluna vem Capitalizado
        return False
    numeros = len(re.findall(r"\d+", b))
    if numeros > frases * 6:            # densidade numérica de tabela
        return False
    # códigos de esquema colados (6H1 9H1 3HP1 4R1) denunciam tabela achatada
    if len(re.findall(r"\b\d+[A-Z]{1,3}\d?\b", b)) >= 2:
        return False
    # cabeçalho de coluna sobrevivente
    if re.search(r"Caracter[íi]sticas\s+Esquemas|Achados cl[íi]nicos\s+Suspeita", b, re.I):
        return False
    return True


def baixa(url, destino):
    if os.path.exists(destino) and os.path.getsize(destino) > 1000:
        return True
    # No Plone o objeto responde HTML; o arquivo está atrás de @@display-file.
    dados = None
    for suf in ("/@@display-file/file", "/@@download/file", ""):
        req = urllib.request.Request(url + suf, headers={"User-Agent": "Mozilla/5.0"})
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                d = r.read()
        except Exception:
            continue
        if d[:4] == b"%PDF":
            dados = d
            break
    if dados is None:
        print("    nao veio PDF de verdade")
        return False
    if len(dados) > MAX_MB * 1_000_000:
        print(f"    grande demais: {len(dados)/1e6:.0f} MB")
        return False
    open(destino, "wb").write(dados)
    return True


def paragrafos(caminho):
    """(pagina, texto) dos parágrafos com dose, verbatim."""
    import fitz
    out = []
    try:
        doc = fitz.open(caminho)
    except Exception as e:
        print(f"    abrir falhou: {type(e).__name__}")
        return out
    for n, pag in enumerate(doc, 1):
        try:
            txt = pag.get_text("text")
        except Exception:
            continue
        for bloco in re.split(r"\n\s*\n", txt):
            b = re.sub(r"\s+", " ", bloco).strip()
            if len(b) < 90 or len(b) > 2600:
                continue
            if not TEM_DOSE.search(b):
                continue
            if not prosa_de_conduta(b):
                continue
            out.append((n, b))
    doc.close()
    return out


def main():
    os.makedirs(PDFS, exist_ok=True)
    titulos = json.load(open(os.path.join(AQUI, "pcdt_titulos.json")))
    alvo = {u: t for u, t in titulos.items()
            if any(k in t.lower() for k in RELEVANTES)}
    print(f"selecionados: {len(alvo)} de {len(titulos)}")

    db = sqlite3.connect(DB)
    db.executescript("""
      DROP TABLE IF EXISTS pcdt;
      CREATE TABLE pcdt (
        id INTEGER PRIMARY KEY, titulo TEXT NOT NULL, url TEXT NOT NULL,
        pagina INTEGER NOT NULL, texto TEXT NOT NULL, citacao TEXT NOT NULL);
      CREATE INDEX idx_pcdt_titulo ON pcdt(titulo);
    """)
    total = 0
    for i, (url, titulo) in enumerate(sorted(alvo.items(), key=lambda x: x[1]), 1):
        nome = re.sub(r"[^a-zA-Z0-9]+", "_", titulo)[:60] + ".pdf"
        destino = os.path.join(PDFS, nome)
        print(f"[{i}/{len(alvo)}] {titulo[:60]}")
        if not baixa(url, destino):
            continue
        pars = paragrafos(destino)
        for pagina, texto in pars:
            cit = f"PCDT — {titulo} (Ministério da Saúde/CONITEC), p. {pagina} — {url}"
            db.execute("INSERT INTO pcdt (titulo, url, pagina, texto, citacao) VALUES (?,?,?,?,?)",
                       (titulo, url, pagina, texto, cit))
        total += len(pars)
        print(f"    {len(pars)} trechos com dose")
        db.commit()
    # índice de busca em português
    db.executescript("""
      DROP TABLE IF EXISTS pcdt_busca;
      CREATE VIRTUAL TABLE pcdt_busca USING fts5(
        titulo, texto, pcdt_id UNINDEXED, tokenize='unicode61 remove_diacritics 2');
    """)
    db.execute("INSERT INTO pcdt_busca (titulo, texto, pcdt_id) SELECT titulo, texto, id FROM pcdt")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"\nPCDT: {total} trechos, banco agora {os.path.getsize(DB)/1e6:.1f} MB")


if __name__ == "__main__":
    main()
