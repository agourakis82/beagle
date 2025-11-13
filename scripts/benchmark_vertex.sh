#!/usr/bin/env bash

set -euo pipefail

echo "🔥 Benchmarking Vertex AI via Beagle"
echo

function call_chat() {
  local payload=$1
  time curl -sS -X POST http://localhost:3000/api/v1/chat \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    | jq -r '.response'
  echo
}

echo "=== Claude Haiku 4.5 (Primário) ==="
call_chat '{"message":"Compose a haiku about AI-enabled hypergraphs."}'

echo "=== Claude Sonnet 4.5 (Premium) ==="
call_chat '{"message":"Explique a neurofarmacologia da quetamina com foco em circuitos cortico-talâmicos.", "model":"sonnet-4.5"}'

