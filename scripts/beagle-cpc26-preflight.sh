#!/usr/bin/env bash
# Beagle CPC26 preflight — one command, GREEN/RED before leaving for Yale.
set -uo pipefail
EXT="https://beagle.chiuratto.ai"
INT="http://10.96.71.119"
NS=beagle
fail=0; line(){ printf "%-32s %s\n" "$1" "$2"; }
TOK=$(kubectl -n $NS get secret cockpit-mobile-auth -o jsonpath='{.data.PROJECT_COCKPIT_AUTH_TOKEN}' 2>/dev/null | base64 -d)
[ -n "$TOK" ] || { line "auth token" "RED (no secret)"; exit 1; }

# 1. external healthz
c=$(curl -s -m10 -o /dev/null -w '%{http_code}' "$EXT/healthz")
[ "$c" = 200 ] && line "1 external /healthz" "GREEN ($c)" || { line "1 external /healthz" "RED ($c)"; fail=1; }

# 2. companion personal chat grounded
r=$(curl -s -m85 -X POST "$EXT/api/mobile/v1/chat" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"prompt":"ping preflight","space":"personal"}')
echo "$r" | grep -q '"grounded":true' && line "2 companion (personal)" "GREEN" || { line "2 companion (personal)" "RED"; fail=1; }

# 3. deep-think cites
r=$(curl -s -m175 -X POST "$EXT/api/mobile/v1/chat" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"prompt":"Cite one paper linking network curvature to brain connectivity.","space":"personal","deepThink":true}')
echo "$r" | grep -qiE 'http|doi|[0-9]{4}\)' && line "3 deep-think cites" "GREEN" || { line "3 deep-think cites" "RED"; fail=1; }

# 4. memory recall (ORC + Sounio present)
orc=$(kubectl -n $NS exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT count(*) FROM records WHERE content ~* 'ollivier|hyperbolic|HSN'\"" 2>/dev/null | tr -d '[:space:]')
sou=$(kubectl -n $NS exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT count(*) FROM records WHERE content ~* 'sounio|souc|tapestry'\"" 2>/dev/null | tr -d '[:space:]')
{ [ "${orc:-0}" -gt 0 ] && [ "${sou:-0}" -gt 0 ]; } && line "4 memory recall" "GREEN (orc=$orc sounio=$sou)" || { line "4 memory recall" "RED (orc=${orc:-?} sounio=${sou:-?})"; fail=1; }

# 5. claude proxy up (deep-think brain)
c=$(curl -s -m8 -o /dev/null -w '%{http_code}' http://127.0.0.1:9500/v1/models)
[ "$c" = 200 ] && line "5 claude proxy t560:9500" "GREEN ($c)" || { line "5 claude proxy t560:9500" "RED ($c)"; fail=1; }

echo "----"
[ "$fail" = 0 ] && echo "VERDICT: GREEN — Beagle ready for CPC26." || echo "VERDICT: RED — fix above before relying on it."
exit $fail
