#!/bin/bash
set -euo pipefail

echo "=== BEAGLE gRPC vs REST Benchmarks ==="
echo

echo "Starting servers..."
cargo run --package beagle-grpc --example server >/tmp/beagle-grpc-server.log 2>&1 &
GRPC_PID=$!
PORT=3000 cargo run --package beagle-server >/tmp/beagle-rest-server.log 2>&1 &
REST_PID=$!

trap 'kill $GRPC_PID $REST_PID >/dev/null 2>&1 || true' EXIT

sleep 3

echo
echo "=== gRPC Benchmarks ==="
cargo bench --package beagle-grpc

echo
echo "=== REST Benchmarks ==="
cargo bench --package beagle-server

kill $GRPC_PID $REST_PID >/dev/null 2>&1 || true

echo
echo "=== Benchmark Complete ==="
echo "Results saved to target/criterion/"
echo
echo "To view HTML report:"
echo "open target/criterion/report/index.html"
echo

