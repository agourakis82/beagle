#!/bin/bash
# Beagle Hypergraph Benchmarking Script

set -euo pipefail

echo "Running Criterion benchmarks..."
echo "================================"

# Run benchmarks and save baseline
cargo bench --bench hypergraph_benchmarks -- --save-baseline main

echo ""
echo "Benchmarks complete!"
echo "Results saved to: target/criterion/"
echo ""
echo "View HTML report:"
echo "  open target/criterion/report/index.html"
echo ""
echo "Compare against baseline later:"
echo "  cargo bench --bench hypergraph_benchmarks -- --baseline main"








