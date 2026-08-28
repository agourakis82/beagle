# -*- coding: utf-8 -*-
"""Mede se a VALÊNCIA desloca a fala, ou se ela só aparece no prompt.

Três medidas, da mais fraca para a mais forte:

  1. PAPAGAIO — a resposta repete o adjetivo da faixa ("desagradável", "agradável"...)?
     Se o único efeito da valência é o adjetivo reaparecer, o vetor é substituição de string.

  2. DIVERGÊNCIA — quanto o léxico muda entre valências (Jaccard sobre palavras de conteúdo).
     Comparada com a divergência entre REPETIÇÕES da MESMA valência, que é o piso de ruído do
     modelo. Se divergir entre valências ≈ divergir consigo mesma, o vetor não fez nada.
     Sem esse piso o número é indefensável: qualquer LLM varia sozinho a cada chamada.

  3. MONOTONICIDADE — a divergência cresce com a distância |Δvalência|? Um vetor que dirige
     produz vizinhança: −0.8 deve estar mais perto de −0.3 do que de +0.8. Se a correlação
     for nula, o que existe são cinco baldes rotulados, não um eixo contínuo.

Uso: mede-deslocamento.py <arquivo-da-varredura>
"""
import sys, re, itertools, statistics

FAIXAS = {"-0.8":"muito desagradável","-0.3":"desagradável","0.0":"neutro",
          "0.3":"agradável","0.8":"muito agradável"}
VAZIAS = set("""a o e de da do que em um uma os as no na para com por se não sim ao à é foi
era ser está estar isso isto aqui ali mais menos muito pouco você seu sua te lhe eu meu minha
como quando onde mas porém já ainda também só entre sobre sem até depois antes""".split())

def carrega(caminho):
    blocos, atual = {}, None
    for linha in open(caminho, encoding="utf-8"):
        m = re.match(r"@@@ valencia=(\S+) rep=(\S+)", linha)
        if m:
            atual = (m.group(1), m.group(2)); blocos[atual] = []
        elif atual:
            blocos[atual].append(linha)
    return {k: "".join(v).strip() for k, v in blocos.items()}

def palavras(t):
    return {w for w in re.findall(r"[a-zà-ÿ]{4,}", t.lower()) if w not in VAZIAS}

def jaccard(a, b):
    A, B = palavras(a), palavras(b)
    return 1 - len(A & B) / len(A | B) if (A | B) else 0.0

def main(caminho):
    b = carrega(caminho)
    if not b: print("nada lido"); return
    vals = sorted({k[0] for k in b}, key=lambda x: (x == "null", float(x) if x != "null" else 0))
    print("valências lidas:", ", ".join(vals))

    print("\n1. PAPAGAIO — o adjetivo da faixa aparece na resposta?")
    for v in vals:
        if v not in FAIXAS: continue
        alvo = FAIXAS[v]
        hits = sum(1 for k, t in b.items() if k[0] == v and alvo.split()[-1] in t.lower())
        n = sum(1 for k in b if k[0] == v)
        print(f"   valência {v:>5} ('{alvo}'): {hits}/{n}")

    dentro, entre = [], []
    for v in vals:
        reps = [t for k, t in b.items() if k[0] == v]
        dentro += [jaccard(x, y) for x, y in itertools.combinations(reps, 2)]
    for v1, v2 in itertools.combinations(vals, 2):
        for t1 in [t for k, t in b.items() if k[0] == v1]:
            for t2 in [t for k, t in b.items() if k[0] == v2]:
                entre.append((abs(float(v1) - float(v2)) if "null" not in (v1, v2) else None,
                              jaccard(t1, t2)))

    print("\n2. DIVERGÊNCIA léxica (0 = idênticas, 1 = nada em comum)")
    if dentro:
        print(f"   entre REPETIÇÕES da mesma valência (piso de ruído): {statistics.mean(dentro):.3f}  (n={len(dentro)})")
    else:
        print("   entre REPETIÇÕES: SEM DADO — rode com repetições > 1, senão não há piso e o")
        print("   número abaixo não significa nada.")
    e = [d for _, d in entre]
    print(f"   entre VALÊNCIAS diferentes .....................: {statistics.mean(e):.3f}  (n={len(e)})")
    if dentro:
        delta = statistics.mean(e) - statistics.mean(dentro)
        print(f"   → efeito da valência acima do ruído: {delta:+.3f}")
        if delta <= 0.02:
            print("   VEREDITO: o vetor NÃO desloca a fala além do ruído do próprio modelo.")

    print("\n3. MONOTONICIDADE — divergência cresce com |Δvalência|?")
    pares = [(dv, dj) for dv, dj in entre if dv is not None]
    if len(pares) >= 4:
        xs = [p[0] for p in pares]; ys = [p[1] for p in pares]
        mx, my = statistics.mean(xs), statistics.mean(ys)
        num = sum((x-mx)*(y-my) for x, y in pares)
        den = (sum((x-mx)**2 for x in xs) * sum((y-my)**2 for y in ys)) ** 0.5
        r = num/den if den else 0.0
        print(f"   correlação(|Δvalência|, divergência) = {r:+.3f}  (n={len(pares)} pares)")
        print("   r≈0 ⇒ não há eixo: são baldes rotulados, não um vetor contínuo.")
    else:
        print("   pares insuficientes")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
