-- Beagle Development Database Initialization

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create test database
CREATE DATABASE beagle_test;

-- Connect to test db and enable vector there too
\c beagle_test
CREATE EXTENSION IF NOT EXISTS vector;

-- Basic schema (minimal para testes funcionarem)
CREATE TABLE IF NOT EXISTS nodes (
    id UUID PRIMARY KEY,
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_nodes_embedding ON nodes USING ivfflat (embedding vector_cosine_ops);
