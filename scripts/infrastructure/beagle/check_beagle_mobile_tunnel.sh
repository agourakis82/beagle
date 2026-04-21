#!/usr/bin/env bash
set -euo pipefail

TUNNEL_HOSTNAME="${TUNNEL_HOSTNAME:-beagle.chiuratto.ai}"
CHAT_PROMPT="${CHAT_PROMPT:-Say hello in one short sentence.}"
CHAT_PROMPT_JSON="$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1]}))' "${CHAT_PROMPT}")"

curl --noproxy '*' --max-time 15 -fsS "https://${TUNNEL_HOSTNAME}/api/mobile/v1/health" \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["ok"] is True and data["data"]["service"]=="project-cockpit-mobile"; print(json.dumps(data["data"], indent=2, sort_keys=True))'

curl --noproxy '*' --max-time 120 -fsS \
  -H 'content-type: application/json' \
  -d "${CHAT_PROMPT_JSON}" \
  "https://${TUNNEL_HOSTNAME}/api/mobile/v1/chat" \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["ok"] is True and data["data"]["response"]; print(data["data"]["response"])'
