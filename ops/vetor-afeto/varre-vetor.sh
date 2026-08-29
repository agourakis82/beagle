#!/bin/bash
# Varre o VETOR (valência × ativação) em dois braços de ENTREGA, tudo o mais congelado.
#
#   descritivo — o vetor descreve o estado dele (a forma histórica, agora com os dois eixos)
#   diretivo   — o vetor prescreve a FORMA do texto, derivada dos mesmos números
#
# Mesma informação, veiculação diferente. Se um deslocar a fala e o outro não, o problema nunca
# foi o vetor. `probe: true` é obrigatório: nada disto entra no corpus dele.
set -u
URL="${URL_CHAT:-https://beagle.chiuratto.ai/api/mobile/v1/chat}"
SAIDA="${1:?uso: varre-vetor.sh <saida> [reps]}"
REPS="${2:-2}"
FALA="${FALA:-Tentando organizar, abri muitas frentes e agora fiquei angustiado pois parece que é um loop infinito e não vejo nada sair}"
TOKEN=$(KUBECONFIG=/home/devsounio/.kube/config timeout 30 kubectl -n beagle get secret cockpit-mobile-auth \
  -o jsonpath='{.data.PROJECT_COCKPIT_AUTH_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null)
[ -z "$TOKEN" ] && { echo "SEM TOKEN"; exit 1; }
: > "$SAIDA"
for rep in $(seq 1 "$REPS"); do
for modo in descritivo diretivo; do
for v in -0.8 0.0 0.8; do
for a in -0.8 0.0 0.8; do
  payload=$(python3 - "$v" "$a" "$modo" "$FALA" <<'PY'
import json,sys
v,a,modo,fala=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
print(json.dumps({"space":"personal","probe":True,"prompt":fala,
  "timezone":"America/Sao_Paulo","heart_rate":72,"hrv_ms":44,"sleep_hours":6.0,
  "state_of_mind":float(v),"arousal":float(a),"afeto_modo":modo},ensure_ascii=False))
PY
)
  arq=$(mktemp)
  curl -s -m 240 -X POST "$URL" -H "content-type: application/json" \
    -H "x-cockpit-token: $TOKEN" -H "authorization: Bearer $TOKEN" --data "$payload" -o "$arq" 2>/dev/null
  python3 - "$v" "$a" "$modo" "$rep" "$SAIDA" "$arq" <<'PY'
import json,sys
v,a,modo,rep,saida,arq=sys.argv[1:7]
try:
    d=json.load(open(arq,encoding="utf-8")); x=d.get("data",d) or {}
    txt=x.get("response") or x.get("text") or ""
except Exception as e:
    txt="<ERRO: %s>"%e
with open(saida,"a",encoding="utf-8") as f:
    f.write("\n@@@ modo=%s valencia=%s ativacao=%s rep=%s\n%s\n"%(modo,v,a,rep,txt.strip()))
print("  %-10s v=%-5s a=%-5s rep=%s -> %d chars"%(modo,v,a,rep,len(txt)))
PY
  rm -f "$arq"
done; done; done; done
echo "gravado em $SAIDA"
