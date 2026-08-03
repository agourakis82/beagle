# Base clínica citável (offline)

Constrói `bula.sqlite`, embarcado no app iOS, que dá ao modelo do aparelho o
**parágrafo para copiar** quando a rede cai dentro do hospital. A base não
ensina o modelo: todo número que ele diz tem que sair daqui, citado.

Duas camadas, nunca misturadas:

| camada | fonte | o que responde |
|---|---|---|
| bula | rótulos aprovados via openFDA/DailyMed (`set_id` + data) | "qual a dose deste fármaco" |
| PCDT | PDFs do Ministério da Saúde/CONITEC (documento + página) | "qual a conduta no SUS" |

## Reconstruir

```sh
python3 extrair_formulario.py ~/darwin-MFC/lib/data/medicamentos > formulario_dele.json
./baixar_bulk.sh         # 14 partições, 1,8 GB, 261k rótulos — sem limite de requisição
python3 casar.py         # casa 727 nomes PT com o corpus; gera casados.json
python3 build_bula2.py   # escreve bula.sqlite com 507 fármacos
python3 build_pcdt.py    # anexa 337 trechos de PCDT (PDFs cacheados em pcdt_pdf/)
```

`build_bula.py` é a versão antiga, por consulta à API — serve para um punhado de
fármacos, mas openFDA sem chave dá **1000 requisições/dia por IP**; para o
formulário inteiro use o lote.

`consulta.py` é o protótipo da recuperação. **O que roda de verdade é o `BulaStore`
em Swift** (`beagle-ios/.../BeagleCore/ConversationStore.swift`) — teste sempre a
porta, não só o protótipo: as duas divergiram na escolha da janela e só apareceu
compilando o Swift num harness `swiftc` isolado.

## Armadilhas que já custaram caro

- **Similaridade de texto não separa grafia diferente de fármaco diferente.**
  Norfloxacino x OFLOXACIN = 0,90. Aciclovir x GANCICLOVIR = 0,90. Seria a dose
  errada do remédio errado. Guarda: comparar na forma fonética e exigir os **3
  primeiros caracteres iguais** — é o começo que carrega a identidade da
  molécula. Sinônimo curado à mão é isento do guarda; adivinhação não é.
- **Sal em dois idiomas.** O índice guarda `TRAMADOL HYDROCHLORIDE`; remover só
  "cloridrato" perde o casamento. 68 fármacos entraram só com isso.

- **openFDA devolve produto combinado.** `metformin hydrochloride` puxava o label
  do ZITUVIM (sitagliptina+metformina): posologia de combinação respondendo por
  fármaco isolado. `melhor()` ordena produto isolado primeiro.
- **PDF do MS tem layout 2D.** Achatar tabela cola cabeçalho de coluna em prosa e
  pode encostar um número na linha errada. Só entra prosa de conduta — o filtro
  derruba 1295 para 337, e a queda é o ponto.
- **Plone não serve o arquivo na URL do objeto**: use `/@@display-file/file`.
- **Busca por assunto ignora população.** "enoxaparina, ClCr 30" traz o PCDT de
  trombofilia na gestação (40 mg). O prompt manda descartar trecho de população
  diferente e dizer por quê.

## O que NÃO entra

`darwin-MFC/lib/data/medicamentos-expanded.ts`: 24 fármacos, **zero** campos de
citação, e o `CONTENT_VALIDATION_STRATEGY.md` do próprio projeto descreve o
método como "AI synthesis". Serve como índice do que importa; não como fonte.

## Pendente

Bulário ANVISA (português, bula brasileira de verdade): a API devolve 403 (WAF).
