#!/usr/bin/env bash
# cli-canary.sh — as CLIs de agente atualizam quase todo dia, e o operador QUER estar na última.
# Então não se fixa a versão: mede-se o binário instalado e falha-se alto quando um campo de
# carga some. Este é o teste que transforma "atualizou e quebrou em silêncio" em "atualizou e o
# canário avisou".
#
# REGRA DE PROJETO (a doc do Claude Code diz literalmente):
#   "Check it [capabilities] to feature-detect instead of comparing version strings, and ignore
#    values you don't recognize."
# Nada aqui compara número de versão para decidir comportamento. Versão só é REPORTADA.
#
# MEDIDO 2026-08-09, e é o que justifica a tolerância aditiva: entre codex 0.125.0 e 0.147.0
# (22 versões) as notificações foram de 58 para 70, NADA foi removido, e os enums de decisão
# ficaram idênticos. O protocolo cresce; não rotaciona. Por isso o canário checa um NÚCLEO
# pequeno e trata desconhecido como informação, não como falha.
#
# Uso:
#   cli-canary.sh            # checagens de esquema/inventário (não gasta token)
#   cli-canary.sh --deep     # + uma volta real no claude para ler `capabilities` (~US$0,02)
set -uo pipefail

BASE_HOME="${BASE_HOME:-/workspace/.home/openvscode-server}"
# O MESMO PATH que o wrapper das lanes monta. Medir outro binário que não este é medir ficção —
# foi exatamente o erro que custou duas afirmações erradas em 09-ago (peguei um diretório `.bak`).
export PATH="$BASE_HOME/bin:$BASE_HOME/.local/node-v20.20.2-linux-x64/bin:$BASE_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

DEEP=0; [ "${1:-}" = "--deep" ] && DEEP=1
fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { printf '  \033[31mFALHA\033[0m %s\n' "$1"; fail=$((fail+1)); }
note() { printf '  ·    %s\n' "$1"; }

echo "═══ CANÁRIO DAS CLIs ═══  $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── 1. Qual binário a lane realmente executa, e quantos concorrentes existem ────────────────
echo
echo "[1] inventário — um PATH ambíguo é bug de supervisão, não detalhe"
for c in claude codex; do
  resolved="$(command -v $c 2>/dev/null)"
  if [ -z "$resolved" ]; then bad "$c não está no PATH das lanes"; continue; fi
  ver="$($c --version 2>/dev/null | head -1)"
  ok "$c → $resolved  [$ver]"
  n=$(find "$BASE_HOME" -maxdepth 6 -name "$c" \( -type f -o -type l \) 2>/dev/null | wc -l)
  [ "$n" -gt 1 ] && note "⚠ $n binários '$c' no disco — só um está no PATH; os outros podem enganar scripts"
done

# ── 2. Codex: o binário descreve o PRÓPRIO protocolo. Não mantemos tabela à mão. ────────────
echo
echo "[2] codex — vocabulário lido do binário instalado (generate-json-schema)"
CXS="$(mktemp -d)"; trap 'rm -rf "$CXS"' EXIT
if codex app-server generate-json-schema --out "$CXS" >/dev/null 2>&1; then
  ok "generate-json-schema respondeu"
  python3 - "$CXS" <<'PY'
import json, sys, os
d = sys.argv[1]
def methods(f):
    p = os.path.join(d, f + ".json")
    if not os.path.exists(p): return None
    o = json.load(open(p)); out = []
    for v in o.get("oneOf", []):
        e = v.get("properties", {}).get("method", {}).get("enum")
        if e: out += e
    return set(out), o.get("definitions", {})

bad = 0
def ok_(m):  print(f"  \033[32mok\033[0m   {m}")
def no_(m):
    global bad; bad += 1; print(f"  \033[31mFALHA\033[0m {m}")

nots, ndefs = methods("ServerNotification") or (set(), {})
reqs, rdefs = methods("ServerRequest") or (set(), {})
print(f"  ·    {len(nots)} notificações · {len(reqs)} requisições do agente")

# O NÚCLEO. Se qualquer um destes sumir, a supervisão estruturada deixa de funcionar e o
# fallback teria que voltar a raspar tela — é exatamente isso que o canário existe para pegar.
CORE_NOTIFS = ["thread/started","thread/status/changed","turn/started","turn/completed",
               "turn/diff/updated","item/started","item/completed"]
CORE_REQS   = ["item/commandExecution/requestApproval","item/fileChange/requestApproval"]
for m in CORE_NOTIFS:
    ok_(f"notificação {m}") if m in nots else no_(f"notificação {m} SUMIU")
for m in CORE_REQS:
    ok_(f"requisição {m}") if m in reqs else no_(f"requisição {m} SUMIU")

# "esperando por você" tem que continuar sendo ENUM, não substring de tela.
flag = ndefs.get("ThreadActiveFlag", {}).get("enum", [])
if "waitingOnApproval" in flag and "waitingOnUserInput" in flag:
    ok_(f"ThreadActiveFlag = {flag}")
