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
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) or ".")
from build_bula import casa_formulario_no_dump


def constroi(flag, destino):
    subprocess.run([sys.executable, "build_bula.py", flag, "--saida", destino],
                    check=True, cwd=os.path.dirname(os.path.abspath(__file__)) or ".")


def _registro(generic_names, texto_dosagem):
    """Um registro minimo no formato do dump da openFDA, so com o que
    peso()/casa_formulario_no_dump usam."""
    return {
        "openfda": {"generic_name": generic_names, "spl_set_id": [], "brand_name": []},
        "set_id": "",
        "effective_time": "",
        "dosage_and_administration": [texto_dosagem],
    }


def _escreve_dump_fake(diretorio, registros):
    caminho = os.path.join(diretorio, "drug-label-0001-of-0001.json")
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump({"results": registros}, f)
    return caminho


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


class TesteCasamentoPorPalavraInteira(unittest.TestCase):
    """Achado de revisao (rodada 1): 'epinephrine' e substring de
    'norepinephrine bitartrate', e 'omeprazole' e substring de
    'esomeprazole magnesium' -- farmacos DIFERENTES, nao uma associacao do
    mesmo ativo. Casamento por substring solta deixaria os dois entrarem
    como candidatos ao alvo errado; hoje isso so nao quebra por 'sorte
    estrutural' (o rotulo certo tem generic_name exatamente igual ao alvo).
    Aqui a droga ERRADA recebe um texto de dosagem muito maior que a droga
    CERTA -- se o casamento fosse por substring, ela ainda venceria via
    peso() (texto mais completo). O teste so passa se o candidato errado for
    excluido ANTES de peso() entrar em jogo, por nao bater na palavra
    inteira."""

    def test_epinephrine_nao_traz_norepinephrine(self):
        with tempfile.TemporaryDirectory() as d:
            _escreve_dump_fake(d, [
                _registro(["EPINEPHRINE"], "dose pequena de epinefrina isolada"),
                _registro(["NOREPINEPHRINE BITARTRATE"], "dose " * 500 + "gigante de noradrenalina"),
            ])
            melhores = casa_formulario_no_dump(d, [("adrenalina", "epinephrine")])
            rec = melhores.get("epinephrine")
            self.assertIsNotNone(rec, "epinephrine devia ter sido encontrada no dump fake")
            genes = [g.lower() for g in rec["openfda"]["generic_name"]]
            self.assertEqual(genes, ["epinephrine"])
            self.assertNotIn("norepinephrine bitartrate", genes)

    def test_omeprazole_nao_traz_esomeprazole(self):
        with tempfile.TemporaryDirectory() as d:
            _escreve_dump_fake(d, [
                _registro(["OMEPRAZOLE"], "dose pequena de omeprazol isolado"),
                _registro(["ESOMEPRAZOLE MAGNESIUM"], "dose " * 500 + "gigante de esomeprazol"),
            ])
            melhores = casa_formulario_no_dump(d, [("omeprazol", "omeprazole")])
            rec = melhores.get("omeprazole")
            self.assertIsNotNone(rec, "omeprazole devia ter sido encontrada no dump fake")
            genes = [g.lower() for g in rec["openfda"]["generic_name"]]
            self.assertEqual(genes, ["omeprazole"])
            self.assertNotIn("esomeprazole magnesium", genes)

    def test_metformina_ainda_casa_dentro_da_combinacao(self):
        # Nao pode virar regressao inversa: a palavra inteira 'metformin
        # hydrochloride' precisa continuar batendo dentro de uma frase maior
        # (o caso ZITUVIM), so nao pode bater como substring solta.
        with tempfile.TemporaryDirectory() as d:
            _escreve_dump_fake(d, [
                _registro(["METFORMIN HYDROCHLORIDE"], "dose isolada de metformina"),
                _registro(["SITAGLIPTIN AND METFORMIN HYDROCHLORIDE"], "dose " * 500 + "da combinacao"),
            ])
            melhores = casa_formulario_no_dump(d, [("metformina", "metformin hydrochloride")])
            rec = melhores.get("metformin hydrochloride")
            self.assertIsNotNone(rec)
            genes = [g.lower() for g in rec["openfda"]["generic_name"]]
            # isolado tem que vencer mesmo com muito menos texto (peso() prioriza isolado > combinado)
            self.assertEqual(genes, ["metformin hydrochloride"])


if __name__ == "__main__":
    unittest.main()
