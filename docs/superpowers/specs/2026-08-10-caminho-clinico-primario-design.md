# O caminho clínico como primário

**Data:** 10-ago-2026
**Estado:** desenho aprovado, não implementado

## O problema

A base clínica offline (507 fármacos com rótulo FDA verbatim + 337 trechos de PCDT)
é consultada **apenas quando não há rede**. Verificado:

```
apps/project-cockpit/server/mobile-routes.mjs  → nenhuma referência a bula
BeagleCore/ConversationStore.swift:480         → BulaStore.shared.consulta(...)
                                                  (só dentro de offlineGroundedPrompt)
```

Consequência: **com rede, ele recebe o que o modelo lembra; sem rede, o que a bula
diz, copiado e citado.** As respostas sobre dose são mais seguras quando a rede cai.

Isso está invertido. O usuário é médico e usa isto em plantão.

O princípio que corrige: retrieval determinístico com citação vence qualquer LLM
para número clínico. A base verbatim não é plano B — é o caminho primário, em
todos os níveis. O modelo embrulha e contextualiza; o número vem sempre do mesmo
lugar.

## Decisões tomadas (dele)

| pergunta | escolha |
|---|---|
| fármaco fora da base, com rede | **responde, marcado** — não recusa |
| dose no relógio | **sim** → a busca tem que ser do servidor |
| cobertura | **ampla online** (todos os ativos distintos da openFDA), estreita offline (507), **com aviso** quando a resposta não vai acompanhar offline |
| onde a busca vive | **SQLite em volume, dentro do cockpit** — mesma tecnologia do app |

Descartado: Postgres (amarraria o caminho clínico ao banco que já travou o WAL e
ficou fora do ar — dose não pode compartilhar destino com a infraestrutura mais
frágil) e serviço dedicado (isolamento ilusório: se o cockpit está fora, não há
resposta de qualquer jeito).

## Arquitetura

**Uma fonte, duas cópias, nenhuma divergência silenciosa.**

Um construtor lê o dump da openFDA e produz o SQLite, com um corte por parâmetro:

- `--completo` → base do servidor: todos os ativos distintos.
  MEDIDO em 2026-08-10 contra o dump em massa da openFDA (export_date
  2026-08-08, 14 partições, 8,2 GB de JSON cru): 14.747 ativos distintos em
  86.619 rótulos de produto, 41 MB de texto útil das seções clínicas →
  **base estimada em 66 MB** (texto + índice FTS ~1,6x). Muito abaixo do teto
  de 1 GB que trocaria a escolha do volume — segue com PVC de 4 Gi. O dump
  cru é bem maior do que o 1,8 GB compactado citado no plano (8,2 GB
  descompactado); isso não é o tamanho da base, só o tamanho da matéria-prima
  antes do corte por ativo distinto.
- `--formulario` → base do telefone: os 507 do formulário dele (29 MB).

Mesmo código, mesmo esquema, mesma normalização de nome, mesma regra de escolha do
melhor rótulo — a que impede `metformina` virar sitagliptina+metformina. Se as duas
bases nascem de código diferente, "mesmo número em todo lugar" é intenção, não
garantia.

**Onde vivem:** a do servidor num PVC do Ceph, montada em `/var/lib/bula` no
cockpit. A do telefone segue no bundle do app.

**Peça nova:** `apps/project-cockpit/server/bula-store.mjs` — busca FTS5, devolve
trecho com citação formatada. Não sabe o que é LLM, não conversa com ninguém:
recebe texto, devolve trecho ou nada. Testável sozinho. É a peça de que depende a
segurança clínica.

**Quem chama:** `completeChatRequest` consulta antes de montar o prompt, como o app
já faz offline.

**O telefone online usa a base do SERVIDOR**, não a dele. A local fica reservada ao
offline. Se cada surface usasse a sua, voltaríamos a ter dois números para a mesma
pergunta.

**Carimbo:** cada base carrega versão do dump, data, contagem e hash do conteúdo. O
app envia o carimbo da base local junto com a pergunta; o servidor sabe dizer se
aquele fármaco também existe lá. É assim que o aviso de "isto não vai te acompanhar
offline" vira fato verificado em vez de suposição.

## Fluxo

**Portão de intenção clínica primeiro.** Nem toda mensagem consulta bula: "tô muito
cansado hoje" já trouxe trechos de HIV e tuberculose no offline. Sem sinal clínico,
o caminho é o de hoje, intocado — a conversa íntima não é contaminada por bula.