else:
    no_(f"ThreadActiveFlag perdeu valor de carga: {flag}")

# O diff tem que continuar chegando como DADO.
diff = ndefs.get("TurnDiffUpdatedNotification", {}).get("properties", {})
ok_("turn/diff/updated carrega `diff`") if "diff" in diff else no_("turn/diff/updated sem campo `diff`")

# ⚠️ O erro que quase virou falso positivo em 09-ago: respondi {decision:"approved"} a um
# fileChange, o log disse "aprovado", e o arquivo NÃO mudou. Cada família tem o seu enum, e
# valor inválido é aceito em silêncio pelo transporte. Este check é o guarda disso.
for f, key, need in [("FileChangeRequestApprovalResponse","FileChangeApprovalDecision","accept"),
                     ("CommandExecutionRequestApprovalResponse","CommandExecutionApprovalDecision","accept"),
                     ("ExecCommandApprovalResponse","ReviewDecision","approved")]:
    p = os.path.join(d, f + ".json")
    if not os.path.exists(p): no_(f"{f} sumiu do esquema"); continue
    o = json.load(open(p))
    vals = [x.get("enum", [None])[0] for x in o.get("definitions", {}).get(key, {}).get("oneOf", [])]
    ok_(f"{key} aceita '{need}'") if need in vals else no_(f"{key} NÃO aceita '{need}': {vals}")

sys.exit(1 if bad else 0)
PY
  [ $? -ne 0 ] && fail=$((fail+1))
else
  bad "codex app-server generate-json-schema falhou — o protocolo deixou de ser auto-descritivo"
fi

# ── 3. Claude: feature-detect por `capabilities`, como a doc manda ──────────────────────────
echo
echo "[3] claude — capabilities (detecção por capacidade, NUNCA por número de versão)"
if [ "$DEEP" -eq 1 ]; then
  # NÃO pegar a linha 1. A doc é explícita: system/init "is the first event in the stream UNLESS
  # startup events precede it" — `plugin_install`, e `hook_started`/`hook_progress`/`hook_response`
  # enquanto um hook de SessionStart roda. Casar pelo TIPO, nunca pela posição. (Esta era a
  # linha 1 do canário anterior, e ela falhou exatamente assim num HOME com hooks.)
  init="$(printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"oi"}]}}' \
    | timeout 90 claude -p --input-format stream-json --output-format stream-json --verbose \
        --no-session-persistence --model claude-haiku-4-5-20251001 2>/dev/null \
    | grep -m1 '"subtype":"init"')"
  if [ -z "$init" ]; then
    bad "nenhum system/init — o modo stream-json bidirecional não respondeu"
  else
    # Heredoc CITADO ('PY'): o shell não toca no conteúdo. A versão anterior usava
    # `python3 -c '...'` com aspas escapadas e quebrava com SyntaxError — e, pior, a falha
    # não era contada e o canário terminava VERDE. Um canário que engole erro é pior que nenhum.
    # O dado vai por ENV, não por stdin: `python3 - <<'PY'` já usa o stdin para ler o PROGRAMA,
    # então pipar o JSON junto dava leitura vazia — e o canário reportava "ilegível" culpando o
    # CLI por um bug meu. Errar do lado de acusar a ferramenta é o pior erro possível aqui.
    INIT_JSON="$init" python3 <<'PY'
import os, sys, json
bad = 0
def ok_(m):  print(f"  \033[32mok\033[0m   {m}")
def no_(m):
    global bad; bad += 1; print(f"  \033[31mFALHA\033[0m {m}")

try:
    o = json.loads(os.environ.get("INIT_JSON", ""))
except Exception as e:
    print(f"  \033[31mFALHA\033[0m system/init ilegível: {e}"); sys.exit(1)

print(f"  ·    versão relatada: {o.get('claude_code_version')}  (reportada, nunca usada para decidir)")
caps = o.get("capabilities")
if caps is None:
    # Opcional por documentação (ausente antes de 2.1.205). Não é falha do protocolo, mas o
    # supervisor perde a detecção por capacidade e tem que degradar — então é AVISO, alto.
    print("  \033[33mAVISO\033[0m capabilities ausente — feature-detect indisponível neste binário")
else:
    ok_(f"capabilities = {caps}")
for k in ("tools", "permissionMode", "session_id"):
    ok_(f"system/init declara {k}") if k in o else no_(f"system/init sem {k}")
sys.exit(1 if bad else 0)
PY
    [ $? -ne 0 ] && fail=$((fail+1))
  fi
else
  note "pulado (roda com --deep; gasta ~US\$0,02 de token)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "═══ VERDE — o núcleo do protocolo está de pé nas versões instaladas ═══"
else
  echo "═══ VERMELHO ($fail) — um campo de carga mudou. NÃO deploye o supervisor sem olhar. ═══"
fi
exit "$fail"
