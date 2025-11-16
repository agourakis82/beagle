#!/bin/bash
set -euo pipefail

cd ~/beagle

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  BEAGLE DISRUPTIVE FEATURES - COMPLETE TEST & DEPLOY      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "📦 Building optimized release..."
if ! cargo build --release --bin beagle-server; then
    echo "❌ Release build failed"
    exit 1
fi

echo "✅ Release build complete"
echo

source .env.dev
export $(grep -v '^#' .env.dev | xargs)

echo "🚀 Starting Beagle server (release mode)..."
cargo run --release --bin beagle-server > /tmp/beagle-test.log 2>&1 &
SERVER_PID=$!
echo "   Server PID: $SERVER_PID"
echo "   Logs: /tmp/beagle-test.log"
echo

echo "⏳ Waiting for server initialization..."
sleep 12

if ! ps -p $SERVER_PID >/dev/null; then
    echo "❌ Server failed to start!"
    echo
    echo "Last 50 lines of log:"
    tail -50 /tmp/beagle-test.log
    exit 1
fi

if ! curl -s http://localhost:3030/health >/dev/null 2>&1; then
    echo "⚠️  Health check failed, trying main endpoints..."
fi

echo "✅ Server running on port 3030"
echo

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  TEST SUITE - All Disruptive Features                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

COMPLEX_QUERY="Os SSRIs modulam genes clock (PER2, BMAL1) através do aumento de serotonina, alterando ritmos circadianos. Isso explica a latência terapêutica na depressão?"

echo "Test Query:"
echo "$COMPLEX_QUERY"
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 1: Baseline Chat (/dev/chat)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
start1=$(date +%s%3N)
response1=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3030/dev/chat \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"$COMPLEX_QUERY\"}")
end1=$(date +%s%3N)
http_code1=$(echo "$response1" | tail -1)
body1=$(echo "$response1" | head -n -1)
if [ "$http_code1" = "200" ]; then
    latency1=$((end1 - start1))
    echo "⏱️  Latency: ${latency1}ms"
    echo "📊 Domain: $(echo "$body1" | jq -r '.domain // "N/A"')"
    echo "📝 Response (200 chars):"
    echo "$body1" | jq -r '.response // .message // "No response"' | head -c 200
    echo "..."
    SESSION_ID=$(echo "$body1" | jq -r '.session_id // ""')
else
    echo "❌ Failed (HTTP $http_code1)"
    echo "$body1" | head -c 500
fi
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 2: Adversarial Debate (/dev/debate)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
start2=$(date +%s%3N)
response2=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3030/dev/debate \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$COMPLEX_QUERY\"}")
end2=$(date +%s%3N)
http_code2=$(echo "$response2" | tail -1)
body2=$(echo "$response2" | head -n -1)
if [ "$http_code2" = "200" ]; then
    latency2=$((end2 - start2))
    echo "⏱️  Latency: ${latency2}ms"
    echo "🥊 Rounds: $(echo "$body2" | jq -r '.transcript.rounds | length // 0')"
    echo "📊 Confidence: $(echo "$body2" | jq -r '.transcript.synthesis.final_confidence // "N/A"')"
    echo
    echo "Debate Rounds:"
    echo "$body2" | jq -r '.transcript.rounds[]? | "  Round \(.round_number):\n    PRO: \(.proponent_argument[0:120])...\n    CON: \(.opponent_rebuttal[0:120])..."' 2>/dev/null || echo "  (No rounds data)"
    echo
    echo "Synthesis:"
    echo "$body2" | jq -r '.transcript.synthesis.conclusion // "N/A"' | head -c 250
    echo "..."
else
    echo "❌ Failed (HTTP $http_code2)"
    echo "$body2" | head -c 500
fi
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 3: Parallel Multi-Agent (/dev/research/parallel)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
start3=$(date +%s%3N)
response3=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3030/dev/research/parallel \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$COMPLEX_QUERY\"}")
end3=$(date +%s%3N)
http_code3=$(echo "$response3" | tail -1)
body3=$(echo "$response3" | head -n -1)
if [ "$http_code3" = "200" ]; then
    latency3=$((end3 - start3))
    echo "⏱️  Latency: ${latency3}ms"
    echo "🤖 LLM Calls: $(echo "$body3" | jq -r '.metrics.llm_calls // "N/A"')"
    echo "⭐ Quality: $(echo "$body3" | jq -r '.metrics.quality_score // "N/A"')"
    echo
    echo "Execution Steps:"
    echo "$body3" | jq -r '.steps[]? | "  [\(.step_number)] \(.action) - \(.duration_ms)ms"' 2>/dev/null || echo "  (No steps data)"
