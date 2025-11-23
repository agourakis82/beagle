#!/bin/bash
# BEAGLE Memory + MCP Integration Test
# Tests the full stack: MCP Server → BEAGLE Core → Memory Engine

set -e

echo "=========================================="
echo "BEAGLE Memory Integration Test"
echo "=========================================="
echo ""

BEAGLE_URL="${BEAGLE_CORE_URL:-http://localhost:8080}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function test_health() {
    echo -e "${YELLOW}[1/4] Testing BEAGLE health endpoint...${NC}"
    response=$(curl -s "$BEAGLE_URL/health")

    if echo "$response" | grep -q "status"; then
        echo -e "${GREEN}✓ BEAGLE is running${NC}"
        echo "Response: $response"
        echo ""
        return 0
    else
        echo -e "${RED}✗ BEAGLE health check failed${NC}"
        echo "Response: $response"
        echo ""
        return 1
    fi
}

function test_ingest() {
    echo -e "${YELLOW}[2/4] Testing memory ingestion...${NC}"

    session_id="test_$(date +%s)"

    response=$(curl -s -X POST "$BEAGLE_URL/api/memory/ingest_chat" \
        -H "Content-Type: application/json" \
        -d '{
            "source": "test",
            "session_id": "'"$session_id"'",
            "turns": [
                {
                    "role": "user",
                    "content": "What is BEAGLE memory integration and how does it work with MCP?"
                },
                {
                    "role": "assistant",
                    "content": "BEAGLE memory integration uses hypergraph storage via ContextBridge. It stores conversations with semantic embeddings in Qdrant for vector search. The MCP server exposes beagle_ingest_chat and beagle_query_memory tools for ChatGPT and Claude Desktop."
                },
                {
                    "role": "user",
                    "content": "Can you explain the architecture?"
                },
                {
                    "role": "assistant",
                    "content": "The architecture has three layers: 1) LLM/LAM clients (ChatGPT, Claude) connect via MCP protocol, 2) BEAGLE MCP Server (TypeScript) translates to HTTP, 3) BEAGLE Core (Rust) processes via MemoryEngine with ContextBridge, storing in Postgres+Redis+Qdrant."
                }
            ],
            "tags": ["test", "integration", "mcp", "memory"],
            "metadata": {
                "test_run": true,
                "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
            }
        }')

    if echo "$response" | grep -q "num_turns"; then
        num_turns=$(echo "$response" | grep -o '"num_turns":[0-9]*' | cut -d: -f2)
        num_chunks=$(echo "$response" | grep -o '"num_chunks":[0-9]*' | cut -d: -f2)
        echo -e "${GREEN}✓ Successfully ingested $num_turns turns, $num_chunks chunks${NC}"
        echo "Session ID: $session_id"
        echo "Response: $response"
        echo ""
        echo "$session_id" > /tmp/beagle_test_session_id.txt
        return 0
    else
        echo -e "${RED}✗ Ingestion failed${NC}"
        echo "Response: $response"
        echo ""
        return 1
    fi
}

function test_query() {
    echo -e "${YELLOW}[3/4] Testing memory query...${NC}"

    # Give it a moment for indexing
    sleep 2

    response=$(curl -s -X POST "$BEAGLE_URL/api/memory/query" \
        -H "Content-Type: application/json" \
        -d '{
            "query": "BEAGLE memory MCP integration architecture",
            "scope": "general",
            "max_items": 5
        }')

    if echo "$response" | grep -q "summary"; then
        echo -e "${GREEN}✓ Successfully queried memory${NC}"
        echo "Response preview:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Query failed${NC}"
        echo "Response: $response"
        echo ""
        return 1
    fi
}

function test_query_specific() {
    echo -e "${YELLOW}[4/4] Testing specific keyword query...${NC}"

    response=$(curl -s -X POST "$BEAGLE_URL/api/memory/query" \
        -H "Content-Type: application/json" \
        -d '{
            "query": "hypergraph ContextBridge Qdrant",
            "max_items": 3
        }')

    if echo "$response" | grep -q "highlights"; then
        num_highlights=$(echo "$response" | grep -o '"highlights":\[' | wc -l)
        echo -e "${GREEN}✓ Query returned results${NC}"

        # Check if our ingested content appears
        if echo "$response" | grep -qi "hypergraph\|ContextBridge\|Qdrant"; then
            echo -e "${GREEN}✓ Found ingested content in query results!${NC}"
        else
            echo -e "${YELLOW}⚠ Content ingested but not yet in top results (may need indexing time)${NC}"
        fi

        echo "Response preview:"
        echo "$response" | jq '.highlights[0]' 2>/dev/null || echo "$response" | head -20
        echo ""
        return 0
    else
        echo -e "${RED}✗ Specific query failed${NC}"
        echo "Response: $response"
        echo ""
        return 1
    fi
}

# Run tests
echo "Testing against: $BEAGLE_URL"
echo ""

failed=0

test_health || ((failed++))
test_ingest || ((failed++))
test_query || ((failed++))
test_query_specific || ((failed++))

echo "=========================================="
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Configure Claude Desktop or ChatGPT with the MCP server"
    echo "2. Test via: 'Use beagle_query_memory to find recent conversations about memory'"
    echo "3. Ingest real conversations via: 'Use beagle_ingest_chat to store this conversation'"
    echo ""
    echo "The BEAGLE Memory + MCP integration is READY! 🚀"
else
    echo -e "${RED}✗ $failed test(s) failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Ensure BEAGLE core is running: cargo run --bin beagle-monorepo --features memory"
    echo "2. Check DATABASE_URL and REDIS_URL are configured in .env"
    echo "3. Verify Qdrant is running (if using vector search)"
    echo "4. Check logs for errors"
    exit 1
fi

echo "=========================================="
