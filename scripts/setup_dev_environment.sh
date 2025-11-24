#!/bin/bash
# BEAGLE Development Environment Setup Script
# Sets up complete development environment for BEAGLE system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            PACKAGE_MANAGER="brew"
            ;;
        Linux*)
            OS="linux"
            if command -v apt-get >/dev/null 2>&1; then
                PACKAGE_MANAGER="apt"
            elif command -v yum >/dev/null 2>&1; then
                PACKAGE_MANAGER="yum"
            elif command -v pacman >/dev/null 2>&1; then
                PACKAGE_MANAGER="pacman"
            else
                log_error "Unsupported Linux distribution"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
    log_info "Detected OS: $OS with package manager: $PACKAGE_MANAGER"
}

# Install system dependencies
install_system_deps() {
    log_header "Installing System Dependencies"

    case "$PACKAGE_MANAGER" in
        "brew")
            log_info "Installing macOS dependencies with Homebrew..."

            # Check if Homebrew is installed
            if ! command -v brew >/dev/null 2>&1; then
                log_info "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi

            # Update Homebrew
            brew update

            # Install dependencies
            local packages=(
                "curl"
                "git"
                "wget"
                "jq"
                "pandoc"
                "docker"
                "docker-compose"
                "node"
                "npm"
                "python@3.11"
                "postgresql"
                "redis"
            )

            for package in "${packages[@]}"; do
                if brew list "$package" >/dev/null 2>&1; then
                    log_info "$package already installed"
                else
                    log_info "Installing $package..."
                    brew install "$package"
                fi
            done
            ;;

        "apt")
            log_info "Installing Linux dependencies with apt..."

            # Update package list
            sudo apt update

            # Install dependencies
            local packages=(
                "curl"
                "wget"
                "git"
                "jq"
                "build-essential"
                "pkg-config"
                "libssl-dev"
                "pandoc"
                "docker.io"
                "docker-compose"
                "nodejs"
                "npm"
                "python3"
                "python3-pip"
                "python3-venv"
                "postgresql-client"
                "redis-tools"
            )

            sudo apt install -y "${packages[@]}"

            # Add user to docker group
            sudo usermod -aG docker "$USER"
            log_warning "You may need to log out and back in for Docker permissions to take effect"
            ;;

        *)
            log_error "Package manager $PACKAGE_MANAGER not supported yet"
            exit 1
            ;;
    esac

    log_success "System dependencies installed"
}

# Install Rust toolchain
install_rust() {
    log_header "Installing Rust Toolchain"

    if command -v rustc >/dev/null 2>&1; then
        log_info "Rust already installed: $(rustc --version)"

        # Update Rust
        log_info "Updating Rust toolchain..."
        rustup update
    else
        log_info "Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

        # Source cargo environment
        source "$HOME/.cargo/env"
    fi

    # Install additional components
    log_info "Installing Rust components..."
    rustup component add clippy rustfmt

    # Install useful cargo extensions
    log_info "Installing cargo extensions..."
    local cargo_tools=(
        "cargo-watch"
        "cargo-edit"
        "cargo-outdated"
        "cargo-audit"
        "cargo-tarpaulin"
    )

    for tool in "${cargo_tools[@]}"; do
        if cargo install --list | grep -q "^$tool "; then
            log_info "$tool already installed"
        else
            log_info "Installing $tool..."
            cargo install "$tool"
        fi
    done

    log_success "Rust toolchain configured"
}

# Setup Python environment
setup_python_env() {
    log_header "Setting up Python Environment"

    cd "$PROJECT_ROOT"

    # Create virtual environment for LoRA training
    if [ ! -d "venv_lora" ]; then
        log_info "Creating Python virtual environment for LoRA training..."
        python3 -m venv venv_lora
    fi

    # Activate virtual environment
    source venv_lora/bin/activate

    # Upgrade pip
    pip install --upgrade pip

    # Install LoRA training dependencies
    log_info "Installing LoRA training dependencies..."
    local python_packages=(
        "torch"
        "transformers>=4.36.0"
        "datasets"
        "trl"
        "accelerate"
        "bitsandbytes"
        "scipy"
        "numpy"
        "pandas"
        "scikit-learn"
    )

    pip install "${python_packages[@]}"

    # Try to install unsloth (may require specific setup)
    log_info "Attempting to install unsloth..."
    pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git" || {
        log_warning "Unsloth installation failed - will need manual setup"
    }

    deactivate

    log_success "Python environment configured"
}

