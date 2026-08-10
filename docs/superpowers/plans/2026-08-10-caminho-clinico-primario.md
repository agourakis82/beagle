# Caminho clínico primário — plano de implementação

> **Para quem executa:** SUB-SKILL OBRIGATÓRIA: use `superpowers:subagent-driven-development` (recomendado) ou `superpowers:executing-plans` para implementar tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** fazer a base clínica verbatim ser o caminho primário para número clínico em TODAS as superfícies (telefone online, relógio, telefone offline), com o número verificado mecanicamente contra a fonte antes de chegar à tela.

**Arquitetura:** um construtor gera duas cópias da mesma base (servidor ampla, telefone estreita) a partir do mesmo código. O cockpit ganha um módulo de consulta isolado (`bula-store.mjs`) que espelha a API que o app já tem em Swift. O `completeChatRequest` consulta antes de montar o prompt. Um guarda mecânico confere cada quantidade clínica da resposta contra os trechos entregues.

**Tecnologias:** Node 20 + `node:sqlite`/`better-sqlite3` (FTS5), `node:test`, Swift 6 no app, Kubernetes (PVC Ceph), Python 3 nos construtores.

**Spec:** `docs/superpowers/specs/2026-08-10-caminho-clinico-primario-design.md`

## Restrições globais

- **O número nunca é gerado, só copiado.** Toda quantidade clínica na resposta tem que aparecer verbatim num trecho entregue. Não converter, não arredondar, não extrapolar.
- **Falso positivo do guarda é pior que o bug.** Nenhuma checagem pode reprovar resposta legítima. Todo guarda tem teste NEGATIVO antes do positivo.
- **Paridade é a garantia central.** Mesma pergunta, mesmo trecho, mesma citação, no servidor e no telefone, para fármacos presentes nos dois.
- **A conversa íntima não é contaminada.** Sem sinal clínico, o caminho é o de hoje, intocado.
- **Estilo do repositório:** comentários em português explicando o PORQUÊ, mensagens de commit longas explicando a causa. Testes com `node:test` no cockpit (`npm test` em `apps/project-cockpit`), `swift test` no pacote iOS.
- **Tipos que já existem e devem ser espelhados** (`BeagleCore/ConversationStore.swift`):
  - `BulaTrecho { nomePT, generico, citacao, texto }`
  - `PCDTTrecho { texto, citacao }`
  - `consulta(_ pergunta: String) -> BulaTrecho?`
  - `consultaPCDT(_ pergunta: String, limite: Int = 2) -> [PCDTTrecho]`
- **Esquema da base (não mudar):** `farmaco(id, nome_pt, generico, marcas, set_id, versao, fonte, citacao)`, `secao(id, farmaco_id, chave, titulo, texto)`, `busca` FTS5, `pcdt(id, titulo, url, pagina, texto, citacao)`, `pcdt_busca` FTS5.

---

### Task 1: Medir o tamanho real da base ampla

O spec estima ~300 MB extrapolando os 29 MB dos 507 atuais. Se passar de alguns GB, a escolha do volume muda. Medir antes de decidir.

**Arquivos:**
- Criar: `tools/base-clinica/medir_ampla.py`

**Interfaces:**
- Produz: um número (MB) e a contagem de ativos distintos, impressos no stdout.

- [ ] **Passo 1: escrever o medidor**

```python
#!/usr/bin/env python3
"""Mede quantos ATIVOS DISTINTOS existem no dump da openFDA e estima o tamanho.

Os 261.258 são rótulos de PRODUTO. O eixo que importa é princípio ativo: muitos
rótulos são o mesmo fármaco de fabricantes diferentes. Indexar por produto
multiplicaria a base sem acrescentar informação clínica.
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
        # Só conta o tamanho da PRIMEIRA vez que vemos o ativo: é o que a base
        # vai guardar (um rótulo por ativo, o melhor).
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
```

- [ ] **Passo 2: rodar contra o dump**

Rodar: `python3 tools/base-clinica/medir_ampla.py <dir-do-dump-openfda>`
Esperado: imprime os quatro números.

- [ ] **Passo 3: registrar a decisão no spec**

Se a base estimada ≤ 1 GB, seguir com PVC de 4 Gi. Se maior, abrir uma nota no spec e parar para decidir. Editar a seção "Arquitetura" do spec substituindo "Tamanho ESTIMADO em ~300 MB" pelo número medido.

- [ ] **Passo 4: commit**

```bash
git add tools/base-clinica/medir_ampla.py docs/superpowers/specs/2026-08-10-caminho-clinico-primario-design.md
git commit -m "base-clinica: medir o tamanho real da base ampla antes de escolher o volume

O spec estimava ~300 MB extrapolando os 29 MB dos 507 atuais. Extrapolacao de
guardanapo nao pode virar premissa de arquitetura: se passar de alguns GB, a
escolha do volume muda.

Mede por ATIVO DISTINTO, nao por rotulo: os 261.258 sao produtos, e muitos sao
o mesmo farmaco de fabricantes diferentes."
```

---

### Task 2: Construtor com dois cortes, um código só

**Arquivos:**
- Modificar: `tools/base-clinica/build_bula.py`
- Criar: `tools/base-clinica/test_corte.py`

**Interfaces:**
- Produz: `build_bula.py --completo --saida <arq>` e `build_bula.py --formulario --saida <arq>`; ambos gravam a tabela `carimbo(chave TEXT PRIMARY KEY, valor TEXT)` com `versao_dump`, `data`, `farmacos`, `hash`.
- Consumido por: Task 8 (deploy) e Task 9 (paridade).

- [ ] **Passo 1: escrever o teste do carimbo e do corte**

```python
# tools/base-clinica/test_corte.py
import sqlite3, subprocess, sys, os, tempfile

def constroi(flag, destino):
    subprocess.run([sys.executable, "build_bula.py", flag, "--saida", destino],
                   check=True, cwd=os.path.dirname(__file__) or ".")

def test_formulario_tem_carimbo_e_507():
    with tempfile.TemporaryDirectory() as d:
        arq = os.path.join(d, "b.sqlite")
        constroi("--formulario", arq)
        c = sqlite3.connect(arq)
        carimbo = dict(c.execute("select chave, valor from carimbo"))
        assert carimbo["farmacos"].isdigit()
        assert len(carimbo["hash"]) == 64          # sha256 hex
        assert int(carimbo["farmacos"]) > 400

def test_os_dois_cortes_usam_o_mesmo_esquema():
    # A garantia central do desenho e "mesmo numero em todo lugar". Esquemas
    # diferentes sao a primeira forma de divergir.
    with tempfile.TemporaryDirectory() as d:
        a, b = os.path.join(d, "a.sqlite"), os.path.join(d, "b.sqlite")
        constroi("--formulario", a)
        constroi("--completo", b)
        esquema = lambda p: sorted(r[0] for r in sqlite3.connect(p).execute(
            "select name from sqlite_master where type='table' order by name"))
        assert esquema(a) == esquema(b)
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `cd tools/base-clinica && python3 -m pytest test_corte.py -x -q`
Esperado: FALHA — `build_bula.py` não aceita `--completo`/`--formulario`/`--saida`.

- [ ] **Passo 3: implementar os dois cortes e o carimbo**

Em `build_bula.py`, antes de `main()`:

```python
import argparse, hashlib, datetime

