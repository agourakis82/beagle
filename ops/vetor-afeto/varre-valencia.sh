#!/bin/bash
# Varre a VALÊNCIA mantendo todo o resto congelado, e guarda as respostas cruas.
#
# A pergunta que ele fez: o vetor de emoção DIRIGE a fala, ou só está no prompt? A diferença é a
# mesma que separou a persona do comportamento hoje — pedir não é obter, e a única forma de saber
# é variar uma coisa e medir o deslocamento.
#
# `probe: true` é obrigatório: exercita o caminho real (roteamento, aterramento, portão de fala)
# sem gravar nada no corpus dele. Sem isso, cada rodada plantaria auto-relatos que ele não disse.
set -u
URL="${URL_CHAT:-https://beagle.chiuratto.ai/api/mobile/v1/chat}"
SAIDA="${1:?uso: varre-valencia.sh <arquivo-de-saida> [repeticoes]}"
REPS="${2:-1}"
FALA="${FALA:-Tentando organizar, abri muitas frentes e agora fiquei angustiado pois parece que é um loop infinito e não vejo nada sair}"

TOKEN=$(KUBECONFIG=/home/devsounio/.kube/config timeout 30 kubectl -n beagle get secret cockpit-mobile-auth \
  -o jsonpath='{.data.PROJECT_COCKPIT_AUTH_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null)
[ -z "$TOKEN" ] && { echo "SEM TOKEN — abortando"; exit 1; }

: > "$SAIDA"
# null = controle (sem afeto nenhum no bloco `## Agora`). Os demais cobrem as cinco faixas de
# `stateOfMindPtBR`: <=-0.6, <=-0.2, <0.2, <0.6, resto.
for rep in $(seq 1 "$REPS"); do
for v in null -0.8 -0.3 0.0 0.3 0.8; do
  payload=$(python3 - "$v" "$FALA" <<'PY'
import json,sys
v,fala=sys.argv[1],sys.argv[2]
b={"space":"personal","probe":True,"prompt":fala,
   # congelados de propósito: só a valência varia
   "timezone":"America/Sao_Paulo","heart_rate":72,"hrv_ms":44,"sleep_hours":6.0}
if v!="null": b["state_of_mind"]=float(v)
print(json.dumps(b,ensure_ascii=False))
PY
)
  corpo_arq=$(mktemp)
  curl -s -m 240 -X POST "$URL" -H "content-type: application/json" \
    -H "x-cockpit-token: $TOKEN" -H "authorization: Bearer $TOKEN" \
    --data "$payload" -o "$corpo_arq" 2>/dev/null
  # 🚨 A resposta vai por ARQUIVO, não por stdin. A versão anterior dava DUAS redireções de
  # stdin ao mesmo python3 — o heredoc do código e um `<<<` com o corpo — e o segundo vencia:
  # o Python recebia a resposta HTTP no lugar do próprio programa. Dezoito respostas de
  # exatamente 49 caracteres, todas o mesmo erro de parse, e nenhuma delas era do servidor.
  python3 - "$v" "$rep" "$SAIDA" "$corpo_arq" <<'PY'
import json,sys
v,rep,saida,arq=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
try:
    d=json.load(open(arq,encoding="utf-8")); x=d.get("data",d)
    txt=x.get("response") or x.get("text") or ""
except Exception as e:
    txt="<ERRO: %s :: %s>"%(e, open(arq,encoding="utf-8",errors="replace").read()[:200])
with open(saida,"a",encoding="utf-8") as f:
    f.write("\n@@@ valencia=%s rep=%s\n%s\n"%(v,rep,txt.strip()))
print("  valencia=%s rep=%s -> %d chars"%(v,rep,len(txt)))
PY
  rm -f "$corpo_arq"
done
done
echo "gravado em $SAIDA"
