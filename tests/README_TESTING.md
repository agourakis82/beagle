# BEAGLE v0.4 Integration Testing Guide

## Overview

This directory contains comprehensive integration tests for BEAGLE v0.4 features:
- ✅ PubMed/arXiv search integration
- ✅ Neo4j graph storage
- ✅ Reflexion loop with quality threshold
- ✅ Multi-provider LLM routing

## Prerequisites

### 1. Neo4j Database

**Option A: Docker (Recommended)**
```bash
docker run \
    --name neo4j-beagle \
    -p 7474:7474 -p 7687:7687 \
    -e NEO4J_AUTH=neo4j/testpassword \
    -d neo4j:5.15
```

**Option B: Local Installation**
- Download from https://neo4j.com/download/
- Start Neo4j server
- Default credentials: neo4j/neo4j (change on first login)

### 2. Environment Variables

Create a `.env` file in the repository root:

```bash
# Required
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=testpassword

# Optional (enables premium LLM providers)
ANTHROPIC_API_KEY=sk-ant-your_key_here     # Claude Direct
GITHUB_TOKEN=ghp_your_token_here            # Copilot
CURSOR_API_KEY=your_cursor_token            # Cursor AI

# Optional (increases PubMed rate limit)
NCBI_API_KEY=your_ncbi_api_key              # 10 req/s instead of 3 req/s

# Optional (enables math specialist)
DEEPSEEK_API_KEY=sk_your_deepseek_key
```

Then load it:
```bash
export $(cat .env | xargs)
```

### 3. Internet Connection
Tests require network access for:
- PubMed API (pubmed.ncbi.nlm.nih.gov)
- arXiv API (export.arxiv.org)
- LLM provider APIs

## Running Tests

### Check Environment Setup
```bash
cargo test test_environment_setup -- --nocapture
```

Expected output:
```
✅ NEO4J_URI: bolt://localhost:7687
✅ ANTHROPIC_API_KEY: sk-ant-...xxxx
✅ GITHUB_TOKEN: ghp_...xxxx
⚠️  CURSOR_API_KEY not set (Cursor unavailable)
⚠️  NCBI_API_KEY not set (3 req/s limit)

✅ Environment setup complete!
```

### Run All Integration Tests
```bash
# Run all tests (requires all services)
cargo test --test v04_integration_tests -- --ignored --nocapture

# Run specific test
cargo test test_pubmed_search_crispr -- --ignored --nocapture

# Run with specific features
cargo test --test v04_integration_tests --features "grok" -- --ignored --nocapture
```

### Run Individual Test Categories

**Paper Search Tests** (1-3):
```bash
cargo test test_pubmed -- --ignored --nocapture
cargo test test_arxiv -- --ignored --nocapture
```

**Graph Storage Tests** (4-5):
```bash
cargo test test_neo4j -- --ignored --nocapture
```

**Reflexion Loop Tests** (6-7):
```bash
cargo test test_reflexion -- --ignored --nocapture
```

**LLM Router Tests** (8-10):
```bash
cargo test test_router -- --ignored --nocapture
```

**End-to-End Test** (11):
```bash
cargo test test_e2e_research_query -- --ignored --nocapture
```

## Test Suite Overview

| Test # | Name | What It Tests | Duration | Dependencies |
|--------|------|---------------|----------|--------------|
| 1 | `test_pubmed_search_crispr` | PubMed API search | ~3s | Internet |
| 2 | `test_pubmed_rate_limiting` | Rate limiter (3-10 req/s) | ~5s | Internet |
| 3 | `test_arxiv_search_quantum` | arXiv API search | ~3s | Internet |
| 4 | `test_neo4j_paper_storage` | Graph storage (MERGE) | ~2s | Neo4j |
| 5 | `test_neo4j_hybrid_retrieval` | Vector + graph search | ~3s | Neo4j |
| 6 | `test_reflexion_loop_low_quality` | Refinement triggers | ~20s | LLM API |
| 7 | `test_reflexion_loop_high_quality` | Fast path (no refinement) | ~10s | LLM API |
| 8 | `test_router_provider_selection` | Router logic | <1s | None |
| 9 | `test_router_copilot_client` | Copilot API | ~3s | GITHUB_TOKEN |
| 10 | `test_router_claude_direct_client` | Claude API | ~3s | ANTHROPIC_API_KEY |
| 11 | `test_e2e_research_query` | Full workflow | ~30s | All |

