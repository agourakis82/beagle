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
# O TOKEN VEM DA FONTE, não de uma cópia no disco.
#
# A primeira versão lia /home/devsounio/.beagle/cockpit-mobile-token.novo. Em
# 09-ago outra sessão rotacionou o token e o arquivo sumiu — o canário passou a
# sair com SUCESSO sem sondar nada. Um alarme que se cala sozinho é pior que
# alarme nenhum, porque o silêncio dele parece "está tudo bem".
#
# Agora lê do Secret do cluster, que é a verdade, com um arquivo como último
# recurso. E se não achar token, GRITA em vez de sair quieto.
TOKEN_FILE="/home/devsounio/.beagle/cockpit-mobile-token.novo"
TOPICO_FILE="/home/devsounio/.beagle/ntfy-topico-externo.txt"
ESTADO="/home/devsounio/.beagle/canario/estado"

TOKEN=$(KUBECONFIG=/home/devsounio/.kube/config timeout 30 kubectl -n beagle get secret cockpit-mobile-auth \
  -o jsonpath='{.data.PROJECT_COCKPIT_AUTH_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null)
[ -z "$TOKEN" ] && [ -r "$TOKEN_FILE" ] && TOKEN=$(cat "$TOKEN_FILE")
TOPICO=$(cat "$TOPICO_FILE" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  logger -t beagle-canario "SEM TOKEN: nao consigo sondar — o canario esta cego"
  [ -n "$TOPICO" ] && curl -s -m 20 -o /dev/null "https://ntfy.sh/$TOPICO" \
    -H "Title: Canario cego" -H "Priority: urgent" -H "Tags: warning" \
    -d "Nao achei o token do cockpit. O canario NAO esta sondando o companion." 2>/dev/null
  exit 1
fi

falhas=()

# MATRIZ DE CAMADAS — dizer ONDE quebrou, não só QUE quebrou.
#
# Em 07-ago o companion ficou horas inacessível e a mensagem útil só apareceu
# depois de eu isolar na mão: túnel morto por nó com DNS quebrado, e o cérebro
# autenticando com um placeholder. Duas camadas diferentes, sintoma idêntico
# ("não responde"). Um alarme que só diz "quebrou" faz ele acordar sem saber por
# onde começar — e às 3h da manhã isso é quase tão ruim quanto não avisar.
#
# Sondadas de fora para dentro. A primeira que falhar nomeia a camada.
camada_quebrada=""
diagnosticar() {
  # 1) TÚNEL: a porta de entrada pública responde?
  local t=$(curl -s -o /dev/null -m 20 -w "%{http_code}" https://beagle.chiuratto.ai/healthz 2>/dev/null)
  if [ "$t" != "200" ]; then camada_quebrada="TÚNEL (Cloudflare -> cockpit): healthz=$t"; return; fi

  # 2) BACKEND: o cockpit responde por dentro, sem passar pelo túnel?
  local b=$(curl -s -o /dev/null -m 20 -w "%{http_code}" http://127.0.0.1:30437/healthz 2>/dev/null)
  [ "$b" = "000" ] && b=$(KUBECONFIG=/home/devsounio/.kube/config timeout 25 kubectl -n beagle get pods \
      --no-headers 2>/dev/null | grep -c "project-cockpit.*1/1.*Running")

  # 3) CÉREBRO: o proxy OAuth autentica?
  local c=$(curl -s -o /dev/null -m 25 -w "%{http_code}" http://10.100.100.2:9500/v1/models 2>/dev/null)
  if [ "$c" = "000" ]; then camada_quebrada="CÉREBRO (proxy OAuth :9500) não responde"; return; fi

  # 4) CONTROL PLANE: não derruba o companion na hora, mas nada se recupera sem ele.
  local k=$(curl -sk -o /dev/null -m 15 -w "%{http_code}" https://10.100.100.2:6443/livez 2>/dev/null)
  [ "$k" != "200" ] && camada_quebrada="CONTROL PLANE do k8s fora (livez=$k) — pods vivos, mas nada se recupera"
}

corpo=$(curl -s -m 180 -X POST "$URL" \
  -H "content-type: application/json" -H "x-cockpit-token: $TOKEN" \
  --data '{"space":"personal","prompt":"Responda em uma frase: quem sou eu para você?"}' 2>/dev/null)
codigo=$?

if [ $codigo -ne 0 ] || [ -z "$corpo" ]; then
  falhas+=("INALCANÇÁVEL: sem resposta da URL pública (curl=$codigo)")
else
  # Assinaturas de ERRO chegando como se fossem fala dele. Esta é a classe de
  # falha que mais importa: o caminho vivo falando lixo.
  # Assinaturas ESPECÍFICAS. A primeira versão procurava "401" solto e teria
  # reprovado fala legítima — ele pode perguntar sobre o 401 de ontem e o
  # companion responder sobre isso. Mesma disciplina do portão de fala: só
  # condena o que é inequivocamente máquina falando, nunca vocabulário.
  for assinatura in "Invalid bearer token" "Failed to authenticate" "API Error:" \
                    "<html" "502 Bad Gateway" "503 Service Unavailable" "ECONNREFUSED"; do
    if grep -qF -- "$assinatura" <<<"$corpo"; then
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
  diagnosticar
  [ -n "$camada_quebrada" ] && falhas+=("ONDE: $camada_quebrada")
  msg=$(printf '%s · ' "${falhas[@]}"); msg=${msg% · }
  logger -t beagle-canario "DEGRADADO: $msg"
  [ "$antes" = "ok" ] && avisar "Companion degradado" "$msg" "urgent" "rotating_light"
  echo quebrado > "$ESTADO"
  exit 1
fi
logger -t beagle-canario "OK: model=$modelo"
[ "$antes" = "quebrado" ] && avisar "Companion voltou" "respondendo pela URL pública" "default" "white_check_mark"
echo ok > "$ESTADO"
