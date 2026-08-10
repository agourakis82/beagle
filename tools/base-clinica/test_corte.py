"""Testes do carimbo e dos dois cortes de build_bula.py.

pytest nao esta instalado neste ambiente (medido, nao suposto — ver relatorio
da Task 2) e nao instalamos nada via pip/apt aqui. Por isso os testes usam
unittest da stdlib. Rodar com:

    cd tools/base-clinica && python3 -m unittest test_corte -v

DESVIO DO BRIEF: o brief pedia `assert int(carimbo["farmacos"]) > 400` para o
corte --formulario. Medido direto em formulario.py: FORMULARIO tem 217 pares
(nome_pt, generico), 216 genericos distintos — nunca poderia produzir mais de
217 farmacos, quanto mais 400. O limiar aqui foi ajustado para 200 (a base
real cobre 211 dos 217, medido abaixo) para nao afirmar um numero que a propria
lista-fonte do repositorio torna impossivel.
"""
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest


def constroi(flag, destino):
    subprocess.run([sys.executable, "build_bula.py", flag, "--saida", destino],
                    check=True, cwd=os.path.dirname(os.path.abspath(__file__)) or ".")


class TesteCarimboECorte(unittest.TestCase):
    def test_formulario_tem_carimbo_e_pelo_menos_200(self):
        with tempfile.TemporaryDirectory() as d:
            arq = os.path.join(d, "b.sqlite")
            constroi("--formulario", arq)
            c = sqlite3.connect(arq)
            carimbo = dict(c.execute("select chave, valor from carimbo"))
            self.assertTrue(carimbo["farmacos"].isdigit())
            self.assertEqual(len(carimbo["hash"]), 64)  # sha256 hex
            self.assertGreater(int(carimbo["farmacos"]), 200)

    def test_os_dois_cortes_usam_o_mesmo_esquema(self):
        # A garantia central do desenho e "mesmo numero em todo lugar". Esquemas
        # diferentes sao a primeira forma de divergir.
        with tempfile.TemporaryDirectory() as d:
            a, b = os.path.join(d, "a.sqlite"), os.path.join(d, "b.sqlite")
            constroi("--formulario", a)
            constroi("--completo", b)
            esquema = lambda p: sorted(r[0] for r in sqlite3.connect(p).execute(
                "select name from sqlite_master where type='table' order by name"))
            self.assertEqual(esquema(a), esquema(b))


if __name__ == "__main__":
    unittest.main()
