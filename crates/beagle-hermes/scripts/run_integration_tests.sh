#!/bin/bash
# Run end-to-end integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_DIR="$(dirname "$SCRIPT_DIR")"

echo "🧪 Running HERMES BPSE Integration Tests"
echo "=========================================="
echo ""

# Load environment
if [ -f "$HERMES_DIR/.env" ]; then
    set -a
    source "$HERMES_DIR/.env"
    set +a
fi

# Check if services are running
echo "🔍 Checking required services..."

# Check Neo4j
if command -v nc &> /dev/null; then
    if nc -z localhost 7687 2>/dev/null; then
        echo "✅ Neo4j is running"
    else
        echo "⚠️  Neo4j not running on port 7687"
        echo "   Start with: docker-compose -f docker-compose.neo4j.yml up -d"
    fi
fi

# Check PostgreSQL
if command -v nc &> /dev/null; then
    if nc -z localhost 5432 2>/dev/null; then
        echo "✅ PostgreSQL is running"
    else
        echo "⚠️  PostgreSQL not running on port 5432"
    fi
fi

# Check Redis
if command -v nc &> /dev/null; then
    if nc -z localhost 6379 2>/dev/null; then
        echo "✅ Redis is running"
    else
        echo "⚠️  Redis not running on port 6379"
    fi
fi

echo ""
echo "🚀 Running tests..."
echo ""

cd "$HERMES_DIR"

# Run unit tests first
echo "📦 Running unit tests..."
cargo test --lib 2>&1 | head -50

echo ""
echo "🔗 Running integration tests..."
echo ""

# Run integration tests (ignored by default - requires services)
cargo test --test integration_test -- --ignored 2>&1 | head -100

echo ""
echo "✅ Test run complete!"
echo ""
echo "Note: Integration tests require Neo4j, PostgreSQL, and Redis running."
echo "Start services with:"
echo "  docker-compose -f docker-compose.neo4j.yml up -d"
echo "  # Start PostgreSQL and Redis separately"

