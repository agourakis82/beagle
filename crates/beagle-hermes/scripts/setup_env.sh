#!/bin/bash
# Setup environment variables for HERMES BPSE

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔧 Setting up HERMES BPSE environment..."

# Check if .env exists
if [ ! -f "$HERMES_DIR/.env" ]; then
    echo "📝 Creating .env from .env.example..."
    cp "$HERMES_DIR/.env.example" "$HERMES_DIR/.env"
    echo "⚠️  Please edit .env and fill in your API keys and configuration"
else
    echo "✅ .env already exists"
fi

# Load environment variables
if [ -f "$HERMES_DIR/.env" ]; then
    echo "📥 Loading environment variables..."
    set -a
    source "$HERMES_DIR/.env"
    set +a
    echo "✅ Environment variables loaded"
fi

# Check required variables
echo ""
echo "🔍 Checking required environment variables..."

REQUIRED_VARS=(
    "NEO4J_URI"
    "NEO4J_USER"
    "NEO4J_PASSWORD"
    "DATABASE_URL"
    "REDIS_URL"
)

MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -eq 0 ]; then
    echo "✅ All required variables are set"
else
    echo "⚠️  Missing required variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    echo ""
    echo "Please set these in .env file"
    exit 1
fi

# Check optional API keys
echo ""
echo "🔑 Checking optional API keys..."

OPTIONAL_VARS=(
    "ANTHROPIC_API_KEY"
    "SEMANTIC_SCHOLAR_API_KEY"
    "OPENAI_API_KEY"
)

for var in "${OPTIONAL_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "⚠️  $var not set (some features may not work)"
    else
        echo "✅ $var is set"
    fi
done

echo ""
echo "✅ Environment setup complete!"
echo ""
echo "Next steps:"
echo "  1. Edit .env and fill in your API keys"
echo "  2. Start Neo4j: docker-compose -f docker-compose.neo4j.yml up -d"
echo "  3. Start PostgreSQL and Redis"
echo "  4. Run tests: cargo test --test integration_test"