# Setup Node.js environment
setup_nodejs_env() {
    log_header "Setting up Node.js Environment"

    # Check Node.js version
    local node_version
    node_version=$(node --version | cut -d'v' -f2)
    local required_major=18

    local node_major
    node_major=$(echo "$node_version" | cut -d'.' -f1)

    if [ "$node_major" -lt "$required_major" ]; then
        log_error "Node.js version $node_version is too old. Required: >= $required_major.x"
        log_info "Please upgrade Node.js"
        exit 1
    fi

    log_success "Node.js version $node_version is compatible"

    # Install MCP server dependencies
    cd "$PROJECT_ROOT/beagle-mcp-server"

    if [ ! -f "package.json" ]; then
        log_warning "MCP server package.json not found, creating basic setup..."
        npm init -y
        npm install --save-dev typescript @types/node
        npm install @modelcontextprotocol/sdk zod
    else
        log_info "Installing MCP server dependencies..."
        npm install
    fi

    # Build MCP server
    if [ -f "tsconfig.json" ]; then
        log_info "Building MCP server..."
        npm run build || log_warning "MCP build failed - may need manual setup"
    fi

    cd "$PROJECT_ROOT"
    log_success "Node.js environment configured"
}

# Setup Docker services
setup_docker_services() {
    log_header "Setting up Docker Services"

    # Start Docker daemon if not running
    if ! docker info >/dev/null 2>&1; then
        log_info "Starting Docker daemon..."
        case "$OS" in
            "macos")
                open -a Docker || log_error "Please start Docker Desktop manually"
                ;;
            "linux")
                sudo systemctl start docker
                sudo systemctl enable docker
                ;;
        esac

        # Wait for Docker to start
        log_info "Waiting for Docker to start..."
        for i in {1..30}; do
            if docker info >/dev/null 2>&1; then
                break
            fi
            sleep 2
        done
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    log_success "Docker daemon is running"

    # Create development docker-compose file
    create_docker_compose_dev

    cd "$PROJECT_ROOT"

    # Pull required images
    log_info "Pulling Docker images..."
    docker-compose -f docker-compose.dev-complete.yml pull || log_warning "Some images may not be available"

    # Start services
    log_info "Starting development services..."
    docker-compose -f docker-compose.dev-complete.yml up -d

    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10

    log_success "Docker services started"
}

