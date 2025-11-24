# BEAGLE Development Setup Guide

**Complete guide to setting up a working BEAGLE development environment**

---

## 🎯 Overview

This guide will help you set up a complete BEAGLE development environment, from zero to running system. BEAGLE is a complex system with multiple components, so proper setup is crucial.

### What You'll Get

After following this guide, you'll have:
- ✅ Complete Rust toolchain with all required tools
- ✅ All external services running (Neo4j, Qdrant, PostgreSQL, Redis)
- ✅ Python environment for LoRA training
- ✅ Node.js environment for MCP server
- ✅ Working BEAGLE core system
- ✅ Proper monitoring and development tools

---

## 📋 Prerequisites

### System Requirements

**Minimum:**
- **OS**: macOS 10.15+, Ubuntu 20.04+, or similar Linux
- **RAM**: 16GB (32GB recommended)
- **Storage**: 50GB free space
- **CPU**: 4+ cores (8+ recommended)

**For LoRA Training:**
- **GPU**: NVIDIA GPU with 8GB+ VRAM (optional but recommended)
- **CUDA**: Version 11.8+ if using GPU

### Required Accounts & API Keys

Before starting, obtain API keys for:
- **OpenAI** (required): https://platform.openai.com/api-keys
- **Anthropic** (required): https://console.anthropic.com/
- **Grok/X.AI** (recommended): https://x.ai/api
- **Twitter** (optional): https://developer.twitter.com/
- **arXiv** (optional): https://arxiv.org/help/api/

---

## 🚀 Quick Start (Automated)

### Option 1: Automated Setup Script

```bash
# Clone the repository
git clone <your-beagle-repo-url>
cd beagle-remote

# Run automated setup
chmod +x scripts/setup_dev_environment.sh
./scripts/setup_dev_environment.sh

# Follow the prompts and wait for completion
# This takes 15-30 minutes depending on your system
```

The script will:
1. Detect your OS and install system dependencies
2. Install Rust toolchain and extensions
3. Set up Python environment for LoRA training
4. Configure Node.js for MCP server
5. Start all required Docker services
6. Build the BEAGLE project
7. Verify everything is working

### Option 2: Manual Step-by-Step

If you prefer manual control or the script fails, follow the detailed instructions below.

---

## 🛠️ Manual Setup Instructions

### Step 1: System Dependencies

#### macOS (using Homebrew)

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required packages
brew update
brew install curl git wget jq pandoc docker docker-compose node npm python@3.11 postgresql redis
```

#### Ubuntu/Debian

```bash
# Update package list
sudo apt update

# Install dependencies
sudo apt install -y curl wget git jq build-essential pkg-config libssl-dev \
    pandoc docker.io docker-compose nodejs npm python3 python3-pip python3-venv \
    postgresql-client redis-tools

# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

#### Arch Linux

```bash
# Install dependencies
sudo pacman -S curl wget git jq base-devel openssl pandoc docker docker-compose \
    nodejs npm python python-pip postgresql redis

# Enable Docker service
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

### Step 2: Rust Toolchain

```bash
# Install Rust via rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Reload shell environment
source ~/.cargo/env

# Install Rust components
rustup component add clippy rustfmt

# Install useful cargo tools
cargo install cargo-watch cargo-edit cargo-outdated cargo-audit cargo-tarpaulin
```

### Step 3: Python Environment (LoRA Training)

```bash
cd beagle-remote

# Create virtual environment
python3 -m venv venv_lora
source venv_lora/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install PyTorch (CPU version - adjust for your hardware)
pip install torch torchvision torchaudio

# For CUDA (if you have NVIDIA GPU):
# pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install training dependencies
pip install transformers>=4.36.0 datasets trl accelerate bitsandbytes scipy numpy pandas scikit-learn

# Install unsloth for efficient LoRA training
pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"

deactivate
```

### Step 4: Node.js Environment (MCP Server)

```bash
# Check Node.js version (should be 18+)
node --version

# If too old, install newer version:
# curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
# sudo apt-get install -y nodejs

# Install MCP server dependencies
cd beagle-mcp-server
npm install
npm run build

cd ..
```

### Step 5: Docker Services

```bash
# Start Docker daemon (varies by OS)
# macOS: Open Docker Desktop
# Linux: sudo systemctl start docker

# Create docker-compose configuration
cp docker-compose.dev.yml docker-compose.dev-complete.yml

# Edit docker-compose.dev-complete.yml to ensure all services are included:
# - PostgreSQL
# - Neo4j
# - Qdrant
# - Redis
# - Prometheus (optional)
# - Grafana (optional)

# Start services
docker-compose -f docker-compose.dev-complete.yml up -d

# Wait for services to start
sleep 30

# Verify services are running
docker-compose -f docker-compose.dev-complete.yml ps
```

### Step 6: Environment Configuration

```bash
# Copy environment template
cp .env.template .env

# Edit .env with your configuration
nano .env
```

**Required Environment Variables:**

```bash
# Core settings
BEAGLE_PROFILE=dev
BEAGLE_SAFE_MODE=true
BEAGLE_DATA_DIR=./data

# Database connections
DATABASE_URL=postgresql://beagle:beagle_dev_password@localhost:5432/beagle_dev
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=beagle_dev_password
QDRANT_URL=http://localhost:6333
REDIS_URL=redis://localhost:6379

