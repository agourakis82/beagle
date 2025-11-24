#!/bin/bash
# BEAGLE External Services Check Script
# Tests connectivity to all required external services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
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

# Load environment variables if available
if [ -f "$PROJECT_ROOT/.env" ]; then
    log_info "Loading environment variables from .env"
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Service check results
declare -A SERVICE_STATUS

# Check if a service is accessible via HTTP
check_http_service() {
    local service_name="$1"
    local url="$2"
    local timeout="${3:-10}"

    log_info "Checking $service_name at $url..."

    if curl -s --max-time "$timeout" --fail "$url" >/dev/null 2>&1; then
        log_success "$service_name is accessible"
        SERVICE_STATUS["$service_name"]="UP"
        return 0
    else
        log_error "$service_name is not accessible at $url"
        SERVICE_STATUS["$service_name"]="DOWN"
        return 1
    fi
}

# Check if a service is accessible via TCP
check_tcp_service() {
    local service_name="$1"
    local host="$2"
    local port="$3"
    local timeout="${4:-5}"

    log_info "Checking $service_name at $host:$port..."

    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then
        log_success "$service_name is accessible"
        SERVICE_STATUS["$service_name"]="UP"
        return 0
    else
        log_error "$service_name is not accessible at $host:$port"
        SERVICE_STATUS["$service_name"]="DOWN"
        return 1
    fi
}

# Check API endpoint with authentication
check_authenticated_api() {
    local service_name="$1"
    local url="$2"
    local auth_header="$3"
    local timeout="${4:-10}"

    log_info "Checking authenticated $service_name..."

    if [ -z "$auth_header" ]; then
        log_warning "$service_name: No authentication provided"
        SERVICE_STATUS["$service_name"]="NO_AUTH"
        return 1
    fi

    if curl -s --max-time "$timeout" --fail -H "$auth_header" "$url" >/dev/null 2>&1; then
        log_success "$service_name API is accessible"
        SERVICE_STATUS["$service_name"]="UP"
        return 0
    else
        log_error "$service_name API is not accessible"
        SERVICE_STATUS["$service_name"]="DOWN"
        return 1
    fi
}

# Check database services
check_databases() {
    log_info "=== Checking Database Services ==="

    # PostgreSQL
    local pg_host="${POSTGRES_HOST:-localhost}"
    local pg_port="${POSTGRES_PORT:-5432}"
    check_tcp_service "PostgreSQL" "$pg_host" "$pg_port"

    # Neo4j
    local neo4j_host="${NEO4J_HOST:-localhost}"
    local neo4j_port="${NEO4J_HTTP_PORT:-7474}"
    local neo4j_url="http://${neo4j_host}:${neo4j_port}"
    check_http_service "Neo4j HTTP" "$neo4j_url"

    # Neo4j Bolt (if different)
    local neo4j_bolt_port="${NEO4J_BOLT_PORT:-7687}"
    check_tcp_service "Neo4j Bolt" "$neo4j_host" "$neo4j_bolt_port"

    # Qdrant
    local qdrant_host="${QDRANT_HOST:-localhost}"
    local qdrant_port="${QDRANT_PORT:-6333}"
    local qdrant_url="http://${qdrant_host}:${qdrant_port}/health"
    check_http_service "Qdrant" "$qdrant_url"

    # Redis
    local redis_host="${REDIS_HOST:-localhost}"
    local redis_port="${REDIS_PORT:-6379}"
    check_tcp_service "Redis" "$redis_host" "$redis_port"
}

# Check LLM services
check_llm_services() {
    log_info "=== Checking LLM Services ==="

    # vLLM (local)
    local vllm_url="${VLLM_URL:-http://localhost:8000}"
    check_http_service "vLLM" "$vllm_url/health"

    # OpenAI API
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        check_authenticated_api "OpenAI API" "https://api.openai.com/v1/models" "Authorization: Bearer $OPENAI_API_KEY"
    else
        log_warning "OpenAI API: No API key provided"
        SERVICE_STATUS["OpenAI API"]="NO_AUTH"
    fi

    # Anthropic API
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        check_authenticated_api "Anthropic API" "https://api.anthropic.com/v1/messages" "X-API-Key: $ANTHROPIC_API_KEY"
    else
        log_warning "Anthropic API: No API key provided"
        SERVICE_STATUS["Anthropic API"]="NO_AUTH"
    fi

    # Grok/X.AI API
    if [ -n "${XAI_API_KEY:-}" ]; then
        check_authenticated_api "Grok API" "https://api.x.ai/v1/models" "Authorization: Bearer $XAI_API_KEY"
    else
        log_warning "Grok API: No API key provided"
        SERVICE_STATUS["Grok API"]="NO_AUTH"
    fi
}

# Check external APIs
check_external_apis() {
    log_info "=== Checking External APIs ==="

    # arXiv API
    check_http_service "arXiv API" "https://export.arxiv.org/api/query?search_query=cat:cs.AI&max_results=1"

    # PubMed API
    check_http_service "PubMed API" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=artificial+intelligence&retmax=1"

    # Twitter API (if key available)
    if [ -n "${TWITTER_BEARER_TOKEN:-}" ]; then
        check_authenticated_api "Twitter API" "https://api.twitter.com/2/tweets/search/recent?query=test&max_results=10" "Authorization: Bearer $TWITTER_BEARER_TOKEN"
    else
        log_warning "Twitter API: No bearer token provided"
        SERVICE_STATUS["Twitter API"]="NO_AUTH"
    fi
}

