#!/bin/bash
set -e

echo "🚀 HERMES BPSE - Starting..."

# Wait for dependencies
echo "⏳ Waiting for dependencies..."

# Wait for PostgreSQL
if [ -n "$DATABASE_URL" ]; then
    echo "  → PostgreSQL..."
    until pg_isready -h $(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p') -p $(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\).*/\1/p') 2>/dev/null; do
        sleep 1
    done
    echo "  ✅ PostgreSQL ready"
fi

# Wait for Neo4j
if [ -n "$NEO4J_URI" ]; then
    echo "  → Neo4j..."
    NEO4J_HOST=$(echo $NEO4J_URI | sed -n 's/.*@\([^:]*\):.*/\1/p')
    NEO4J_PORT=$(echo $NEO4J_URI | sed -n 's/.*:\([0-9]*\).*/\1/p')
    until nc -z $NEO4J_HOST $NEO4J_PORT 2>/dev/null; do
        sleep 1
    done
    echo "  ✅ Neo4j ready"
fi

# Wait for Redis
if [ -n "$REDIS_URL" ]; then
    echo "  → Redis..."
    REDIS_HOST=$(echo $REDIS_URL | sed -n 's/.*\/\/\([^:]*\):.*/\1/p')
    REDIS_PORT=$(echo $REDIS_URL | sed -n 's/.*:\([0-9]*\).*/\1/p')
    until nc -z $REDIS_HOST $REDIS_PORT 2>/dev/null; do
        sleep 1
    done
    echo "  ✅ Redis ready"
fi

# Run migrations if needed
if [ -n "$DATABASE_URL" ] && [ -d "/app/migrations" ]; then
    echo "📊 Running database migrations..."
    # TODO: Add migration runner here
    # sqlx migrate run --database-url $DATABASE_URL
fi

# Execute command
echo "✅ All dependencies ready. Starting HERMES..."
exec "$@"

