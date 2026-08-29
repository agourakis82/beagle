# -*- coding: utf-8 -*-
"""Mede o vetor (valência × ativação) em cada braço de ENTREGA, separadamente.

O erro a evitar é misturar os braços: descritivo e diretivo produzem textos com vocabulário
diferente por construção, e uma divergência global entre eles não diria nada sobre o vetor.
Cada braço é medido contra o SEU PRÓPRIO piso de ruído.

Medidas por braço:
  RUÍDO       — divergência entre repetições da MESMA célula (v,a). É o piso: o modelo varia
                sozinho a cada chamada, e sem esse número qualquer efeito é indefensável.
  EFEITO      — divergência entre células diferentes, menos o ruído.
  EIXOS       — correlação de |Δvalência| e de |Δativação| com a divergência, separadas.
                Um vetor real produz vizinhança em AMBOS os eixos.
  COMPRIMENTO — correlação entre ativação e tamanho da resposta. No braço diretivo esta é a
                predição explícita: ativação alta manda a coisa na primeira linha e frases
                curtas, logo o texto deve ENCURTAR. Se não encurtar, a instrução não pegou —
                e isso é falsificação direta, não impressão.
"""
import sys, re, itertools, statistics

def carrega(caminho):
    b, atual = {}, None
    for l in open(caminho, encoding="utf-8"):
        m = re.match(r"@@@ modo=(\S+) valencia=(\S+) ativacao=(\S+) rep=(\S+)", l)
        if m: atual = m.groups(); b[atual] = []
        elif atual: b[atual].append(l)
    return {k: "".join(v).strip() for k, v in b.items()}

VAZIAS = set("""a o e de da do que em um uma os as no na para com por se não sim ao à é foi era
ser estar isso isto aqui ali mais menos muito pouco você seu sua te lhe eu meu minha como quando
onde mas porém já ainda também só entre sobre sem até depois antes""".split())
pal = lambda t: {w for w in re.findall(r"[a-zà-ÿ]{4,}", t.lower()) if w not in VAZIAS}
def jac(a, b):
    A, B = pal(a), pal(b)
    return 1 - len(A & B)/len(A | B) if (A | B) else 0.0
def corr(xs, ys):
    if len(xs) < 4: return None
    mx, my = statistics.mean(xs), statistics.mean(ys)
    den = (sum((x-mx)**2 for x in xs)*sum((y-my)**2 for y in ys))**0.5
    return (sum((x-mx)*(y-my) for x, y in zip(xs, ys))/den) if den else 0.0

def braco(nome, itens):
    print(f"\n═══ braço {nome.upper()}  (n={len(itens)} respostas)")
    if len(itens) < 4: print("   amostra insuficiente"); return
    celulas = {}
    for (v, a, r), t in itens.items(): celulas.setdefault((v, a), []).append(t)

    ruido = [jac(x, y) for reps in celulas.values() for x, y in itertools.combinations(reps, 2)]
    pares = []
    for (c1, t1), (c2, t2) in itertools.combinations(
            [((v, a), t) for (v, a), ts in celulas.items() for t in ts], 2):
        if c1 == c2: continue
        pares.append((abs(float(c1[0])-float(c2[0])), abs(float(c1[1])-float(c2[1])), jac(t1, t2)))
    if not ruido:
        print("   SEM piso de ruído (rode com repetições > 1) — nenhum efeito é interpretável.")
        return
    mr, me = statistics.mean(ruido), statistics.mean([p[2] for p in pares])
    print(f"   ruído (repetições da mesma célula) ... {mr:.3f}  (n={len(ruido)})")
    print(f"   entre células diferentes ............. {me:.3f}  (n={len(pares)})")
    print(f"   → efeito do vetor acima do ruído ..... {me-mr:+.3f}")
    rv = corr([p[0] for p in pares], [p[2] for p in pares])
    ra = corr([p[1] for p in pares], [p[2] for p in pares])
    print(f"   correlação |Δvalência| × divergência .. {rv:+.3f}" if rv is not None else "")
    print(f"   correlação |Δativação| × divergência .. {ra:+.3f}" if ra is not None else "")

    xs = [float(a) for (v, a), ts in celulas.items() for _ in ts]
    ys = [len(t) for (v, a), ts in celulas.items() for t in ts]
    rc = corr(xs, ys)
    print(f"   correlação ativação × COMPRIMENTO .... {rc:+.3f}" if rc is not None else "")
    if nome == "diretivo" and rc is not None:
        print("     (o diretivo PREVÊ negativa: ativação alta ⇒ texto mais curto.", end=" ")
        print("cumpriu.)" if rc < -0.2 else "NÃO cumpriu — a instrução não pegou.)")
    if me - mr <= 0.02:
        print("   VEREDITO: o vetor não desloca a fala além do ruído do próprio modelo.")

def main(caminho):
    b = carrega(caminho)
    if not b: print("nada lido"); return
    for modo in ("descritivo", "diretivo"):
        braco(modo, {(v, a, r): t for (m, v, a, r), t in b.items() if m == modo})

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
