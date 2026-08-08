#!/bin/bash
# CANÁRIO EXTERNO — sonda o companion de fora do cluster.
#
# POR QUE FORA: a sonda que roda DENTRO do k8s é estruturalmente cega para o
# túnel Cloudflare, para o DNS de pod do próprio nó em que ela caiu, e para o
# certificado. Em 07-ago o companion ficou inacessível por horas e a sonda
# in-cluster não viu — e quando viu, não conseguiu avisar, porque o ntfy que ela
# usa mora no mesmo cluster que estava quebrado. Alarme que compartilha destino
# com o alarmado não é alarme.
#
# Este roda no HOST Proxmox (systemd de SISTEMA, não --user), que é um domínio de
# falha separado: sobrevive à morte do k8s inteiro. E avisa pelo ntfy.sh PÚBLICO,
# que não é nosso, não roda aqui e não cai com a gente.
#
# E NÃO checa liveness: checa SEMÂNTICA. HTTP 200 não prova nada neste sistema —
# foi um 200 que carregou "401 Invalid bearer token" até a tela dele como se
# fosse fala do companion.
set -uo pipefail

URL="https://beagle.chiuratto.ai/api/mobile/v1/chat"
TOKEN_FILE="/home/devsounio/.beagle/cockpit-mobile-token.novo"
TOPICO_FILE="/home/devsounio/.beagle/ntfy-topico-externo.txt"
ESTADO="/home/devsounio/.beagle/canario/estado"

[ -r "$TOKEN_FILE" ] || exit 0
TOKEN=$(cat "$TOKEN_FILE")
TOPICO=$(cat "$TOPICO_FILE" 2>/dev/null)

falhas=()
corpo=$(curl -s -m 180 -X POST "$URL" \
  -H "content-type: application/json" -H "x-cockpit-token: $TOKEN" \
  --data '{"space":"personal","prompt":"Responda em uma frase: quem sou eu para você?"}' 2>/dev/null)
codigo=$?

if [ $codigo -ne 0 ] || [ -z "$corpo" ]; then
  falhas+=("INALCANÇÁVEL: sem resposta da URL pública (curl=$codigo)")
else
  # Assinaturas de ERRO chegando como se fossem fala dele. Esta é a classe de
  # falha que mais importa: o caminho vivo falando lixo.
  for assinatura in "Invalid bearer" "401" "Failed to authenticate" "<html" "502 Bad" "Service Unavailable"; do
    if grep -qi -- "$assinatura" <<<"$corpo"; then
      falhas+=("ERRO NA BOCA: resposta contém \"$assinatura\" — isso chegaria na tela dele")
      break
    fi
  done
  modelo=$(python3 -c "import sys,json;d=json.load(sys.stdin);x=d.get('data',d);print(x.get('model',''))" <<<"$corpo" 2>/dev/null)
  texto=$(python3 -c "import sys,json;d=json.load(sys.stdin);x=d.get('data',d);print(str(x.get('response','')))" <<<"$corpo" 2>/dev/null)
  [ "$modelo" = "floor" ] && falhas+=("NO CHÃO: presença enlatada, nenhum modelo respondendo")
  [ ${#texto} -lt 40 ] && falhas+=("RESPOSTA CURTA DEMAIS: ${#texto} caracteres")
fi

# Estado no disco: sem isso, uma queda de madrugada vira 30 notificações e ele
# aprende a ignorá-las — que é como um alarme morre de verdade.
antes=$(cat "$ESTADO" 2>/dev/null || echo ok)
avisar() {  # titulo, corpo, prioridade, tag
  [ -n "$TOPICO" ] || return 0
  curl -s -m 20 -o /dev/null "https://ntfy.sh/$TOPICO" \
    -H "Title: $1" -H "Priority: $3" -H "Tags: $4" -d "$2" 2>/dev/null
}

if [ ${#falhas[@]} -gt 0 ]; then
  msg=$(printf '%s · ' "${falhas[@]}"); msg=${msg% · }
  logger -t beagle-canario "DEGRADADO: $msg"
  [ "$antes" = "ok" ] && avisar "Companion degradado" "$msg" "urgent" "rotating_light"
  echo quebrado > "$ESTADO"
  exit 1
fi
logger -t beagle-canario "OK: model=$modelo"
[ "$antes" = "quebrado" ] && avisar "Companion voltou" "respondendo pela URL pública" "default" "white_check_mark"
echo ok > "$ESTADO"
