-- Beagle Development Database Initialization

CREATE EXTENSION IF NOT EXISTS vector;

-- Basic schema (minimal) in development database
CREATE TABLE IF NOT EXISTS public.nodes (
    id UUID PRIMARY KEY,
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_nodes_embedding ON nodes USING ivfflat (embedding vector_cosine_ops);

-- Create test database idempotently
SELECT 'CREATE DATABASE beagle_test'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'beagle_test')
\gexec

-- Connect to test db and replicate setup
\c beagle_test
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.nodes (
    id UUID PRIMARY KEY,
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_nodes_embedding ON nodes USING ivfflat (embedding vector_cosine_ops);