Com sinal clínico:

1. **Busca no ativo** — casamento estrito: o produto começa pelo fármaco pedido,
   associação descartada quando se pediu isolado. Errar aqui entrega bula de
   ganciclovir para quem perguntou de aciclovir.
2. **PCDT junto**, quando houver — ao lado do rótulo americano, não no lugar.
3. **Material da mensagem** — trechos verbatim, citação colada em cada um.
4. **Regra no sistema** — copiar e citar; nunca converter, extrapolar ou
   arredondar; se rótulo e PCDT divergem, mostrar os dois e dizer que divergem, sem
   escolher por ele; o trecho vale só para a população que descreve.
5. **O modelo embrulha** — contextualiza e liga com o que sabe dele, mas o número
   atravessa copiado.

**Fármaco não encontrado:** responde, e a marca vai no ENVELOPE da resposta, não
como texto que o modelo pode esquecer de escrever.

**Fármaco fora da base local:** segundo aviso, derivado da comparação de carimbos.

**Offline:** fluxo idêntico, base local no lugar do servidor.
**Relógio:** idêntico ao telefone online — mesmo servidor.

## O guarda do número

O buraco: quem escreve a frase final é o modelo. Instrução não é garantia — na
enoxaparina ele disse 40 mg com a bula dizendo 30.

Depois de composta e antes de virar bolha: extrair da resposta toda quantidade
clínica e conferir
se cada uma **aparece nos trechos entregues**. Comparação de texto, não julgamento.

Conta como quantidade clínica: dose (`30 mg`), dose por peso (`1,5 mg/kg`),
concentração (`5 mg/mL`), taxa (`mL/min`, `mcg/kg/min`) e **frequência**
(`12/12h`, `a cada 8 horas`, `1x/dia`) — a frequência entra porque errar o
intervalo erra a dose diária inteira.

- todas conferem → passa
- número que não está em fonte nenhuma → não entrega; devolve o trecho citado, sem
  a frase do modelo

Mesma disciplina do portão de fala e do guarda da boca: checagem burra e verificável
no caminho de saída, que transforma promessa em propriedade. É o único ponto do
sistema em que "quase certo" pode entrar num paciente.

**O teste que mais importa é o negativo.** O guarda não pode reprovar resposta
legítima: ignora número fora do domínio clínico (idade, horário, dias sem dormir,
"os 507 fármacos") e só olha quantidade com unidade de dose. "A bula fala em 30 mg,
mas o protocolo daqui usa 40" passa — os dois estão em fontes entregues.

## Degradação

| falha | comportamento |
|---|---|
| base do servidor inacessível | avisa sem-fonte e responde marcado |
| fármaco não encontrado | responde marcado |
| guarda do número reprova | entrega o trecho citado, sem a frase do modelo |
| tudo fora | o chão, como hoje |

## Testes

**bula-store, isolado:** casamento estrito (aciclovir não casa com ganciclovir;
metformina não traz a associação); fármaco ausente devolve vazio, não aproximação.

**Guarda do número, nos dois sentidos:** reprova número inventado; **não** reprova
idade, horário, contagem, nem número legítimo presente na fonte; não reprova
resposta que compara duas fontes divergentes.

**Portão de intenção:** "tô cansado" não consulta bula; "dose de enoxaparina em ClCr
30" consulta.

**Paridade servidor/telefone:** a mesma pergunta, contra as duas bases, devolve o
mesmo trecho e a mesma citação para os fármacos presentes nas duas. É a garantia
central do desenho e precisa de teste próprio.

**Canário:** passa a sondar enoxaparina com ClCr baixo e conferir que volta 30 mg
citando o DailyMed. Se a base sumir do volume, ou o portão parar de disparar, ou a
citação sumir, ele sabe em cinco minutos. Hoje isso quebraria em silêncio.

## Fora de escopo

- ANVISA / bulário brasileiro: cobertura medida em 2 de 12 numa amostra, serviço
  instável. Ferramenta commitada e retomável (`tools/base-clinica/build_anvisa.py`).
- Busca semântica: a textual com casamento estrito é o que dá para verificar.
- Interações medicamentosas e cálculo de dose por peso: o desenho entrega o que a
  bula diz. Calcular é outra coisa, e outro risco.
