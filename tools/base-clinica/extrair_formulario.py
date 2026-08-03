#!/usr/bin/env python3
"""Extrai o formulário do darwin-MFC: 727 nomes em português, com ATC.

O darwin-MFC entra como FORMULÁRIO, nunca como fonte — em 1039 entradas há 9
campos de citação e os arquivos se chamam expansao-600-final/ultimo. A lista diz
o que importa na prática dele; o conteúdo vem do rótulo aprovado.
"""
import json, os, re, sys

RAIZ = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/darwin-MFC/lib/data/medicamentos")
saida = {}
for f in sorted(os.listdir(RAIZ)):
    if not f.endswith(".ts"):
        continue
    s = open(os.path.join(RAIZ, f), encoding="utf-8", errors="ignore").read()
    for m in re.finditer(r"nomeGenerico:\s*'([^']+)'", s):
        nome = m.group(1).strip()
        janela = s[m.start():m.start() + 1200]
        atc = re.search(r"atcCode:\s*'([^']+)'", janela)
        rx = re.search(r"rxNormCui:\s*'([0-9]+)'", janela)
        classe = re.search(r"classeTerapeutica:\s*'([^']+)'", janela)
        if nome and nome.lower() not in saida:
            saida[nome.lower()] = {"nome": nome, "atc": atc.group(1) if atc else None,
                                   "rxcui": rx.group(1) if rx else None,
                                   "classe": classe.group(1) if classe else None,
                                   "arquivo": f}
json.dump(saida, sys.stdout, ensure_ascii=False, indent=0)