def parse_args():
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--completo", action="store_true",
                   help="todos os ativos distintos — base do SERVIDOR")
    g.add_argument("--formulario", action="store_true",
                   help="so os farmacos do formulario dele — base do TELEFONE")
    p.add_argument("--saida", required=True)
    return p.parse_args()

def gravar_carimbo(db, versao_dump):
    """O carimbo e o que permite dizer, com FATO, se um farmaco tambem existe na
    base local — em vez de supor. E o que sustenta o aviso de 'isto nao vai te
    acompanhar offline'."""
    db.execute("CREATE TABLE IF NOT EXISTS carimbo (chave TEXT PRIMARY KEY, valor TEXT)")
    n = db.execute("SELECT COUNT(*) FROM farmaco").fetchone()[0]
    # Hash do CONTEUDO, nao do arquivo: dois builds do mesmo dump tem que bater.
    h = hashlib.sha256()
    for (g,) in db.execute("SELECT generico FROM farmaco ORDER BY generico"):
        h.update((g or "").encode("utf-8"))
    for chave, valor in [("versao_dump", versao_dump),
                         ("data", datetime.date.today().isoformat()),
                         ("farmacos", str(n)),
                         ("hash", h.hexdigest())]:
        db.execute("INSERT OR REPLACE INTO carimbo VALUES (?,?)", (chave, valor))
    db.commit()
```

E em `main()`, escolher a lista de fármacos pelo corte:

```python
    args = parse_args()
    alvo = FORMULARIO if args.formulario else todos_os_ativos_do_dump()
    # ... constroi normalmente em args.saida ...
    gravar_carimbo(db, versao_dump=os.environ.get("OPENFDA_VERSAO", "desconhecida"))
```

- [ ] **Passo 4: rodar e ver passar**

Rodar: `cd tools/base-clinica && python3 -m pytest test_corte.py -x -q`
Esperado: 2 passed.

- [ ] **Passo 5: commit**

```bash
git add tools/base-clinica/build_bula.py tools/base-clinica/test_corte.py
git commit -m "base-clinica: um codigo, dois cortes, e um carimbo em cada base

A garantia que o desenho vende e 'mesmo numero em todo lugar'. Se a base do
servidor e a do telefone nascem de codigo diferente, isso e intencao, nao
garantia — duas normalizacoes de nome, duas regras de escolha do melhor rotulo,
duas chances de divergir.

--completo (servidor, todos os ativos distintos) e --formulario (telefone, os
507) saem do MESMO codigo.

O carimbo (versao do dump, data, contagem, hash do conteudo) e o que permite
dizer com FATO se um farmaco tambem existe na base local, sustentando o aviso
de 'isto nao vai te acompanhar offline' em vez de supor."
```

---

### Task 3: `bula-store.mjs` — consulta e citação no servidor

Espelha a API que o app já tem em Swift. Não sabe o que é LLM, não conversa com ninguém: recebe texto, devolve trecho ou nada.

**Arquivos:**
- Criar: `apps/project-cockpit/server/bula-store.mjs`
- Criar: `apps/project-cockpit/server/bula-store.test.mjs`

**Interfaces:**
- Produz:
  - `abrirBase(caminho) -> Base | null`
  - `consulta(base, pergunta) -> { nomePT, generico, citacao, texto } | null`
  - `consultaPCDT(base, pergunta, limite = 2) -> [{ texto, citacao }]`
  - `carimbo(base) -> { versaoDump, data, farmacos, hash }`
- Consumido por: Tasks 5, 6, 7.

- [ ] **Passo 1: escrever os testes, o NEGATIVO primeiro**

```javascript
// apps/project-cockpit/server/bula-store.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { abrirBase, consulta, consultaPCDT, carimbo } from "./bula-store.mjs";

const BASE = process.env.BULA_DB || "/var/lib/bula/bula.sqlite";
const base = abrirBase(BASE);

// ---- os que impedem entregar a bula ERRADA ----

test("aciclovir NAO casa com ganciclovir", { skip: !base }, () => {
  const r = consulta(base, "dose de aciclovir endovenoso");
  if (r) assert.ok(!/ganciclovir/i.test(r.generico), `casou errado: ${r.generico}`);
});

test("metformina nao traz a associacao com sitagliptina", { skip: !base }, () => {
  const r = consulta(base, "dose de metformina");
  if (r) assert.ok(!/sitagliptin/i.test(r.generico), `trouxe associacao: ${r.generico}`);
});

test("farmaco ausente devolve null, nunca aproximacao", { skip: !base }, () => {
  assert.equal(consulta(base, "dose de xisplogrina zeta"), null);
});

// ---- os que provam que serve ----

test("enoxaparina devolve trecho com citacao", { skip: !base }, () => {
  const r = consulta(base, "dose profilatica de enoxaparina");
  assert.ok(r, "nao achou enoxaparina");
  assert.match(r.generico, /enoxaparin/i);
  assert.ok(r.citacao.length > 10, "citacao vazia");
  assert.ok(r.texto.length > 50, "texto curto demais");
});

test("carimbo tem os quatro campos", { skip: !base }, () => {
  const c = carimbo(base);
  assert.ok(Number(c.farmacos) > 0);
  assert.equal(c.hash.length, 64);
});

test("base inexistente devolve null, nao lanca", () => {
  assert.equal(abrirBase("/caminho/que/nao/existe.sqlite"), null);
});
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `cd apps/project-cockpit && npm test 2>&1 | grep bula-store`
Esperado: FALHA — módulo não existe.

- [ ] **Passo 3: implementar**

