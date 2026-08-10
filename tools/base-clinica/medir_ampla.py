#!/usr/bin/env python3
"""Mede quantos ATIVOS DISTINTOS existem no dump da openFDA e estima o tamanho.

Os 261.258 sao rotulos de PRODUTO. O eixo que importa e principio ativo: muitos
rotulos sao o mesmo farmaco de fabricantes diferentes. Indexar por produto
multiplicaria a base sem acrescentar informacao clinica.
"""
import json, glob, sys, collections

ativos = collections.Counter()
bytes_secoes = 0
for caminho in sorted(glob.glob(sys.argv[1] + "/*.json")):
    with open(caminho, encoding="utf-8") as f:
        d = json.load(f)
    for r in d.get("results", []):
        nome = ((r.get("openfda") or {}).get("generic_name") or [None])[0]
        if not nome:
            continue
        chave = nome.strip().lower()
        # So conta o tamanho da PRIMEIRA vez que vemos o ativo: e o que a base
        # vai guardar (um rotulo por ativo, o melhor).
        if chave not in ativos:
            for campo in ("dosage_and_administration", "warnings",
                          "use_in_specific_populations", "how_supplied"):
                for t in (r.get(campo) or []):
                    bytes_secoes += len(t.encode("utf-8"))
        ativos[chave] += 1

print("ativos distintos: %d" % len(ativos))
print("rotulos totais:   %d" % sum(ativos.values()))
print("texto util:       %.0f MB" % (bytes_secoes / 1048576))
print("base estimada:    %.0f MB (texto + indice FTS ~1.6x)" % (bytes_secoes * 1.6 / 1048576))
