"""Recuperação da base clínica — protótipo do que o Swift vai fazer no aparelho.

Regra: só devolve TEXTO VERBATIM da bula, com citação. Nada é reescrito.
Se não achar o fármaco, devolve None — e o app volta a recusar.
"""
import re, sqlite3, unicodedata


def _norm(s):
    s = unicodedata.normalize("NFD", (s or "").lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9 ]+", " ", s)


# o que o pedido está perguntando -> qual seção da bula responde
GATILHOS = [
    (r"\brenal\b|clcr|cl cr|creatinin|dialis|tfg|clearance|nefro",
     "use_in_specific_populations", r"renal impairment|creatinine clearance|crcl|dialysis"),
    (r"hepat|cirros|child pugh", "use_in_specific_populations", r"hepatic impairment|liver"),
    (r"gestan|gravid|gestacao|amament|lactan|gravidez", "use_in_specific_populations", r"pregnan|lactation|nursing"),
    (r"idoso|geriatr", "use_in_specific_populations", r"geriatric|elderly"),
    (r"contraindic|nao pode usar|quando nao", "contraindications", None),
    (r"interac|junto com|associad", "drug_interactions", None),
    (r"intoxic|superdos|overdose", "overdosage", None),
]
JANELA = 1400
TETO = 4200

# Palavras que casariam por prefixo com nome de fármaco e não são pedido de dose.
# "para" -> paracetamol, "dose" -> nada, "mais" -> ruído. Sem isto a base
# responderia perguntas que ninguém fez.
PARADAS = {
    "para", "pare", "parar", "paciente", "pacientes", "dose", "doses", "dosagem",
    "quanto", "quando", "quantos", "como", "onde", "porque", "pode", "posso",
    "podia", "fazer", "faco", "tenho", "estou", "esta", "esse", "essa", "isso",
    "aqui", "agora", "hoje", "noite", "manha", "tarde", "mais", "menos", "muito",
    "pouco", "sobre", "ainda", "meu", "minha", "seu", "sua", "nao", "sim", "tudo",
    "nada", "algum", "alguma", "plantao", "hospital", "leito", "anos", "idade",
    "peso", "kilo", "quilo", "hora", "horas", "dias", "semana", "mesmo", "melhor",
    "pior", "certo", "errado", "duvida", "ajuda", "preciso", "queria", "acho",
}

# uma janela vale mais quando tem número de dose de verdade
_DOSE = re.compile(r"\b\d+(\.\d+)?\s?(mg|mcg|g|units?|mL|milligrams?)\b", re.I)
_RENAL = re.compile(r"creatinine clearance|crcl|renal impairment|dialysis", re.I)
_CAB = re.compile(r"dose reduction|dosage adjustment|dosage in patients with|dosage modification", re.I)


def _melhor_janela(texto, padrao):
    """Entre todas as ocorrências, a janela com mais densidade de dose.

    Pegar a PRIMEIRA ocorrência cortava no meio de outra frase e deixava de fora
    a tabela de ajuste renal, que é justamente o que muda a conduta.
    """
    if not padrao:
        return texto[:JANELA]
    pos = [m.start() for m in re.finditer(padrao, texto, re.I)]
    if not pos:
        return texto[:JANELA]
    melhor, melhor_peso = None, -1
    for i in pos:
        ini = max(0, i - 350)
        jan = texto[ini:ini + JANELA]
        peso = len(_CAB.findall(jan)) * 40 + len(_DOSE.findall(jan)) * 3 + len(_RENAL.findall(jan))
        if peso > melhor_peso:
            melhor, melhor_peso = jan, peso
    # não começar no meio de uma palavra
    if melhor and not melhor[0].isupper():
        corte = melhor.find(". ")
        if 0 < corte < 220:
            melhor = melhor[corte + 2:]
    return melhor


def consulta(db_path, pergunta):
    q = _norm(pergunta)
    tokens = [t for t in q.split() if len(t) >= 4]
    db = sqlite3.connect(db_path)
    achado = None
    for fid, pt, gen, marcas, cit in db.execute(
            "SELECT id, nome_pt, generico, marcas, citacao FROM farmaco"):
        # busca também nas MARCAS: ele vai escrever "xarelto", não "rivaroxabana"
        for cand in [pt, gen] + [m.strip() for m in (marcas or "").split(",") if m.strip()]:
            n = _norm(cand)
            for palavra in n.split():
                if len(palavra) < 4:
                    continue
                for t in tokens:
                    if t in PARADAS:
                        continue
                    # prefixo nos dois sentidos: "vanco"/"nora" acham o fármaco,
                    # "enoxaparina" acha "enoxaparin". Sem a lista de paradas,
                    # "para o paciente" casaria com paracetamol.
                    if palavra.startswith(t) or t.startswith(palavra):
                        pontos = len(t)
                        if achado is None or pontos > achado[0]:
                            achado = (pontos, fid, pt, gen, cit)
    if not achado:
        return None
    _, fid, pt, gen, cit = achado
    secoes = {k: (t, ti) for k, ti, t in
              db.execute("SELECT chave, titulo, texto FROM secao WHERE farmaco_id=?", (fid,))}

    alvo = None
    extra = None
    for gat, chave, pad in GATILHOS:
        if re.search(gat, q):
            alvo, extra = pad, chave
            break

    partes = []
    if "dosage_and_administration" in secoes:
        partes.append(("Posologia e administração",
                       _melhor_janela(secoes["dosage_and_administration"][0], alvo)))
    if extra and extra in secoes:
        t, ti = secoes[extra]
        partes.append((ti, _melhor_janela(t, alvo)))
    if "boxed_warning" in secoes:
        partes.append(("Advertência em tarja preta", secoes["boxed_warning"][0][:600]))

    corpo = "\n\n".join(f"### {ti}\n{tx}" for ti, tx in partes)[:TETO]
    db.close()
    return {"nome_pt": pt, "generico": gen, "citacao": cit, "texto": corpo}