```javascript
// apps/project-cockpit/server/bula-store.mjs
//
// Consulta a base clinica verbatim. Espelha BulaStore do app (Swift) — mesma
// tabela, mesma busca FTS5, mesmo formato de citacao.
//
// POR QUE ESPELHAR EM VEZ DE INVENTAR: a garantia do desenho e que ele recebe o
// MESMO numero, da MESMA fonte, com a MESMA citacao, no telefone e no relogio,
// com rede e sem. Duas implementacoes de busca sao duas chances de divergir — e
// divergir aqui e dois numeros diferentes para a mesma pergunta.
//
// Este modulo NAO sabe o que e um LLM e nao conversa com ninguem: recebe texto,
// devolve trecho ou nada. E por isso que ele e testavel sozinho, e ele e a peca
// de que depende a seguranca clinica.

import { DatabaseSync } from "node:sqlite";

/** Palavras que NUNCA devem virar nome de farmaco na extracao. */
const PARADAS = new Set([
  "para", "dose", "doses", "posologia", "quanto", "quantas", "de", "do", "da",
  "com", "sem", "em", "no", "na", "o", "a", "um", "uma", "paciente", "adulto",
  "renal", "hepatico", "endovenoso", "oral", "profilaxia", "tratamento",
]);

export function abrirBase(caminho) {
  try {
    const db = new DatabaseSync(caminho, { readOnly: true });
    db.prepare("SELECT 1 FROM farmaco LIMIT 1").get();
    return db;
  } catch {
    // Base ausente nao e excecao: e um estado que o chamador trata (responde
    // marcado, sem fonte). Lancar aqui derrubaria o chat inteiro.
    return null;
  }
}

function normalizar(s) {
  return (s || "").toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
}

export function consulta(base, pergunta) {
  if (!base) return null;
  const palavras = normalizar(pergunta).split(" ")
    .filter((p) => p.length >= 4 && !PARADAS.has(p));
  for (const palavra of palavras) {
    const linha = base.prepare(
      `SELECT f.id, f.nome_pt, f.generico, f.citacao
         FROM farmaco f
        WHERE lower(f.generico) LIKE ?1 OR lower(f.nome_pt) LIKE ?1
        ORDER BY length(f.generico) ASC
        LIMIT 1`
    ).get(palavra + "%");
    if (!linha) continue;
    // CASAMENTO ESTRITO: o nome do produto tem que COMECAR pelo farmaco pedido.
    // Similaridade de texto ja fez aciclovir casar com GANCICLOVIR e metformina
    // trazer sitagliptina+metformina. Entregar a bula errada e pior que nao
    // entregar nenhuma.
    const g = normalizar(linha.generico);
    if (!g.startsWith(palavra.slice(0, 4))) continue;
    const secoes = base.prepare(
      `SELECT titulo, texto FROM secao WHERE farmaco_id = ? ORDER BY id LIMIT 4`
    ).all(linha.id);
    if (!secoes.length) continue;
    return {
      nomePT: linha.nome_pt,
      generico: linha.generico,
      citacao: linha.citacao,
      texto: secoes.map((s) => `${s.titulo}\n${s.texto}`).join("\n\n"),
    };
  }
  return null;
}

export function consultaPCDT(base, pergunta, limite = 2) {
  if (!base) return [];
  const termos = normalizar(pergunta).split(" ")
    .filter((p) => p.length >= 4 && !PARADAS.has(p));
  if (!termos.length) return [];
  try {
    return base.prepare(
      `SELECT p.texto, p.citacao FROM pcdt_busca b
         JOIN pcdt p ON p.id = b.pcdt_id
        WHERE pcdt_busca MATCH ? LIMIT ?`
    ).all(termos.join(" OR "), limite);
  } catch {
    return [];
  }
}

export function carimbo(base) {
  if (!base) return null;
  const linhas = base.prepare("SELECT chave, valor FROM carimbo").all();
  const m = Object.fromEntries(linhas.map((l) => [l.chave, l.valor]));
  return { versaoDump: m.versao_dump, data: m.data, farmacos: m.farmacos, hash: m.hash };
}
```

- [ ] **Passo 4: rodar e ver passar**

Rodar: `cd apps/project-cockpit && BULA_DB=<caminho-da-base-de-teste> npm test 2>&1 | grep -E "^# (tests|pass|fail)"`
Esperado: os testes de bula-store passam; os `skip` só se a base não estiver montada.

- [ ] **Passo 5: commit**

```bash
git add apps/project-cockpit/server/bula-store.mjs apps/project-cockpit/server/bula-store.test.mjs
git commit -m "cockpit: bula-store — a consulta clinica do lado do servidor

Espelha BulaStore do app (Swift): mesma tabela, mesma busca FTS5, mesmo formato
de citacao. Espelhar em vez de inventar porque a garantia do desenho e o MESMO
numero, da MESMA fonte, com a MESMA citacao, no telefone e no relogio, com rede
e sem — e duas implementacoes de busca sao duas chances de divergir.

Casamento ESTRITO: o produto tem que comecar pelo farmaco pedido. Similaridade
de texto ja fez aciclovir casar com GANCICLOVIR e metformina trazer
sitagliptina+metformina. Entregar a bula errada e pior que nao entregar nenhuma.

Base ausente devolve null em vez de lancar: e um estado que o chamador trata
(responde marcado, sem fonte), nao uma excecao que derruba o chat."
```

---

### Task 4: Portão de intenção clínica no servidor

**Arquivos:**
- Modificar: `apps/project-cockpit/server/bula-store.mjs`
- Modificar: `apps/project-cockpit/server/bula-store.test.mjs`

**Interfaces:**
- Produz: `pareceClinica(pergunta) -> boolean`
- Consumido por: Task 5.

- [ ] **Passo 1: escrever os testes, o NEGATIVO primeiro**

```javascript
// acrescentar em bula-store.test.mjs
import { pareceClinica } from "./bula-store.mjs";

test("conversa intima NAO dispara consulta clinica", () => {
  // Isto ja aconteceu: "cara eu to muito cansado hoje" trouxe trechos de HIV e
  // tuberculose. A conversa dele com o companion nao pode ser contaminada por bula.
  for (const q of ["cara eu to muito cansado hoje",
                   "acabei de perder um paciente e to sozinho no corredor",
                   "quem sou eu pra voce",
                   "nao aguento mais esse plantao"]) {
    assert.equal(pareceClinica(q), false, `disparou em: ${q}`);
  }
});

test("pergunta clinica dispara", () => {
  for (const q of ["dose de enoxaparina em ClCr 30",
                   "posologia da vancomicina",
                   "quanto de dipirona posso dar",
                   "qual o ajuste renal do meropenem"]) {
    assert.equal(pareceClinica(q), true, `nao disparou em: ${q}`);
  }
});
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `cd apps/project-cockpit && npm test 2>&1 | grep -c "not ok"`
Esperado: falha — `pareceClinica` não existe.

- [ ] **Passo 3: implementar com a MESMA expressão do app**

```javascript
// em bula-store.mjs
//
// A MESMA expressao do app (ConversationStore.swift:1426). Copiada de proposito:
// se os dois portoes divergirem, a mesma pergunta consulta bula com rede e nao
// consulta sem — que e exatamente a inconsistencia que este desenho existe para
// matar.
const INTENCAO_CLINICA = new RegExp(
  "\\b(dose|doses|posologia|dosagem|mg|mcg|ampola|comprimido|esquema|" +
  "tratamento|tratar|profilaxia|conduta|protocolo|ajuste|diluic|infus|" +
  "prescrev|prescric|receit|administr|via oral|intraveno|antibiotic|" +
  "quanto de|quantas|posso dar|pode dar)", "i");

