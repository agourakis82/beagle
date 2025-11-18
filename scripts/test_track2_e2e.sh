#!/bin/bash
# Track 2 Multi-Agent E2E Test Execution Script
# Usage: ./scripts/test_track2_e2e.sh [test_name]

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if API key is set
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "${YELLOW}⚠️  ANTHROPIC_API_KEY not set${NC}"
    echo "Set it with: export ANTHROPIC_API_KEY='your-key-here'"
    exit 1
fi

echo -e "${GREEN}🧪 Track 2 Multi-Agent E2E Test Suite${NC}"
echo "=========================================="
echo ""

# Change to project root
cd "$(dirname "$0")/.."

# Function to run a specific test
run_test() {
    local test_name=$1
    local description=$2
    
    echo -e "${GREEN}📋 Running: $description${NC}"
    echo "   Test: $test_name"
    echo ""
    
    cargo test --package beagle-hermes "$test_name" -- --nocapture 2>&1 | tee /tmp/beagle_test_${test_name}.log
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
        return 1
    fi
}

# Function to run ignored test (requires infrastructure)
run_ignored_test() {
    local test_name=$1
    local description=$2
    
    echo -e "${YELLOW}📋 Running (ignored): $description${NC}"
    echo "   Test: $test_name"
    echo ""
    
    cargo test --package beagle-hermes "$test_name" --ignored -- --nocapture 2>&1 | tee /tmp/beagle_test_${test_name}.log
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
        return 1
    fi
}

# Parse command line argument
if [ $# -eq 0 ]; then
    # Run all tests in sequence
    
    echo -e "${GREEN}Running all Track 2 tests...${NC}"
    echo ""
    
    # 1. Unit tests (no infrastructure needed)
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}PHASE 1: Unit Tests (No Infrastructure)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    run_test "test_argos_validation" "ARGOS Validation (Unit Test)"
    echo ""
    
    run_test "test_argos_citation_edge_cases" "ARGOS Citation Edge Cases"
    echo ""
    
    # 2. Tests requiring API keys (but no full infrastructure)
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}PHASE 2: API Tests (Requires ANTHROPIC_API_KEY)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    run_ignored_test "test_athena_paper_search" "ATHENA Paper Search"
    echo ""
    
    run_ignored_test "test_hermes_draft_generation" "HERMES Draft Generation"
    echo ""
    
    run_ignored_test "test_athena_paper_search_variants" "ATHENA Paper Search Variants"
    echo ""
    
    # 3. E2E tests (require full infrastructure)
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}PHASE 3: E2E Tests (Requires Full Infrastructure)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  These tests require:${NC}"
    echo "   - PostgreSQL (DATABASE_URL)"
    echo "   - Neo4j (NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)"
    echo "   - Redis (REDIS_URL)"
    echo "   - ANTHROPIC_API_KEY"
    echo ""
    
    read -p "Continue with E2E tests? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_ignored_test "test_complete_multi_agent_synthesis" "Complete Multi-Agent Synthesis"
        echo ""
        
        run_ignored_test "test_refinement_loop" "Refinement Loop"
        echo ""
        
        run_ignored_test "test_edge_case_empty_cluster" "Edge Case: Empty Cluster"
        echo ""
        
        run_ignored_test "test_edge_case_large_word_count" "Edge Case: Large Word Count"
        echo ""
        
        run_ignored_test "test_performance_parallel_sections" "Performance: Parallel Sections"
        echo ""
        
        # 4. Summary test
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}PHASE 4: Test Summary${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        run_ignored_test "run_all_tests_summary" "Complete Test Suite Summary"
        echo ""
    else
        echo -e "${YELLOW}Skipping E2E tests${NC}"
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Test execution complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
else
    # Run specific test
    TEST_NAME=$1
    case $TEST_NAME in
        "argos")
            run_test "test_argos_validation" "ARGOS Validation"
            ;;
        "athena")
            run_ignored_test "test_athena_paper_search" "ATHENA Paper Search"
            ;;
        "hermes")
            run_ignored_test "test_hermes_draft_generation" "HERMES Draft Generation"
            ;;
        "e2e")
            run_ignored_test "test_complete_multi_agent_synthesis" "Complete E2E Synthesis"
            ;;
        "summary")
            run_ignored_test "run_all_tests_summary" "Test Suite Summary"
            ;;
        *)
            echo -e "${RED}Unknown test: $TEST_NAME${NC}"
            echo "Available tests: argos, athena, hermes, e2e, summary"
            exit 1
            ;;
    esac
fi

