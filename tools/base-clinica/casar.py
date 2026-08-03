#!/usr/bin/env python3
"""Casa o formulário dele (727 nomes em português) com os rótulos do FDA.

A lista vem do darwin-MFC — é ela que diz o que importa na prática dele. O
CONTEÚDO continua vindo só do rótulo aprovado. Nome que não casar com folga fica
de fora: offline, ausência vira recusa, e recusa é o lado seguro do erro.
"""
import difflib, json, os, re, sys, unicodedata, zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
BULK = os.path.join(AQUI, "fda_bulk")

SAIS = r"(cloridrato|sulfato|fosfato|maleato|tartarato|besilato|mesilato|succinato|" \
       r"fumarato|acetato|citrato|nitrato|bromidrato|dicloridrato|valerato|propionato|" \
       r"sodico|sodica|potassico|potassica|calcico|calcica|monoidratado|di?hidratado|" \
       r"hydrochloride|hydrobromide|sulfate|phosphate|maleate|tartrate|bitartrate|" \
       r"besylate|mesylate|succinate|fumarate|acetate|citrate|nitrate|sodium|" \
       r"potassium|calcium|magnesium|dihydrate|monohydrate|hcl|bisulfate|valerate|" \
       r"propionate|lactate|gluconate|tromethamine|dipropionate|furoate|xinafoate|"\
       r"bissulfato|dissodico|dissodica|dipropionato|benzoato|palmitato)"


