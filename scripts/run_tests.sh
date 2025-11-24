#!/bin/bash
# BEAGLE v0.4 Integration Test Runner
#
# Usage:
#   ./run_tests.sh                    # Run all tests
#   ./run_tests.sh env                # Check environment only
#   ./run_tests.sh pubmed              # Run PubMed tests
#   ./run_tests.sh e2e                 # Run end-to-end test

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   BEAGLE v0.4 Integration Test Runner            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Check if .env file exists
if [ -f .env ]; then
    echo -e "${GREEN}✅ Loading .env file${NC}"
    export $(cat .env | grep -v '^#' | xargs)
else
    echo -e "${YELLOW}⚠️  No .env file found. Using system environment variables.${NC}"
fi

# Function to run a specific test
run_test() {
    local test_name=$1
    local test_pattern=$2

    echo -e "\n${GREEN}▶ Running: $test_name${NC}"
    if cargo test "$test_pattern" --test v04_integration_tests -- --ignored --nocapture; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
        return 1
    fi
}

# Main test execution
case "${1:-all}" in
    env)
        echo -e "${GREEN}Checking environment setup...${NC}"
        cargo test test_environment_setup -- --nocapture
        ;;

    pubmed)
        run_test "PubMed Search Tests" "test_pubmed"
        ;;

    arxiv)
        run_test "arXiv Search Tests" "test_arxiv"
        ;;

    neo4j)
        run_test "Neo4j Storage Tests" "test_neo4j"
        ;;

    reflexion)
        run_test "Reflexion Loop Tests" "test_reflexion"
        ;;

    router)
        run_test "LLM Router Tests" "test_router"
        ;;

    e2e)
        run_test "End-to-End Test" "test_e2e_research_query"
        ;;

    all)
        echo -e "${GREEN}Running all integration tests...${NC}"
        echo ""

        # Check environment first
        echo -e "${GREEN}Step 1/8: Environment Check${NC}"
        cargo test test_environment_setup -- --nocapture || {
            echo -e "${RED}❌ Environment check failed. Please set up required environment variables.${NC}"
            echo -e "${YELLOW}See tests/README_TESTING.md for setup instructions.${NC}"
            exit 1
        }

        # Run all tests
        echo -e "\n${GREEN}Step 2/8: Running all integration tests${NC}"
        if cargo test --test v04_integration_tests -- --ignored --nocapture; then
            echo -e "\n${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║           ✅ ALL TESTS PASSED                     ║${NC}"
            echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
        else
            echo -e "\n${RED}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║           ❌ SOME TESTS FAILED                    ║${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
            exit 1
        fi
        ;;

    quick)
        echo -e "${GREEN}Running quick smoke tests (no LLM calls)...${NC}"
        run_test "Environment Check" "test_environment_setup"
        run_test "Router Selection Logic" "test_router_provider_selection"
        ;;

    *)
        echo -e "${RED}Unknown test category: $1${NC}"
        echo ""
        echo "Usage: $0 [category]"
        echo ""
        echo "Categories:"
        echo "  env        - Check environment setup"
        echo "  pubmed     - PubMed search tests"
        echo "  arxiv      - arXiv search tests"
        echo "  neo4j      - Neo4j storage tests"
        echo "  reflexion  - Reflexion loop tests"
        echo "  router     - LLM router tests"
        echo "  e2e        - End-to-end integration test"
        echo "  quick      - Quick smoke tests (no API calls)"
        echo "  all        - Run all tests (default)"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
