# HERMES BPSE - Setup Guide

## 🚀 Quick Start

### 1. Environment Setup

```bash
# Copy environment template
cp .env.example .env

# Edit .env and fill in your API keys
nano .env

# Or use the setup script
./scripts/setup_env.sh
```

### 2. Required Services

#### Neo4j
```bash
# Start Neo4j with Docker Compose
docker-compose -f docker-compose.neo4j.yml up -d

# Apply schema
docker exec -i hermes-neo4j cypher-shell -u neo4j -p hermespassword < schema/neo4j_schema.cypher
```

#### PostgreSQL
```bash
# Create database
createdb beagle

# Run migrations
cd migrations
psql beagle < 001_create_manuscripts.sql
```

#### Redis
```bash
# Start Redis (if not using Docker)
redis-server

# Or with Docker
docker run -d -p 6379:6379 redis:7-alpine
```

### 3. Python Dependencies

```bash
# Install Python dependencies
cd python
pip install -r requirements.txt

# Download spaCy model
python -m spacy download en_core_web_sm
```

### 4. Build and Test

```bash
# Build
cargo build --release

# Run unit tests
cargo test --lib

# Run integration tests (requires services)
./scripts/run_integration_tests.sh
```

## 📋 Environment Variables

### Required
- `NEO4J_URI`: Neo4j connection string
- `NEO4J_USER`: Neo4j username
- `NEO4J_PASSWORD`: Neo4j password
- `DATABASE_URL`: PostgreSQL connection string
- `REDIS_URL`: Redis connection string

### Optional (for full functionality)
- `ANTHROPIC_API_KEY`: For LLM synthesis
- `SEMANTIC_SCHOLAR_API_KEY`: For citation generation
- `OPENAI_API_KEY`: For Whisper transcription (if using API)
- `JWT_SECRET`: For authentication (change in production!)

## 🧪 Testing

### Unit Tests
```bash
cargo test --lib
```

### Integration Tests
```bash
# Requires services running
./scripts/run_integration_tests.sh
```

### Manual Testing
```bash
# Start HERMES engine
cargo run --bin hermes-cli

# Or use the Tauri app
cd tauri
npm install
npm run tauri dev
```

## 🔧 Troubleshooting

### Neo4j Connection Issues
- Check if Neo4j is running: `docker ps | grep neo4j`
- Verify credentials in `.env`
- Check firewall/network settings

### Python Dependencies
- Ensure Python 3.8+ is installed
- Use virtual environment: `python -m venv venv && source venv/bin/activate`
- Install dependencies: `pip install -r python/requirements.txt`

### Compilation Errors
- Update Rust: `rustup update`
- Clean build: `cargo clean && cargo build`
- Check Cargo.toml for dependency conflicts

## 📚 Next Steps

1. **Configure API Keys**: Edit `.env` with your API keys
2. **Start Services**: Neo4j, PostgreSQL, Redis
3. **Run Tests**: Verify everything works
4. **Start HERMES**: Begin capturing insights!