# LLM APIs (add your actual keys)
OPENAI_API_KEY=your_openai_api_key_here
ANTHROPIC_API_KEY=your_anthropic_api_key_here
XAI_API_KEY=your_xai_api_key_here

# Local vLLM (if running)
VLLM_URL=http://localhost:8000

# Optional APIs
TWITTER_BEARER_TOKEN=your_twitter_token_here
ARXIV_API_TOKEN=your_arxiv_token_here
```

### Step 7: Project Setup

```bash
# Create data directories
mkdir -p data/{knowledge,papers,memory,logs,exports}
mkdir -p logs/{audit,pipeline,services}
mkdir -p temp/{lora,builds}

# Build the project
cargo build --workspace

# Run tests to verify setup
cargo test --workspace --lib
```

---

## ✅ Verification

### Run System Check

```bash
# Check external services
./scripts/check_external_services.sh

# Run comprehensive audit
./scripts/audit_system.sh

# Check compilation status
cargo check --workspace
```

### Test Basic Functionality

```bash
# Test LLM connection (requires API keys)
cargo test --package beagle-llm test_connection

# Test database connections
cargo test --package beagle-db test_migrations

# Test MCP server
cd beagle-mcp-server
npm test
cd ..
```

### Start Core Services

```bash
# Start the main BEAGLE server
cargo run --bin core_server

# In another terminal, test MCP server
cd beagle-mcp-server
npm start
```

---

## 🔧 Service Configuration Details

### PostgreSQL Setup

```sql
-- Connect to PostgreSQL and create database
psql -h localhost -U beagle -d postgres
CREATE DATABASE beagle_dev;
CREATE DATABASE beagle_test;
\q

-- Run migrations
cargo run --bin migrate
```

### Neo4j Configuration

1. Open Neo4j Browser: http://localhost:7474
2. Login with: `neo4j` / `beagle_dev_password`
3. Install required plugins:
   ```cypher
   CALL apoc.help("config");
   CALL gds.version();
   ```

### Qdrant Setup

```bash
# Test Qdrant connection
curl http://localhost:6333/health

# Create test collection
curl -X PUT http://localhost:6333/collections/test \
  -H "Content-Type: application/json" \
  -d '{"vectors": {"size": 384, "distance": "Cosine"}}'
```

---

## 🐛 Troubleshooting

### Common Issues

#### "Docker daemon not running"
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
sudo systemctl enable docker
```

#### "Permission denied" for Docker
```bash
sudo usermod -aG docker $USER
# Then log out and back in
```

#### "Rust compiler not found"
```bash
source ~/.cargo/env
# Or restart your terminal
```

#### "Node.js version too old"
```bash
# Install Node Version Manager
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
nvm use 18
```

#### "Python package conflicts"
```bash
# Create fresh virtual environment
rm -rf venv_lora
python3 -m venv venv_lora
source venv_lora/bin/activate
pip install --upgrade pip
# Reinstall packages
```

#### "Neo4j connection refused"
```bash
# Check if Neo4j is running
docker-compose -f docker-compose.dev-complete.yml ps

# View Neo4j logs
docker-compose -f docker-compose.dev-complete.yml logs neo4j

# Restart Neo4j
docker-compose -f docker-compose.dev-complete.yml restart neo4j
```

### Service Status Check

```bash
# Check all services
./scripts/check_external_services.sh

# Manual service checks
curl http://localhost:6333/health           # Qdrant
curl http://localhost:7474                 # Neo4j
redis-cli ping                            # Redis
pg_isready -h localhost -p 5432           # PostgreSQL
```

### Performance Issues

If the system runs slowly:

1. **Increase Docker memory allocation** (Docker Desktop → Settings → Resources)
2. **Check disk space**: `df -h`
3. **Monitor resource usage**: `docker stats`
4. **Consider using SSD** for better I/O performance

---

## 🚀 Next Steps

Once your development environment is set up:

1. **Run the audit**: `./scripts/audit_system.sh`
2. **Review findings**: `cat audit/AUDIT_SUMMARY.md`
3. **Start implementing**: Follow the restoration plan
4. **Test regularly**: Use the provided test scripts

### Development Workflow

```bash
# Daily development routine
docker-compose -f docker-compose.dev-complete.yml up -d  # Start services
cargo watch -x "build --workspace"                       # Auto-build on changes
cargo test --workspace                                   # Run tests

# Before committing
cargo clippy --workspace -- -D warnings                 # Lint code
cargo fmt --all                                         # Format code
./scripts/check_external_services.sh                    # Verify services
```

---

## 📚 Additional Resources

- **Rust Documentation**: https://doc.rust-lang.org/
- **Neo4j Documentation**: https://neo4j.com/docs/
- **Qdrant Documentation**: https://qdrant.tech/documentation/
- **Docker Compose Reference**: https://docs.docker.com/compose/

---

## 🆘 Getting Help

If you encounter issues not covered in this guide:

1. **Check the audit results**: Often reveals specific problems
2. **Review service logs**: `docker-compose logs <service>`
3. **Verify environment variables**: Ensure all required keys are set
4. **Test individual components**: Use targeted tests to isolate issues

Remember: The foundation must be solid before building advanced features!