export function pareceClinica(pergunta) {
  return INTENCAO_CLINICA.test(pergunta || "");
}
```

- [ ] **Passo 4: rodar e ver passar**

Rodar: `cd apps/project-cockpit && npm test 2>&1 | grep -E "^# (tests|pass|fail)"`
Esperado: `fail 1` (a pré-existente do `fetchSounioState`), nada novo.

- [ ] **Passo 5: commit**

```bash
git add apps/project-cockpit/server/bula-store.mjs apps/project-cockpit/server/bula-store.test.mjs
git commit -m "cockpit: portao de intencao clinica, a MESMA expressao do app

Nem toda mensagem consulta bula. 'Cara eu to muito cansado hoje' ja trouxe
trechos de HIV e tuberculose no offline — a conversa dele com o companion nao
pode ser contaminada.

A expressao e copiada do app de proposito. Se os dois portoes divergirem, a
mesma pergunta consulta bula com rede e nao consulta sem, que e exatamente a
inconsistencia que este desenho existe para matar."
```

---

### Task 5: O guarda do número

A peça central. Instrução não é garantia — na enoxaparina o modelo disse 40 mg com a bula dizendo 30.

**Arquivos:**
- Criar: `apps/project-cockpit/server/guarda-do-numero.mjs`
- Criar: `apps/project-cockpit/server/guarda-do-numero.test.mjs`

**Interfaces:**
- Produz: `conferirNumeros(resposta, trechos) -> { ok: boolean, inventados: string[] }`
- Consumido por: Task 6.

- [ ] **Passo 1: escrever os testes, o NEGATIVO primeiro**

```javascript
// apps/project-cockpit/server/guarda-do-numero.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { conferirNumeros } from "./guarda-do-numero.mjs";

const FONTE = ["Table 1: 30 mg administered subcutaneously once daily " +
               "(creatinine clearance <30 mL/minute). Treatment: 1 mg/kg every 12 hours."];

// ---- NEGATIVOS: nao pode reprovar resposta legitima ----

test("numero que ESTA na fonte passa", () => {
  const r = conferirNumeros("A dose e 30 mg por via subcutanea, uma vez ao dia.", FONTE);
  assert.equal(r.ok, true, JSON.stringify(r.inventados));
});

test("numero NAO clinico e ignorado", () => {
  // Idade, horario, contagem — nada disso e dose, e reprovar isso seria censurar
  // conversa normal.
  const r = conferirNumeros(
    "Voce dormiu 4 horas e ja sao 3 da manha. Sao 507 farmacos na base.", FONTE);
  assert.equal(r.ok, true, JSON.stringify(r.inventados));
});

test("comparar duas fontes divergentes passa se as duas estao entregues", () => {
  const fontes = [...FONTE, "PCDT: a dose recomendada e 40 mg ao dia."];
  const r = conferirNumeros(
    "A bula fala em 30 mg; o PCDT usa 40 mg. Os dois divergem — o protocolo daqui manda.",
    fontes);
  assert.equal(r.ok, true, JSON.stringify(r.inventados));
});

test("frequencia presente na fonte passa", () => {
  const r = conferirNumeros("1 mg/kg a cada 12 horas.", FONTE);
  assert.equal(r.ok, true, JSON.stringify(r.inventados));
});

// ---- POSITIVOS: tem que pegar o numero inventado ----

test("o erro real da enoxaparina: 40 mg com a bula dizendo 30", () => {
  const r = conferirNumeros("Para ClCr 30, use 40 mg por dia.", FONTE);
  assert.equal(r.ok, false);
  assert.ok(r.inventados.some((x) => x.includes("40")), JSON.stringify(r.inventados));
});

test("dose por peso inventada", () => {
  const r = conferirNumeros("Use 1,5 mg/kg de 12 em 12 horas.", FONTE);
  assert.equal(r.ok, false);
});

test("sem fonte nenhuma, qualquer dose e invencao", () => {
  const r = conferirNumeros("A dose e 500 mg de 8 em 8 horas.", []);
  assert.equal(r.ok, false);
});
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `cd apps/project-cockpit && npm test 2>&1 | grep -c "not ok"`
Esperado: falha — módulo não existe.

- [ ] **Passo 3: implementar**

