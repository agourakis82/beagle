# -*- coding: utf-8 -*-
"""Produto sedeniônico por Cayley–Dickson, e os fatos estruturais que decidem o desenho de ψ.

Nada aqui é citado de memória: o produto é construído por duplicação a partir de ℝ, e cada
afirmação sobre divisores de zero é VERIFICADA por busca, não assumida.
"""
import itertools, random

def conj(a):
    return (a[0],) + tuple(-x for x in a[1:])

def mul(a, b):
    n = len(a)
    if n == 1:
        return (a[0]*b[0],)
    h = n//2
    a1, a2 = a[:h], a[h:]
    b1, b2 = b[:h], b[h:]
    # (a1,a2)(b1,b2) = (a1b1 - conj(b2)a2 , b2a1 + a2conj(b1))
    p1 = tuple(x-y for x, y in zip(mul(a1, b1), mul(conj(b2), a2)))
    p2 = tuple(x+y for x, y in zip(mul(b2, a1), mul(a2, conj(b1))))
    return p1 + p2

def e(i, n=16):
    v = [0.0]*n; v[i] = 1.0; return tuple(v)

def add(*vs):
    return tuple(sum(c) for c in zip(*vs))

def zero(v, tol=1e-12):
    return all(abs(x) < tol for x in v)

def norm2(v):
    return sum(x*x for x in v)

if __name__ == "__main__":
    n = 16
    # 1) sanidade: e_i * e_i = -1 para i>0, e a norma é multiplicativa nos OCTONIÕES
    assert mul(e(3), e(3))[0] == -1.0
    ok = all(abs(norm2(mul(e(i), e(j))) - 1.0) < 1e-12 for i in range(8) for j in range(8))
    print("octoniões: norma multiplicativa nas unidades ->", ok)

    # 2) EXISTEM divisores de zero em S? busca sobre pares (e_i+e_j)(e_k+e_l)
    achados = []
    for i, j in itertools.combinations(range(1, n), 2):
        a = add(e(i), e(j))
        for k, l in itertools.combinations(range(1, n), 2):
            b = add(e(k), e(l))
            if zero(mul(a, b)):
                achados.append(((i, j), (k, l)))
    print("pares (e_i+e_j)(e_k+e_l) que ANIQUILAM:", len(achados))
    for p in achados[:5]:
        print("   e%d+e%d  x  e%d+e%d  = 0" % (p[0][0], p[0][1], p[1][0], p[1][1]))

    # 3) O FATO QUE DECIDE ψ: dois elementos DENTRO da cópia octoniônica (e0..e7)
    #    conseguem aniquilar? Busca aleatória ampla + todos os pares de base.
    pior = None
    for _ in range(200000):
        a = tuple([random.uniform(-1, 1) for _ in range(8)] + [0.0]*8)
        b = tuple([random.uniform(-1, 1) for _ in range(8)] + [0.0]*8)
        if norm2(a) < 1e-6 or norm2(b) < 1e-6: continue
        r = norm2(mul(a, b))/(norm2(a)*norm2(b))
        if pior is None or r < pior: pior = r
    print("dentro de e0..e7 (subálgebra ≅ O): menor |ab|²/(|a|²|b|²) em 200k sorteios = %.3e" % pior)

    # 4) e como fica o mesmo teste quando os dois PODEM usar as 16 coordenadas
    pior16 = None
    for _ in range(200000):
        a = tuple(random.uniform(-1, 1) for _ in range(16))
        b = tuple(random.uniform(-1, 1) for _ in range(16))
        r = norm2(mul(a, b))/(norm2(a)*norm2(b))
        if pior16 is None or r < pior16: pior16 = r
    print("em S inteiro:                       menor razão em 200k sorteios = %.3e" % pior16)

    # 5) os achados em (2) cruzam as duas metades da duplicação?
    if achados:
        cruza = sum(1 for (ij, kl) in achados
                    if (min(ij) < 8 <= max(ij)) or (min(kl) < 8 <= max(kl)))
        print("dos %d pares aniquiladores, %d têm ao menos um lado CRUZANDO e0..e7 / e8..e15"
              % (len(achados), cruza))

def estrutura_dos_aniquiladores():
    """Todos os 84 pares têm a forma (declarado_i + medido_j)? E a atribuição DENTRO de cada
    metade é gauge (todo índice serve igual) ou substantiva (alguns índices são especiais)?"""
    n = 16
    achados = []
    for i, j in itertools.combinations(range(1, n), 2):
        a = add(e(i), e(j))
        for k, l in itertools.combinations(range(1, n), 2):
            if zero(mul(a, add(e(k), e(l)))):
                achados.append(((i, j), (k, l)))
    forma = sum(1 for (ij, kl) in achados
                if ij[0] < 8 <= ij[1] and kl[0] < 8 <= kl[1])
    print("dos %d pares, %d têm AMBOS os lados na forma (declarado_i + medido_j)"
          % (len(achados), forma))

    from collections import Counter
    cd = Counter(); cm = Counter()
    for (ij, kl) in achados:
        for (x, y) in (ij, kl):
            if x < 8 <= y: cd[x] += 1; cm[y] += 1
    print("ocorrências por índice DECLARADO (e1..e7):",
          {k: cd[k] for k in sorted(cd)})
    print("ocorrências por índice MEDIDO   (e8..e15):",
          {k: cm[k] for k in sorted(cm)})

    # para um dado par declarado_i + medido_j, QUANTOS parceiros o aniquilam?
    from collections import defaultdict
    parc = defaultdict(int)
    for (ij, kl) in achados: parc[ij] += 1
    vals = sorted(set(parc.values()))
    print("parceiros aniquiladores por elemento (valores distintos):", vals)
    print("total de elementos (e_i+e_j) que são divisores de zero:", len(parc))

if __name__ == "__main__" and len(__import__("sys").argv) > 1:
    estrutura_dos_aniquiladores()