# Check containerized services
check_docker_services() {
    log_info "=== Checking Docker Services ==="

    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker not installed or not in PATH"
        SERVICE_STATUS["Docker"]="NOT_INSTALLED"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running"
        SERVICE_STATUS["Docker"]="DOWN"
        return 1
    fi

    log_success "Docker daemon is running"
    SERVICE_STATUS["Docker"]="UP"

    # Check if docker-compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        log_success "docker-compose is available"
        SERVICE_STATUS["docker-compose"]="UP"
    else
        log_warning "docker-compose not available"
        SERVICE_STATUS["docker-compose"]="NOT_INSTALLED"
    fi

    # Check for running BEAGLE services
    local running_services
    running_services=$(docker ps --format "table {{.Names}}" | grep -E "(neo4j|qdrant|postgres|redis|vllm)" || true)

    if [ -n "$running_services" ]; then
        log_info "Running BEAGLE-related containers:"
        echo "$running_services" | while read -r service; do
            log_success "  - $service"
        done
    else
        log_warning "No BEAGLE-related containers running"
    fi
}

# Check required tools
check_required_tools() {
    log_info "=== Checking Required Tools ==="

    local tools=("curl" "cargo" "rustc" "node" "npm" "python3" "pandoc")

    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version
            case "$tool" in
                "cargo"|"rustc")
                    version=$($tool --version | head -n1)
                    ;;
                "node")
                    version="Node.js $(node --version)"
                    ;;
                "npm")
                    version="npm $(npm --version)"
                    ;;
                "python3")
                    version="Python $(python3 --version | cut -d' ' -f2)"
                    ;;
                "pandoc")
                    version="Pandoc $(pandoc --version | head -n1 | cut -d' ' -f2)"
                    ;;
                *)
                    version=$($tool --version 2>/dev/null | head -n1 || echo "installed")
                    ;;
            esac
            log_success "$tool: $version"
            SERVICE_STATUS["$tool"]="UP"
        else
            log_error "$tool: Not installed"
            SERVICE_STATUS["$tool"]="NOT_INSTALLED"
        fi
    done
}

# Generate service status report
generate_report() {
    local report_file="$PROJECT_ROOT/audit/logs/service_check_${TIMESTAMP}.log"
    mkdir -p "$(dirname "$report_file")"

    log_info "Generating service status report..."

    {
        echo "# BEAGLE External Services Status Report"
        echo "Generated: $(date)"
        echo "Timestamp: $TIMESTAMP"
        echo ""
        echo "## Service Status Summary"
        echo ""

        local up_count=0
        local down_count=0
        local no_auth_count=0
        local not_installed_count=0

        for service in "${!SERVICE_STATUS[@]}"; do
            local status="${SERVICE_STATUS[$service]}"
            case "$status" in
                "UP")
                    echo "✅ $service: UP"
                    ((up_count++))
                    ;;
                "DOWN")
                    echo "❌ $service: DOWN"
                    ((down_count++))
                    ;;
                "NO_AUTH")
                    echo "🔑 $service: NO_AUTH"
                    ((no_auth_count++))
                    ;;
                "NOT_INSTALLED")
                    echo "📦 $service: NOT_INSTALLED"
                    ((not_installed_count++))
                    ;;
                *)
                    echo "❓ $service: $status"
                    ;;
            esac
        done

        echo ""
        echo "## Summary Statistics"
        echo "- Services UP: $up_count"
        echo "- Services DOWN: $down_count"
        echo "- Missing Authentication: $no_auth_count"
        echo "- Not Installed: $not_installed_count"
        echo "- Total Checked: ${#SERVICE_STATUS[@]}"

        echo ""
        echo "## Recommendations"

        if [ $down_count -gt 0 ]; then
            echo "### Critical Issues"
            echo "- $down_count services are down and need attention"
            echo "- Run \`docker-compose up -d\` to start containerized services"
        fi

        if [ $no_auth_count -gt 0 ]; then
            echo "### Authentication Issues"
            echo "- $no_auth_count services need API keys configured"
            echo "- Check .env.example for required environment variables"
        fi

        if [ $not_installed_count -gt 0 ]; then
            echo "### Missing Dependencies"
            echo "- $not_installed_count tools need to be installed"
            echo "- See docs/DEVELOPMENT_SETUP.md for installation instructions"
        fi

        if [ $up_count -eq ${#SERVICE_STATUS[@]} ]; then
            echo "### All Services Operational ✅"
            echo "All checked services are running correctly!"
        fi

    } | tee "$report_file"

    log_success "Report saved to: $report_file"
}

# Main execution
main() {
    log_info "Starting BEAGLE external services check..."
    echo "Timestamp: $TIMESTAMP"
    echo ""

    check_required_tools
    echo ""

    check_docker_services
    echo ""

    check_databases
    echo ""

    check_llm_services
    echo ""

    check_external_apis
    echo ""

    generate_report

    # Exit with appropriate code
    local down_services=0
    for status in "${SERVICE_STATUS[@]}"; do
        if [ "$status" = "DOWN" ]; then
            ((down_services++))
        fi
    done

    if [ $down_services -eq 0 ]; then
        log_success "All critical services are operational!"
        exit 0
    else
        log_error "$down_services critical services are down"
        exit 1
    fi
}

# Run main function
main "$@"