```javascript
// apps/project-cockpit/server/guarda-do-numero.mjs
//
// O NUMERO NUNCA E GERADO, SO COPIADO.
//
// A gente entrega o trecho da bula e manda copiar. Mas quem escreve a frase
// final e o modelo, e instrucao nao e garantia: na enoxaparina ele disse 40 mg
// com a bula dizendo 30. Uma regra categorica consertou aquele caso e nao fecha
// a classe.
//
// Aqui a checagem e burra e verificavel, como o portao de fala e o guarda da
// boca: extrai toda quantidade CLINICA da resposta e confere se aparece nos
// trechos entregues. Comparacao de texto, nao julgamento.
//
// E o unico ponto do sistema em que "quase certo" pode entrar num paciente.

/** Unidades que fazem um numero ser CLINICO. Fora desta lista, e so numero:
 *  idade, horario, contagem — e reprovar isso seria censurar conversa normal. */
const UNIDADES = "mg|mcg|µg|g|kg|ml|mL|l|L|ui|UI|mEq|mmol";
const TAXAS = `(?:${UNIDADES})\\s*\\/\\s*(?:kg|m2|h|hora|min|minuto|dia|${UNIDADES})`;

const PADROES = [
  // dose e concentracao: 30 mg, 1,5 mg/kg, 5 mg/mL, 100 mcg/kg/min
  new RegExp(`\\b\\d+(?:[.,]\\d+)?\\s*(?:${TAXAS}|(?:${UNIDADES}))\\b`, "gi"),
  // frequencia: 12/12h, a cada 8 horas, 3x ao dia.
  // Entra porque errar o intervalo erra a dose DIARIA inteira.
  /\b\d+\s*\/\s*\d+\s*h\b/gi,
  /\ba cada\s+\d+(?:[.,]\d+)?\s*(?:h|horas?|min|minutos?|dias?)\b/gi,
  /\b\d+\s*x\s*(?:ao|por)\s*dia\b/gi,
];

/** Normaliza para comparar: virgula/ponto decimal, espacos, caixa. */
function normalizar(s) {
  return (s || "").toLowerCase()
    .replace(/,/g, ".")
    .replace(/\s+/g, " ")
    .replace(/\s*\/\s*/g, "/")
    .trim();
}

/** Extrai as quantidades clinicas de um texto. */
export function quantidadesClinicas(texto) {
  const achadas = [];
  for (const re of PADROES) {
    for (const m of (texto || "").matchAll(re)) achadas.push(m[0]);
  }
  return achadas;
}

/**
 * Confere se toda quantidade clinica da resposta aparece nos trechos entregues.
 *
 * `ok:false` NUNCA e para ser mostrado: e ordem de entregar o trecho citado sem
 * a frase do modelo.
 */
export function conferirNumeros(resposta, trechos) {
  const fonte = normalizar((trechos || []).join("\n"));
  const inventados = [];
  for (const q of quantidadesClinicas(resposta)) {
    const n = normalizar(q);
    if (fonte.includes(n)) continue;
    // Segunda chance: o modelo pode escrever "1 mg/kg a cada 12 horas" onde a
    // fonte diz "1 mg/kg every 12 hours". Confere o NUMERO com a unidade, que e
    // o que importa clinicamente, ignorando a redacao ao redor.
    const so = n.match(/^(\d+(?:\.\d+)?)\s*(.*)$/);
    if (so && fonte.includes(so[1]) &&
        (!so[2] || fonte.includes(so[2].split("/")[0].trim()))) continue;
    inventados.push(q);
  }
  return { ok: inventados.length === 0, inventados };
}
```

- [ ] **Passo 4: rodar e ver passar**

Rodar: `cd apps/project-cockpit && npm test 2>&1 | grep -E "^# (tests|pass|fail)"`
Esperado: todos os 7 do guarda passam; `fail 1` continua sendo só a pré-existente.

- [ ] **Passo 5: commit**

```bash
git add apps/project-cockpit/server/guarda-do-numero.mjs apps/project-cockpit/server/guarda-do-numero.test.mjs
git commit -m "cockpit: o guarda do numero — instrucao nao e garantia

A gente entrega o trecho da bula e manda copiar. Mas quem escreve a frase final
e o modelo, e na enoxaparina ele disse 40 mg com a bula dizendo 30. A regra
categorica consertou aquele caso e nao fecha a classe.

Extrai toda quantidade CLINICA da resposta e confere se aparece nos trechos
entregues. Comparacao de texto, nao julgamento — mesma disciplina do portao de
fala e do guarda da boca.

Frequencia conta como quantidade clinica: errar o intervalo erra a dose diaria
inteira.

O TESTE QUE MAIS IMPORTA E O NEGATIVO: idade, horario e contagem sao ignorados,
e resposta que compara duas fontes divergentes passa. Um guarda que censura
resposta legitima e pior que o bug que ele previne.

E o unico ponto do sistema em que 'quase certo' pode entrar num paciente."
```

---

### Task 6: Ligar no chat, com as marcas no envelope

**Arquivos:**
- Modificar: `apps/project-cockpit/server/mobile-routes.mjs`
- Modificar: `k8s/project-cockpit/deployment.yaml` (variável `BULA_DB`)

**Interfaces:**
- Consome: `abrirBase`, `consulta`, `consultaPCDT`, `pareceClinica` (Tasks 3-4), `conferirNumeros` (Task 5).
- Produz: campos novos no envelope da resposta — `clinical_source` (`"bula"` | `"pcdt"` | `null`), `clinical_unsourced` (boolean), `clinical_citations` (string[]).

- [ ] **Passo 1: abrir a base uma vez, no boot**

Em `mobile-routes.mjs`, junto dos outros imports:

```javascript
import { abrirBase, consulta, consultaPCDT, pareceClinica } from "./bula-store.mjs";
import { conferirNumeros } from "./guarda-do-numero.mjs";

// Base clinica aberta UMA vez, no boot: SQLite readonly e barato de manter
// aberto e caro de reabrir por request. `null` quando o volume nao esta
// montado — e um estado tratado (responde marcado), nao um erro.
const BASE_CLINICA = abrirBase(process.env.BULA_DB || "/var/lib/bula/bula.sqlite");
if (!BASE_CLINICA) {
  console.error("[clinico] base NAO montada — respostas clinicas sairao SEM FONTE");
}
```

- [ ] **Passo 2: consultar antes de montar o prompt**

Dentro de `completeChatRequest`, logo depois de `effectiveSystem` ficar pronto:

```javascript
  // O CAMINHO CLINICO E PRIMARIO — nao e plano B.
  //
  // Ate 10-ago a base so era consultada OFFLINE: com rede ele recebia o que o
  // modelo lembrava. As respostas sobre dose eram mais seguras quando a rede
  // caia. Retrieval deterministico com citacao vence qualquer LLM para numero
  // clinico; o modelo embrulha e contextualiza, o numero vem sempre daqui.
  let trechosClinicos = [];
  let citacoesClinicas = [];
  let semFonteClinica = false;
  if (chatSpace === "personal" && pareceClinica(prompt)) {
    const bula = consulta(BASE_CLINICA, prompt);
    const pcdt = consultaPCDT(BASE_CLINICA, prompt);
    if (bula) {
      trechosClinicos.push(
        `## Bula (VERBATIM — rotulo aprovado)\nFarmaco: ${bula.nomePT} (${bula.generico})\n` +
        `Citacao: ${bula.citacao}\n\n${bula.texto}`);
      citacoesClinicas.push(bula.citacao);
    }
    for (const p of pcdt) {
      trechosClinicos.push(`## Protocolo brasileiro (VERBATIM — PCDT)\nCitacao: ${p.citacao}\n\n${p.texto}`);
      citacoesClinicas.push(p.citacao);
    }
    semFonteClinica = trechosClinicos.length === 0;
  }