else
    echo "❌ Failed (HTTP $http_code3)"
    echo "$body3" | head -c 500
fi
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 4: Hypergraph Reasoning (/dev/reasoning)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
start4=$(date +%s%3N)
response4=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3030/dev/reasoning \
  -H "Content-Type: application/json" \
  -d '{"source": "serotonina", "target": "ritmos circadianos", "max_hops": 3}')
end4=$(date +%s%3N)
http_code4=$(echo "$response4" | tail -1)
body4=$(echo "$response4" | head -n -1)
if [ "$http_code4" = "200" ]; then
    latency4=$((end4 - start4))
    echo "⏱️  Latency: ${latency4}ms"
    echo "🕸️  Paths: $(echo "$body4" | jq -r '.paths | length // 0')"
    echo
    echo "Top Path:"
    echo "$body4" | jq -r '.paths[0]? | "  Confidence: \(.confidence // \"N/A\")\n  Hops: \(.hops // \"N/A\")\n  Explanation: \(.explanation[0:200] // \"N/A\")..."' 2>/dev/null || echo "  (No path data)"
else
    echo "❌ Failed (HTTP $http_code4)"
    echo "$body4" | head -c 500
fi
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 5: Causal Discovery (/dev/causal/extract)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CAUSAL_TEXT="SSRIs aumentam serotonina sináptica. A serotonina modula genes clock como PER2 e BMAL1. Esses genes regulam ritmos circadianos. Ritmos circadianos normalizados reduzem sintomas depressivos."
start5=$(date +%s%3N)
response5=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3030/dev/causal/extract \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"$CAUSAL_TEXT\"}")
end5=$(date +%s%3N)
http_code5=$(echo "$response5" | tail -1)
body5=$(echo "$response5" | head -n -1)
if [ "$http_code5" = "200" ]; then
    latency5=$((end5 - start5))
    echo "⏱️  Latency: ${latency5}ms"
    echo "🔗 Nodes: $(echo "$body5" | jq -r '.graph.nodes | length // 0')"
    echo "→  Edges: $(echo "$body5" | jq -r '.graph.edges | length // 0')"
    echo
    echo "Causal Edges:"
    echo "$body5" | jq -r '.graph.edges[]? | "  \(.from) --[\(.edge_type // \"N/A\"), \(.strength // 0)]-> \(.to)"' 2>/dev/null | head -5 || echo "  (No edges data)"
else
    echo "❌ Failed (HTTP $http_code5)"
    echo "$body5" | head -c 500
fi
echo

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  RESULTS SUMMARY                                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
printf "%-30s %-15s %-15s\n" "Feature" "HTTP Status" "Latency"
printf "%-30s %-15s %-15s\n" "------------------------------" "---------------" "---------------"
printf "%-30s %-15s %-15s\n" "Baseline Chat" "$http_code1" "${latency1:-N/A}ms"
printf "%-30s %-15s %-15s\n" "Adversarial Debate" "$http_code2" "${latency2:-N/A}ms"
printf "%-30s %-15s %-15s\n" "Parallel Multi-Agent" "$http_code3" "${latency3:-N/A}ms"
printf "%-30s %-15s %-15s\n" "Hypergraph Reasoning" "$http_code4" "${latency4:-N/A}ms"
printf "%-30s %-15s %-15s\n" "Causal Discovery" "$http_code5" "${latency5:-N/A}ms"
echo

success_count=0
[ "$http_code1" = "200" ] && success_count=$((success_count + 1))
[ "$http_code2" = "200" ] && success_count=$((success_count + 1))
[ "$http_code3" = "200" ] && success_count=$((success_count + 1))
[ "$http_code4" = "200" ] && success_count=$((success_count + 1))
[ "$http_code5" = "200" ] && success_count=$((success_count + 1))

echo "✅ Success Rate: $success_count/5 features operational"
echo

echo "🛑 Stopping server..."
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

echo

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  TEST SUITE COMPLETE                                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "Full logs: /tmp/beagle-test.log"
echo

if [ $success_count -eq 5 ]; then
    echo "🎉 ALL FEATURES OPERATIONAL! Ready for commit."
    echo
    echo "Next: Run commit script"
elif [ $success_count -ge 3 ]; then
    echo "⚠️  $success_count/5 features working. Review failed endpoints."
    echo
    echo "Check logs for failed features"
else
    echo "❌ Only $success_count/5 features working. Debug required."
    echo
    echo "Review /tmp/beagle-test.log for errors"
fi