# Create comprehensive development docker-compose
create_docker_compose_dev() {
    log_info "Creating development docker-compose configuration..."

    cat > "$PROJECT_ROOT/docker-compose.dev-complete.yml" << 'EOF'
version: '3.8'

services:
  # PostgreSQL for structured data
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: beagle_dev
      POSTGRES_USER: beagle
      POSTGRES_PASSWORD: beagle_dev_password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U beagle"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Neo4j for knowledge graph
  neo4j:
    image: neo4j:5.13
    environment:
      NEO4J_AUTH: neo4j/beagle_dev_password
      NEO4J_PLUGINS: '["apoc", "graph-data-science"]'
      NEO4J_dbms_security_procedures_unrestricted: apoc.*,gds.*
      NEO4J_apoc_export_file_enabled: true
      NEO4J_apoc_import_file_enabled: true
      NEO4J_apoc_import_file_use__neo4j__config: true
    ports:
      - "7474:7474"  # HTTP
      - "7687:7687"  # Bolt
    volumes:
      - neo4j_data:/data
      - neo4j_logs:/logs
      - neo4j_import:/var/lib/neo4j/import
      - neo4j_plugins:/plugins
    healthcheck:
      test: ["CMD-SHELL", "cypher-shell -u neo4j -p beagle_dev_password 'RETURN 1'"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Qdrant for vector storage
  qdrant:
    image: qdrant/qdrant:v1.7.0
    ports:
      - "6333:6333"  # HTTP API
      - "6334:6334"  # gRPC API
    volumes:
      - qdrant_data:/qdrant/storage
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:6333/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Redis for caching
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Optional: vLLM for local LLM inference
  # Uncomment if you have GPU support and want local LLM
  # vllm:
  #   image: vllm/vllm-openai:latest
  #   ports:
  #     - "8000:8000"
  #   environment:
  #     - MODEL_NAME=microsoft/DialoGPT-medium
  #   volumes:
  #     - vllm_models:/root/.cache/huggingface
  #   deploy:
  #     resources:
  #       reservations:
  #         devices:
  #           - driver: nvidia
  #             count: 1
  #             capabilities: [gpu]

  # Prometheus for metrics (optional)
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./observability/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'

  # Grafana for monitoring (optional)
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=beagle_admin
    volumes:
      - grafana_data:/var/lib/grafana

volumes:
  postgres_data:
  neo4j_data:
  neo4j_logs:
  neo4j_import:
  neo4j_plugins:
  qdrant_data:
  redis_data:
  prometheus_data:
  grafana_data:
  # vllm_models:

networks:
  default:
    name: beagle_dev_network
EOF

    log_success "Development docker-compose created"
}

# Create environment configuration
create_env_config() {
    log_header "Creating Environment Configuration"

    # Create .env.template
    cat > "$PROJECT_ROOT/.env.template" << 'EOF'
# BEAGLE Development Environment Configuration
# Copy this file to .env and configure your actual values

# =============================================================================
# CORE CONFIGURATION
# =============================================================================

# Environment profile (dev, lab, prod)
BEAGLE_PROFILE=dev

# Safety mode (true for development, false for production)
BEAGLE_SAFE_MODE=true

# Data directory for artifacts
BEAGLE_DATA_DIR=./data

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# PostgreSQL
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=beagle_dev
POSTGRES_USER=beagle
POSTGRES_PASSWORD=beagle_dev_password
DATABASE_URL=postgresql://beagle:beagle_dev_password@localhost:5432/beagle_dev

# Neo4j
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=beagle_dev_password

# Qdrant
QDRANT_URL=http://localhost:6333
QDRANT_API_KEY=

# Redis
REDIS_URL=redis://localhost:6379

# =============================================================================
# LLM SERVICE CONFIGURATION
# =============================================================================

# Local vLLM (if running)
VLLM_URL=http://localhost:8000

# OpenAI API
OPENAI_API_KEY=your_openai_api_key_here

# Anthropic Claude API
ANTHROPIC_API_KEY=your_anthropic_api_key_here

# Grok/X.AI API
XAI_API_KEY=your_xai_api_key_here

# =============================================================================
# EXTERNAL APIS
# =============================================================================

# Twitter API (optional)
TWITTER_BEARER_TOKEN=your_twitter_bearer_token_here

# arXiv API (for submission - optional)
ARXIV_API_TOKEN=your_arxiv_api_token_here

# =============================================================================
# MCP CONFIGURATION
# =============================================================================

# MCP Server settings
MCP_TRANSPORT=stdio
MCP_HTTP_PORT=3001
MCP_AUTH_TOKEN=your_mcp_auth_token_here

# =============================================================================
# MONITORING & OBSERVABILITY
# =============================================================================

# Logging
RUST_LOG=info
RUST_LOG_JSON=false

# Metrics
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=9090

# Health checks
HEALTH_CHECK_INTERVAL=30

# =============================================================================
# DEVELOPMENT SETTINGS
# =============================================================================

# Enable debug features
DEBUG_MODE=true

# Development server settings
DEV_SERVER_PORT=8080
DEV_SERVER_HOST=localhost

# Test database (separate from main)
TEST_DATABASE_URL=postgresql://beagle:beagle_dev_password@localhost:5432/beagle_test
EOF

    # Create actual .env if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log_info "Creating .env file from template..."
        cp "$PROJECT_ROOT/.env.template" "$PROJECT_ROOT/.env"
        log_warning "Please edit .env file with your actual API keys and configurations"
    fi

    log_success "Environment configuration created"
}

# Setup project directories
setup_directories() {
    log_header "Setting up Project Directories"

    cd "$PROJECT_ROOT"

    local directories=(
        "data/knowledge"
        "data/papers"
        "data/memory"
        "data/logs"
        "data/exports"
        "logs/audit"
        "logs/pipeline"
        "logs/services"
        "temp/lora"
        "temp/builds"
        "docs/generated"
        "docs/api"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    done

    # Create .gitkeep files for important empty directories
    local gitkeep_dirs=(
        "data"
        "logs"
        "temp"
    )

    for dir in "${gitkeep_dirs[@]}"; do
        if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
            touch "$dir/.gitkeep"
        fi
    done

    log_success "Project directories created"
}

# Build the project
build_project() {
    log_header "Building BEAGLE Project"

    cd "$PROJECT_ROOT"

    # Check Cargo.toml exists
    if [ ! -f "Cargo.toml" ]; then
        log_error "Cargo.toml not found in project root"
        exit 1
    fi

    # Clean previous builds
    log_info "Cleaning previous builds..."
    cargo clean

    # Build in debug mode first
    log_info "Building project in debug mode..."
    if cargo build --workspace; then
        log_success "Debug build successful"
    else
        log_error "Debug build failed"
        exit 1
    fi

    # Run basic tests
    log_info "Running basic tests..."
    if cargo test --workspace --lib; then
        log_success "Basic tests passed"
    else
        log_warning "Some tests failed - this may be expected in development"
    fi

    # Build documentation
    log_info "Building documentation..."
    cargo doc --workspace --no-deps

    log_success "Project built successfully"
}

# Verify setup
verify_setup() {
    log_header "Verifying Development Environment Setup"

    local verification_script="$SCRIPT_DIR/check_external_services.sh"

    if [ -x "$verification_script" ]; then
        log_info "Running external services check..."
        "$verification_script" || log_warning "Some services are not available - this is normal for development"
    else
        log_warning "External services check script not found or not executable"
    fi

    # Check that we can run basic BEAGLE commands
    cd "$PROJECT_ROOT"

    log_info "Testing basic BEAGLE functionality..."

    # Test compilation
    if cargo check --workspace --quiet; then
        log_success "✅ Project compiles successfully"
    else
        log_error "❌ Project compilation failed"
    fi

    # Test if we can list available binaries
    log_info "Available BEAGLE binaries:"
    cargo install --list --root ./target 2>/dev/null || log_info "No binaries installed yet"

    # Check if MCP server can be built
    if [ -d "beagle-mcp-server" ]; then
        cd beagle-mcp-server
        if [ -f "package.json" ] && npm run build >/dev/null 2>&1; then
            log_success "✅ MCP server builds successfully"
        else
            log_warning "⚠️  MCP server build issues"
        fi
        cd "$PROJECT_ROOT"
    fi

    log_success "Development environment verification complete"
}

# Print setup summary
print_setup_summary() {
    log_header "Development Environment Setup Complete!"

    cat << EOF

🎉 BEAGLE development environment is ready!

📁 Project Structure:
   - Source code: $PROJECT_ROOT/crates/ and $PROJECT_ROOT/apps/
   - Data directory: $PROJECT_ROOT/data/
   - Logs: $PROJECT_ROOT/logs/
   - Documentation: $PROJECT_ROOT/target/doc/

🔧 Services Available:
   - PostgreSQL: localhost:5432 (beagle_dev database)
   - Neo4j: localhost:7474 (HTTP), localhost:7687 (Bolt)
   - Qdrant: localhost:6333
   - Redis: localhost:6379
   - Prometheus: localhost:9090 (monitoring)
   - Grafana: localhost:3000 (dashboards, admin/beagle_admin)

🚀 Next Steps:
   1. Edit .env file with your API keys:
      vi $PROJECT_ROOT/.env

   2. Start the development services:
      docker-compose -f docker-compose.dev-complete.yml up -d

   3. Run the audit script:
      ./scripts/audit_system.sh

   4. Build and test the system:
      cargo build --workspace
      cargo test --workspace

   5. Start the core server:
      cargo run --bin core_server

📚 Documentation:
   - Local docs: file://$PROJECT_ROOT/target/doc/index.html
   - Environment template: $PROJECT_ROOT/.env.template
   - Docker services: $PROJECT_ROOT/docker-compose.dev-complete.yml

🔍 Troubleshooting:
   - Check service status: ./scripts/check_external_services.sh
   - View logs: docker-compose -f docker-compose.dev-complete.yml logs
   - Restart services: docker-compose -f docker-compose.dev-complete.yml restart

Happy coding! 🦀🚀

EOF
}

# Main execution function
main() {
    log_info "Starting BEAGLE development environment setup..."

    # Change to project root
    cd "$PROJECT_ROOT"

    # Run setup steps
    detect_os
    install_system_deps
    install_rust
    setup_python_env
    setup_nodejs_env
    create_env_config
    setup_directories
    setup_docker_services
    build_project
    verify_setup
    print_setup_summary

    log_success "Development environment setup completed successfully!"
}

# Handle script arguments
case "${1:-setup}" in
    "setup")
        main
        ;;
    "verify")
        verify_setup
        ;;
    "services")
        setup_docker_services
        ;;
    "build")
        build_project
        ;;
    "help"|"-h"|"--help")
        cat << EOF
BEAGLE Development Environment Setup

Usage: $0 [command]

Commands:
    setup     Run complete development environment setup (default)
    verify    Verify existing setup
    services  Setup and start Docker services only
    build     Build project only
    help      Show this help message

Examples:
    $0              # Run complete setup
    $0 setup        # Run complete setup
    $0 verify       # Check if environment is working
    $0 services     # Setup Docker services only

EOF
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Run '$0 help' for usage information"
        exit 1
        ;;
esac