```

- [ ] **Passo 3: injetar os trechos e a regra**

Ainda em `completeChatRequest`, ao montar o prompt final:

```javascript
  const promptFinal = trechosClinicos.length
    ? `${trechosClinicos.join("\n\n---\n\n")}\n\n${prompt}`
    : prompt;

  const regraClinica = trechosClinicos.length
    ? "\n\nREGRA CLINICA: todo numero clinico que voce disser tem que ser COPIADO dos "
      + "trechos acima e vir com a citacao daquele trecho. Nunca converta, extrapole ou "
      + "arredonde. Se a bula e o PCDT divergirem, mostre os DOIS e diga que divergem — "
      + "nao escolha por ele. O trecho vale so para a populacao que descreve."
    : (semFonteClinica
        ? "\n\nAVISO: voce NAO tem fonte para este turno. Pode responder, mas deixe "
          + "explicito que o numero vem do seu conhecimento e nao de uma bula."
        : "");
  const sistemaFinal = effectiveSystem + regraClinica;
```

- [ ] **Passo 4: conferir o número antes de devolver**

No retorno de `completeChatRequest`, antes do `return`:

```javascript
  if (trechosClinicos.length) {
    const veredito = conferirNumeros(responseText, trechosClinicos);
    if (!veredito.ok) {
      // Nao entrega a frase do modelo: devolve o que a bula DIZ, citado.
      console.error(`[clinico] numero fora da fonte: ${veredito.inventados.join(", ")}`);
      responseText =
        "Nao vou te entregar esse numero: ele nao esta na fonte que eu tenho aqui. "
        + "O que a bula diz, verbatim:\n\n" + trechosClinicos.join("\n\n---\n\n");
    }
  }
```

E acrescentar ao objeto devolvido:

```javascript
    clinical_source: trechosClinicos.length ? "bula" : null,
    clinical_unsourced: semFonteClinica,
    clinical_citations: citacoesClinicas,
```

- [ ] **Passo 5: declarar a variável no deployment**

Em `k8s/project-cockpit/deployment.yaml`, no `env` do container `app`:

```yaml
        - name: BULA_DB
          value: /var/lib/bula/bula.sqlite
```

- [ ] **Passo 6: rodar os testes**

Rodar: `cd apps/project-cockpit && npm test 2>&1 | grep -E "^# (tests|pass|fail)"`
Esperado: `fail 1` (só a pré-existente).

- [ ] **Passo 7: commit**

```bash
git add apps/project-cockpit/server/mobile-routes.mjs k8s/project-cockpit/deployment.yaml
git commit -m "cockpit: o caminho clinico vira PRIMARIO, e a marca vai no envelope

Ate hoje a base so era consultada OFFLINE. Com rede ele recebia o que o modelo
lembrava — as respostas sobre dose eram mais seguras quando a rede caia. Ele e
medico e usa isto em plantao.

Agora: portao de intencao, consulta a bula e ao PCDT, trechos verbatim como
material da mensagem, regra de copiar-e-citar no sistema, e o guarda do numero
antes de devolver. Se o guarda reprova, entrega o que a bula DIZ, citado, sem a
frase do modelo.

A marca de 'sem fonte' vai no ENVELOPE (clinical_unsourced), nao como texto que
o modelo pode esquecer de escrever."
```

---

### Task 7: Carimbo e o aviso de "não acompanha offline"

**Arquivos:**
- Modificar: `apps/project-cockpit/server/mobile-routes.mjs`
- Modificar: `beagle-ios/BeagleSuite/Sources/BeagleCore/BeagleClient.swift`
- Modificar: `beagle-ios/BeagleSuite/Sources/BeagleCockpit/Companion/MessageBubble.swift`

**Interfaces:**
- Consome: `carimbo(base)` (Task 3), `clinical_source`/`clinical_unsourced` (Task 6).
- Produz: campo `clinical_offline_ok` (boolean) no envelope; marca visual na bolha.

- [ ] **Passo 1: o app manda o carimbo da base local**

Em `BeagleClient.swift`, no corpo da requisição de chat:

```swift
        // Carimbo da base LOCAL. E com ele que o servidor sabe, com fato, se o
        // farmaco que ele acabou de citar tambem existe no telefone — e portanto
        // se aquela resposta vai acompanhar ele quando a rede cair.
        if let c = BulaStore.shared.carimbo {
            corpo["bula_local_hash"] = c.hash
            corpo["bula_local_farmacos"] = c.farmacos
        }
```

- [ ] **Passo 2: o servidor responde se acompanha ou não**

Em `mobile-routes.mjs`, dentro do bloco clínico:

```javascript
    // O farmaco citado existe na base LOCAL dele?
    //
    // A cobertura online e ampla e a offline e estreita — foi a escolha dele. O
    // preco e que a mesma pergunta pode ter resposta diferente conforme a rede,
    // e ele descobre isso no pior momento: quando o sinal cai no meio de uma
    // duvida. O aviso existe para ele saber ANTES.
    const localHash = cleanString(req.body?.bula_local_hash);
    clinicalOfflineOk = Boolean(bula) && Boolean(localHash) &&
      Boolean(BASE_CLINICA_LOCAL_TEM?.(bula.generico));
```

Com o auxiliar, junto da abertura da base:

```javascript
// Lista de genericos da base ESTREITA (a mesma que vai no telefone), carregada
// uma vez. E o que permite responder "isto nao vai te acompanhar offline" como
// FATO verificado, nao suposicao.
const BASE_ESTREITA = abrirBase(process.env.BULA_DB_FORMULARIO || "/var/lib/bula/bula-formulario.sqlite");
const BASE_CLINICA_LOCAL_TEM = BASE_ESTREITA
  ? (generico) => Boolean(BASE_ESTREITA.prepare(
      "SELECT 1 FROM farmaco WHERE lower(generico) = lower(?) LIMIT 1").get(generico))
  : null;
```

E no envelope: `clinical_offline_ok: clinicalOfflineOk`.

- [ ] **Passo 3: a marca na bolha**

Em `MessageBubble.swift`, abaixo do corpo da mensagem:

```swift
    /// Marca clinica. Vai ABAIXO da fala e com peso proprio — nao pode ser um
    /// detalhe que ele precise procurar as 3h da manha.
    @ViewBuilder
    private var marcaClinica: some View {
        if message.clinicalUnsourced == true {
            Label("sem fonte — isto e o modelo, nao a bula",
                  systemImage: "exclamationmark.triangle.fill")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.postureWarm)
        } else if let citacoes = message.clinicalCitations, !citacoes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(citacoes, id: \.self) { c in
                    Text(c).font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                if message.clinicalOfflineOk == false {
                    Label("nao acompanha offline", systemImage: "wifi.slash")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.postureWarm.opacity(0.9))
                }
            }
        }
    }