def norm(s):
    s = unicodedata.normalize("NFD", (s or "").lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = re.sub(r"\([^)]*\)", " ", s)          # "(AAS)", "(Vitamina D3)"
    s = re.sub(r"\b\d+\s?(mg|mcg|g|ui|ml)\b", " ", s)   # "acido folico 5mg"
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(rf"\b{SAIS}\b", " ", s)
    s = re.sub(r"\bde\b|\bda\b|\bdo\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


# Português -> inglês nas terminações de DCI. Ordem importa: mais específico antes.
REGRAS = [
    ("micina", "mycin"), ("ciclina", "cycline"), ("cilina", "cillin"),
    ("floxacino", "floxacin"), ("azol", "azole"), ("olona", "olone"),
    ("sona", "sone"), ("pina", "pine"), ("zepam", "zepam"), ("olol", "olol"),
    ("pril", "pril"), ("sartana", "sartan"), ("statina", "statin"),
    ("parina", "parin"), ("tidina", "tidine"), ("idina", "idine"),
    ("adina", "adine"), ("afina", "afine"), ("amina", "amine"),
    ("ida", "ide"), ("ico", "ic"), ("ina", "in"), ("ano", "an"),
    ("eno", "ene"), ("ol", "ol"), ("ona", "one"), ("a", "a"),
]




# Divergências PT/EN que nenhuma morfologia atravessa. Só mapeia NOME — o
# conteúdo continua vindo do rótulo. Cada linha é verificável em 10 segundos.
SINONIMOS = {
    "paracetamol": "acetaminophen", "acido acetilsalicilico": "aspirin",
    "aas": "aspirin", "adrenalina": "epinephrine", "noradrenalina": "norepinephrine",
    "salbutamol": "albuterol", "dipirona": "metamizole", "glibenclamida": "glyburide",
    "acido folico": "folic acid", "colecalciferol": "cholecalciferol",
    "tiamina": "thiamine", "piridoxina": "pyridoxine", "cianocobalamina": "cyanocobalamin",
    "sulfato ferroso": "ferrous sulfate", "insulina humana nph": "insulin human",
    "insulina humana regular": "insulin human", "insulina glargina": "insulin glargine",
    "insulina lispro": "insulin lispro", "insulina asparte": "insulin aspart",
    "varfarina": "warfarin", "fenitoina": "phenytoin", "fenobarbital": "phenobarbital",
    "cefalexina": "cephalexin", "cefalotina": "cephalothin", "cefazolina": "cefazolin",
    "hidroclorotiazida": "hydrochlorothiazide", "clomifeno": "clomiphene",
    "benzoato de benzila": "benzyl benzoate", "acido valproico": "valproic acid",
    "acido tranexamico": "tranexamic acid", "acido ascorbico": "ascorbic acid",
    "escopolamina": "scopolamine", "butilescopolamina": "scopolamine",
    "prometazina": "promethazine", "clorpromazina": "chlorpromazine",
    "levotiroxina": "levothyroxine", "espironolactona": "spironolactone",
    "sinvastatina": "simvastatin", "norfloxacino": "norfloxacin",
    "aciclovir": "acyclovir", "fluorouracila": "fluorouracil",
    "metildopa": "methyldopa", "amicacina": "amikacin", "vancomicina": "vancomycin",
    "clindamicina": "clindamycin", "gentamicina": "gentamicin",
    "cetamina": "ketamine", "cetoprofeno": "ketoprofen", "cetorolaco": "ketorolac",
    "hidroxizina": "hydroxyzine", "hidralazina": "hydralazine",
    "furosemida": "furosemide", "digoxina": "digoxin", "heparina": "heparin",
    "morfina": "morphine", "codeina": "codeine", "petidina": "meperidine",
    "polietilenoglicol": "polyethylene glycol", "dexametasona": "dexamethasone",
    "clopidogrel": "clopidogrel", "beclometasona": "beclomethasone",
    "domperidona": "domperidone", "metoclopramida": "metoclopramide",
    "bromoprida": "bromopride", "ondansetrona": "ondansetron",
    "omeprazol": "omeprazole", "pantoprazol": "pantoprazole",
    "nifedipino": "nifedipine", "anlodipino": "amlodipine",
    "captopril": "captopril", "losartana": "losartan", "metformina": "metformin",
    "prednisolona": "prednisolone", "azatioprina": "azathioprine",
    "carbamazepina": "carbamazepine", "haloperidol": "haloperidol",
    "amitriptilina": "amitriptyline", "fluoxetina": "fluoxetine",
    "diazepam": "diazepam", "clonazepam": "clonazepam", "midazolam": "midazolam",
}


def fonetico(s):
    """Reduz PT e EN à mesma forma: doxiciclina/doxycycline, sinvastatina/simvastatin."""
    s = re.sub(r"^[0-9]+\s*", "", s)          # "5-fluorouracila"
    s = re.sub(r"^e(?=[sp][a-z])", "", s)     # espironolactona -> spironolactone
    s = s.replace("ph", "f").replace("th", "t").replace("y", "i")
    s = s.replace("k", "c").replace("w", "v").replace("z", "s")
    s = s.replace("h", "")
    s = re.sub(r"n(?=[vbm])", "m", s)         # sinvastatina -> simvastatin
    s = re.sub(r"(.)\1+", r"\1", s)
    return s


def candidatos(pt):
    base = norm(pt)
    if not base:
        return []
    saida = {base}
    for palavra in base.split():
        for a, b in REGRAS:
            if palavra.endswith(a):
                saida.add(base.replace(palavra, palavra[: -len(a)] + b))
                break
    # muitos DCI só perdem o "a" final: metformina -> metformin
    saida.add(re.sub(r"a\b", "", base).strip())
    return [c for c in saida if len(c) >= 4]


def indice_bulk():
    """generic_name normalizado -> melhor registro (isolado, dose mais completa)."""
    idx = {}
    zips = sorted(f for f in os.listdir(BULK) if f.endswith(".zip"))
    for i, z in enumerate(zips, 1):
        with zipfile.ZipFile(os.path.join(BULK, z)) as zf:
            nome = zf.namelist()[0]
            dados = json.loads(zf.read(nome).decode("utf-8"))
        for rec in dados.get("results", []):
            dose = " ".join(rec.get("dosage_and_administration", []) or [])
            if len(dose) < 200:
                continue
            of = rec.get("openfda", {}) or {}
            genes = of.get("generic_name") or []
            combinado = len(genes) > 1 or any(" and " in g.lower() for g in genes)
            pop = " ".join(rec.get("use_in_specific_populations", []) or [])
            peso = (0 if combinado else 1, len(dose) * 2 + len(pop))
            for g in genes:
                k = norm(g)
                if not k:
                    continue
                if k not in idx or peso > idx[k][0]:
                    idx[k] = (peso, rec, g)
        print(f"  partição {i}/{len(zips)}: índice com {len(idx)} nomes", flush=True)
    return idx


CACHE = os.path.join(AQUI, "idx_bulk.pkl")
CAMPOS = ["dosage_and_administration", "dosage_forms_and_strengths",
          "use_in_specific_populations", "contraindications", "boxed_warning",
          "warnings_and_cautions", "drug_interactions", "overdosage",
          "effective_time", "set_id"]


def indice_cacheado():
    import pickle
    if os.path.exists(CACHE):
        print("  (índice em cache, re-chaveado)")
        cru = pickle.load(open(CACHE, "rb"))
        # o cache guarda o nome original; a chave é derivada, então re-derivar
        # aqui deixa o cache imune a mudanças em norm().
        novo = {}
        for _k, (peso, mag, g) in cru.items():
            k2 = norm(g)
            if k2 and (k2 not in novo or peso > novo[k2][0]):
                novo[k2] = (peso, mag, g)
        return novo
    cru = indice_bulk()
    enxuto = {}
    for k, (peso, rec, g) in cru.items():
        mag = {c: rec.get(c) for c in CAMPOS if rec.get(c)}
        mag["openfda"] = {"brand_name": (rec.get("openfda", {}) or {}).get("brand_name", [])[:6],
                          "spl_set_id": (rec.get("openfda", {}) or {}).get("spl_set_id", [])}
        enxuto[k] = (peso, mag, g)
    pickle.dump(enxuto, open(CACHE, "wb"), protocol=4)
    print(f"  índice em cache: {os.path.getsize(CACHE)/1e6:.0f} MB")
    return enxuto


def main():
    form = json.load(open(os.path.join(AQUI, "formulario_dele.json")))
    print(f"formulário dele: {len(form)} medicamentos")
    idx = indice_cacheado()
    chaves = list(idx.keys())
    # índice fonético: é nele que cefalexina encontra CEPHALEXIN
    fon_idx = {}
    for k in chaves:
        fon_idx.setdefault(fonetico(k), k)
    fon_chaves = list(fon_idx.keys())

    casados, perdidos, duvidosos = {}, [], []
    for k, v in form.items():
        achou = None
        base = norm(v["nome"])
        curado = False
        alvo = SINONIMOS.get(base) or SINONIMOS.get(base.split()[0] if base else "")
        if alvo and norm(alvo) in idx:
            achou = (norm(alvo), 1.0)
            curado = True
        if not achou:
            for c in candidatos(v["nome"]):
                if c in idx:
                    achou = (c, 1.0)
                    break
        if not achou:
            # espaço fonético: cefalexina -> cefalexin == cephalexin reduzido
            for c in candidatos(v["nome"]):
                fc = fonetico(c)
                if fc in fon_idx:
                    achou = (fon_idx[fc], 1.0)
                    break
                prox = difflib.get_close_matches(fc, fon_chaves, n=1, cutoff=0.90)
                if prox:
                    r = difflib.SequenceMatcher(None, fc, prox[0]).ratio()
                    if achou is None or r > achou[1]:
                        achou = (fon_idx[prox[0]], r)
        if not achou:
            for c in candidatos(v["nome"]):
                prox = difflib.get_close_matches(c, chaves, n=1, cutoff=0.90)
                if prox:
                    r = difflib.SequenceMatcher(None, c, prox[0]).ratio()
                    if achou is None or r > achou[1]:
                        achou = (prox[0], r)
        if achou is None:
            perdidos.append(v["nome"])
            continue
        chave, score = achou
        # Similaridade alta NÃO basta: norfloxacino x ofloxacin dá 0.90 e é outro
        # fármaco. Comparar na forma fonética e exigir o mesmo começo — é o
        # começo que carrega a identidade da molécula.
        fa = fonetico(norm(v["nome"]).split()[0] if norm(v["nome"]) else "")
        fb = fonetico(chave.split()[0] if chave else "")
        prefixo_ok = bool(fa) and bool(fb) and fa[:3] == fb[:3]
        rf = difflib.SequenceMatcher(None, fa, fb).ratio() if fa and fb else 0
        # Sinônimo curado à mão já foi verificado; o guarda existe para
        # adivinhação por similaridade, não para o que eu conferi.
        if not curado and not (prefixo_ok and (score >= 0.93 or rf >= 0.86)):
            duvidosos.append((v["nome"], idx[chave][2], round(score, 3), round(rf, 3)))
            continue
        casados[v["nome"]] = {"chave": chave, "generico": idx[chave][2],
                              "score": round(score, 3), "atc": v["atc"],
                              "via": "sinonimo" if curado else "morfologia"}

    print(f"\ncasados: {len(casados)} | duvidosos (descartados): {len(duvidosos)} | sem label: {len(perdidos)}")
    json.dump(casados, open(os.path.join(AQUI, "casados.json"), "w"), ensure_ascii=False, indent=1)
    json.dump({"duvidosos": duvidosos, "perdidos": perdidos},
              open(os.path.join(AQUI, "nao_casados.json"), "w"), ensure_ascii=False, indent=1)
    print("\nAMOSTRA de casamentos exatos:")
    for n, c in list(casados.items())[:12]:
        print(f"  {n:32s} -> {c['generico'][:40]:42s} {c['score']}")
    print("\nAMOSTRA de duvidosos DESCARTADOS:")
    for d in duvidosos[:10]:
        print(f"  {d[0]:32s} -> {d[1][:40]:42s} txt={d[2]} fon={d[3]}")


if __name__ == "__main__":
    main()