## Expected Results

### Success Criteria

**Test 1: PubMed Search**
```
✅ Found 10 papers in 2.3s
✅ First paper: CRISPR-Cas9 off-target activity profiling...
```

**Test 4: Neo4j Storage**
```
✅ Stored paper with ID: 4:abc123:456
✅ Duplicate prevention working
```

**Test 6: Reflexion Loop**
```
✅ Reflexion loop completed:
   - Iterations: 2
   - Quality: 0.82
   - Time: 18.5s
```

**Test 11: End-to-End**
```
✅ E2E test passed:
   - Answer length: 1842 chars
   - Papers cited: 8
   - Quality: 0.79
   - Refinements: 1
   - Total time: 24.3s
```

### Common Issues

**Issue**: `NEO4J_URI not set`
**Fix**: Export environment variable or start Neo4j

**Issue**: `Connection refused (os error 111)`
**Fix**: Ensure Neo4j is running: `docker ps` or `systemctl status neo4j`

**Issue**: `NCBI rate limit exceeded`
**Fix**: Add `NCBI_API_KEY` or wait 60 seconds between test runs

**Issue**: `ANTHROPIC_API_KEY not set`
**Fix**: Tests 6, 7, 10, 11 will skip if no LLM key available

## Continuous Integration

### GitHub Actions Workflow

Create `.github/workflows/v04_tests.yml`:

```yaml
name: BEAGLE v0.4 Integration Tests

on:
  push:
    branches: [main, develop]
  pull_request:

env:
  RUST_BACKTRACE: 1
  NEO4J_URI: bolt://localhost:7687
  NEO4J_USER: neo4j
  NEO4J_PASSWORD: test_password

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      neo4j:
        image: neo4j:5.15
        env:
          NEO4J_AUTH: neo4j/test_password
        ports:
          - 7687:7687
        options: >-
          --health-cmd "cypher-shell 'RETURN 1'"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      
      - name: Cache cargo
        uses: actions/cache@v3
        with:
          path: |
            ~/.cargo/bin/
            ~/.cargo/registry/index/
            ~/.cargo/registry/cache/
            ~/.cargo/git/db/
            target/
          key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
      
      - name: Run tests
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GH_COPILOT_TOKEN }}
        run: |
          cargo test --test v04_integration_tests -- --ignored --nocapture
```

## Performance Benchmarks

After running tests, document baseline performance:

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| PubMed search latency | <5s | TBD | ⏳ |
| arXiv search latency | <5s | TBD | ⏳ |
| Neo4j write (1 paper) | <1s | TBD | ⏳ |
| Reflexion (0 refinements) | <15s | TBD | ⏳ |
| Reflexion (1-2 refinements) | <30s | TBD | ⏳ |
| E2E query | <60s | TBD | ⏳ |

## Debugging

### Enable Trace Logging
```bash
RUST_LOG=debug cargo test test_e2e_research_query -- --ignored --nocapture
```

### Check Neo4j Contents
```bash
# Via cypher-shell
docker exec -it neo4j-beagle cypher-shell -u neo4j -p testpassword

# Query all papers
MATCH (p:Paper) RETURN p LIMIT 10;

# Check indexes
SHOW INDEXES;
```

### Monitor API Rate Limits
```bash
# Watch network traffic
tcpdump -i any -n -s 0 -w /tmp/beagle_test.pcap host pubmed.ncbi.nlm.nih.gov

# Analyze with Wireshark
wireshark /tmp/beagle_test.pcap
```

## Next Steps

After all tests pass:
1. Document actual performance metrics
2. Set up CI/CD pipeline
3. Create baseline for regression testing
4. Add Prometheus metrics
5. Deploy to staging environment

## Support

If tests fail, please report with:
- Test name and error message
- Environment details (`rustc --version`, `neo4j --version`)
- Relevant logs (`RUST_LOG=debug`)
- Network conditions (firewall, proxy, etc.)