```

- [ ] **Passo 4: a marca TAMBÉM no relógio**

O relógio fala com o mesmo servidor e recebe os mesmos campos. Mostrar a dose lá sem dizer de onde veio é exatamente o que este desenho existe para impedir — e no pulso, no corredor, é onde ele mais vai perguntar dose.

Em `beagle-ios/BeagleSuite/Sources/BeagleWatch/FalarView.swift`, no bloco `respondido`, abaixo do texto:

```swift
            // A PROCEDENCIA VAI JUNTO, tambem aqui.
            //
            // A tela do relogio e pequena e a tentacao e cortar o que "nao cabe".
            // A citacao nao e enfeite: e a diferenca entre um numero que ele pode
            // usar e um numero que ele precisa conferir. Se algo tem que sair para
            // caber, sai o texto do modelo, nunca a fonte.
            if semFonte {
                Label("sem fonte", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            } else if let c = citacao, !c.isEmpty {
                Text(c)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
```

E no `enviar()`, guardar os campos do envelope junto da resposta:

```swift
            semFonte = (r.value?.clinicalUnsourced == true)
            citacao  = r.value?.clinicalCitations?.first
```

com o estado correspondente:

```swift
    @State private var semFonte = false
    @State private var citacao: String?
```

- [ ] **Passo 5: compilar e testar**

Rodar: `cd beagle-ios/BeagleSuite && swift test`, o build iOS do `instalar-companion.sh`, e o build do relógio:
```bash
xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleWatch \
  -destination "generic/platform=watchOS" -derivedDataPath .derived \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Esperado: testes passam, build SUCCEEDED.

- [ ] **Passo 6: commit**

```bash
git add -A
git commit -m "clinico: o aviso de 'nao acompanha offline' vira FATO verificado

A cobertura online e ampla e a offline e estreita — escolha dele. O preco e que
a mesma pergunta pode ter resposta diferente conforme a rede, e ele descobre
isso no pior momento: quando o sinal cai no meio de uma duvida.

O app manda o carimbo (hash) da base local; o servidor confere se o farmaco
citado existe la. O aviso passa a ser verificado, nao suposto.

A marca vai ABAIXO da fala e com peso proprio: nao pode ser um detalhe que ele
precise procurar as 3h da manha."
```

---

### Task 8: Volume, base no cluster e deploy

**Arquivos:**
- Criar: `k8s/project-cockpit/bula-pvc.yaml`
- Criar: `k8s/project-cockpit/bula-build-job.yaml`
- Modificar: `k8s/project-cockpit/deployment.yaml`

**Interfaces:**
- Consome: `build_bula.py --completo/--formulario` (Task 2).
- Produz: `/var/lib/bula/bula.sqlite` e `/var/lib/bula/bula-formulario.sqlite` montados no cockpit.

- [ ] **Passo 1: o PVC**

```yaml
# k8s/project-cockpit/bula-pvc.yaml
# Volume da base clinica. Tamanho definido pela MEDICAO da Task 1 — nao pela
# estimativa de guardanapo do spec.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bula-clinica
  namespace: beagle
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd-ssd
  resources:
    requests:
      storage: 4Gi
```

- [ ] **Passo 2: o job que constrói as duas bases**

```yaml
# k8s/project-cockpit/bula-build-job.yaml
# Constroi AS DUAS bases do mesmo dump, com o mesmo codigo, na mesma execucao.
# Rodar as duas juntas nao e conveniencia: e o que garante que elas nascem do
# mesmo dump. Dois jobs em momentos diferentes podem pegar dumps diferentes, e
# ai "mesmo numero em todo lugar" volta a ser intencao.
apiVersion: batch/v1
kind: Job
metadata:
  name: bula-build
  namespace: beagle
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      securityContext:
        seccompProfile: {type: Unconfined}
      tolerations:
        - {key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}
      containers:
        - name: build
          image: 192.168.3.207:5003/base-clinica:latest
          command: ["/bin/bash", "-lc"]
          args:
            - |
              set -euo pipefail
              python3 /app/build_bula.py --completo   --saida /dados/bula.sqlite.novo
              python3 /app/build_bula.py --formulario --saida /dados/bula-formulario.sqlite.novo
              # Troca ATOMICA: o cockpit le a base o tempo todo. Escrever por cima
              # de um arquivo aberto entrega meia base para quem estiver perguntando.
              mv /dados/bula.sqlite.novo            /dados/bula.sqlite
              mv /dados/bula-formulario.sqlite.novo /dados/bula-formulario.sqlite
          volumeMounts:
            - {name: bula, mountPath: /dados}
      volumes:
        - name: bula
          persistentVolumeClaim: {claimName: bula-clinica}
```

- [ ] **Passo 3: montar no cockpit**

Em `k8s/project-cockpit/deployment.yaml`, no container `app`:

```yaml
        volumeMounts:
        - mountPath: /var/lib/bula
          name: bula-clinica
          readOnly: true
```

e em `volumes`:

```yaml
      - name: bula-clinica
        persistentVolumeClaim:
          claimName: bula-clinica
          readOnly: true
```

- [ ] **Passo 4: aplicar com o wrapper que confere**

Rodar:
```bash
kubectl apply -f k8s/project-cockpit/bula-pvc.yaml
kubectl apply -f k8s/project-cockpit/bula-build-job.yaml
kubectl -n beagle wait --for=condition=complete job/bula-build --timeout=30m
ops/aplicar.sh k8s/project-cockpit/deployment.yaml beagle
```
Esperado: `aplicar.sh` acusa zero chave duplicada, mostra o diff do volume, aplica e confirma o rollout.

- [ ] **Passo 5: provar que a base chegou**

Rodar:
```bash
kubectl -n beagle exec deploy/project-cockpit -c app -- \
  sh -c 'ls -la /var/lib/bula/ && node -e "
   import(\"/app/server/bula-store.mjs\").then(m=>{
     const b=m.abrirBase(\"/var/lib/bula/bula.sqlite\");
     console.log(m.carimbo(b));
     console.log(m.consulta(b,\"dose de enoxaparina\")?.generico);
   })"'
```
Esperado: imprime o carimbo e `enoxaparin sodium` (ou equivalente).

- [ ] **Passo 6: commit**

```bash
git add k8s/project-cockpit/bula-pvc.yaml k8s/project-cockpit/bula-build-job.yaml k8s/project-cockpit/deployment.yaml
git commit -m "k8s: volume da base clinica e job que constroi as duas juntas

As duas bases saem do MESMO dump, na MESMA execucao. Nao e conveniencia: dois
jobs em momentos diferentes podem pegar dumps diferentes, e ai 'mesmo numero em
todo lugar' volta a ser intencao em vez de garantia.

Troca atomica por mv: o cockpit le a base o tempo todo, e escrever por cima de
um arquivo aberto entrega meia base para quem estiver perguntando naquele
instante."
```

---

### Task 9: Teste de paridade servidor ↔ telefone

A garantia central do desenho. Precisa de teste próprio.

**Arquivos:**
- Criar: `apps/project-cockpit/server/paridade-clinica.test.mjs`

**Interfaces:**
- Consome: `abrirBase`, `consulta` (Task 3); as duas bases do volume (Task 8).

- [ ] **Passo 1: escrever o teste**

```javascript
// apps/project-cockpit/server/paridade-clinica.test.mjs
//
// A GARANTIA CENTRAL: mesma pergunta, mesmo trecho, mesma citacao, no servidor e
// no telefone — para os farmacos presentes nos dois.
//
// Sem este teste, "mesmo numero em todo lugar" e uma frase no spec. Duas bases
// podem divergir por normalizacao de nome, por ordem de escolha do melhor
// rotulo, ou porque alguem regerou uma so.
import test from "node:test";
import assert from "node:assert/strict";
import { abrirBase, consulta } from "./bula-store.mjs";

const AMPLA = abrirBase(process.env.BULA_DB || "/var/lib/bula/bula.sqlite");
const ESTREITA = abrirBase(process.env.BULA_DB_FORMULARIO || "/var/lib/bula/bula-formulario.sqlite");
const temAsDuas = Boolean(AMPLA && ESTREITA);

const PERGUNTAS = [
  "dose profilatica de enoxaparina",
  "posologia da vancomicina",
  "dose de meropenem",
  "ajuste renal da ampicilina",
  "dose de fenitoina",
];

test("as duas bases devolvem o MESMO farmaco e a MESMA citacao", { skip: !temAsDuas }, () => {
  for (const q of PERGUNTAS) {
    const a = consulta(AMPLA, q);
    const b = consulta(ESTREITA, q);
    if (!b) continue;                       // farmaco fora do formulario: nao ha o que comparar
    assert.ok(a, `a base ampla nao achou: ${q}`);
    assert.equal(a.generico, b.generico, `farmaco diferente em: ${q}`);
    assert.equal(a.citacao, b.citacao, `citacao diferente em: ${q}`);
  }
});

test("o texto entregue e o mesmo para os farmacos comuns", { skip: !temAsDuas }, () => {
  const a = consulta(AMPLA, "dose profilatica de enoxaparina");
  const b = consulta(ESTREITA, "dose profilatica de enoxaparina");
  if (a && b) assert.equal(a.texto, b.texto);
});
```

- [ ] **Passo 2: rodar dentro do pod (onde as duas bases existem)**

Rodar:
```bash
kubectl -n beagle exec deploy/project-cockpit -c app -- \
  sh -c 'cd /app && node --test server/paridade-clinica.test.mjs'
```
Esperado: PASS. Se falhar, as bases divergiram — investigar o construtor antes de seguir.

- [ ] **Passo 3: commit**

```bash
git add apps/project-cockpit/server/paridade-clinica.test.mjs
git commit -m "cockpit: teste de paridade — a garantia central vira verificacao

'Mesmo numero em todo lugar' e a promessa deste desenho. Sem teste proprio, e
uma frase no spec: duas bases podem divergir por normalizacao de nome, por ordem
de escolha do melhor rotulo, ou porque alguem regerou uma so.

Compara farmaco, citacao e texto entre a base ampla e a estreita para os
farmacos presentes nas duas."
```

---

### Task 10: O canário sonda a pergunta clínica

**Arquivos:**
- Modificar: `ops/canario/canario.sh`

**Interfaces:**
- Consome: o endpoint `/api/mobile/v1/chat` já sondado.

- [ ] **Passo 1: acrescentar a sonda clínica**

Em `ops/canario/canario.sh`, depois da checagem de fala:

```bash
# SONDA CLINICA: uma pergunta de resposta conhecida.
#
# Se a base sumir do volume, se o portao de intencao parar de disparar, ou se a
# citacao sumir da resposta, isto quebra em SILENCIO — o companion continua
# respondendo, so que sem fonte. E exatamente a classe de falha que custou uma
# semana inteira: existe, parece certo, e nao cobre nada.
clinico=$(curl -s -m 180 -X POST "$URL" \
  -H "content-type: application/json" -H "x-cockpit-token: $TOKEN" \
  --data '{"space":"personal","prompt":"Qual a dose profilatica de enoxaparina para clearance de creatinina abaixo de 30?"}' 2>/dev/null)

if ! grep -qF "30 mg" <<<"$clinico"; then
  falhas+=("CLINICO SEM O NUMERO: a resposta de enoxaparina nao trouxe 30 mg")
fi
if ! grep -qiE "dailymed|fda|bula" <<<"$clinico"; then
  falhas+=("CLINICO SEM CITACAO: respondeu dose sem dizer de onde veio")
fi
```

- [ ] **Passo 2: rodar e ver passar**

Rodar: `/home/devsounio/.beagle/canario/canario.sh; echo "saida=$?"`
Esperado: `saida=0`, e `journalctl -t beagle-canario -n 1` mostra OK.

- [ ] **Passo 3: provar que pega a falha**

Desmontar temporariamente a base (renomear o arquivo no volume), rodar o canário, confirmar que ele acusa `CLINICO SEM O NUMERO` e notifica. Remontar.

- [ ] **Passo 4: commit**

```bash
cp /home/devsounio/.beagle/canario/canario.sh ops/canario/canario.sh
git add ops/canario/canario.sh
git commit -m "canario: sondar uma pergunta clinica de resposta conhecida

Se a base sumir do volume, se o portao de intencao parar de disparar, ou se a
citacao sumir, isto quebra em SILENCIO: o companion continua respondendo, so que
sem fonte. E exatamente a classe de falha que custou a semana inteira — existe,
parece certo, nao cobre nada.

Enoxaparina com ClCr abaixo de 30 tem que voltar 30 mg E a citacao. Provado nos
dois sentidos: passa com a base montada, acusa com ela ausente."
```

---

## Ordem e dependências

```
1 (medir) → 2 (construtor) → 8 (volume+deploy)
                ↓                    ↓
   3 (bula-store) → 4 (portao) → 6 (ligar) → 7 (carimbo+marca)
                ↓                    ↓
             5 (guarda)          9 (paridade) → 10 (canario)
```

Tasks 3, 4 e 5 são módulos puros e podem ser feitas antes de existir volume — os testes usam `skip` quando a base não está montada.
