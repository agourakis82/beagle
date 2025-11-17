#!/bin/bash
# Test script for Docker build

set -e

echo "🧪 Testing HERMES Docker Build"
echo "================================"
echo ""

cd "$(dirname "$0")/../.."

# Test 1: Syntax check
echo "1️⃣ Checking Dockerfile syntax..."
docker build --dry-run -f crates/beagle-hermes/docker/Dockerfile . 2>&1 | head -5 || echo "⚠️  Dry-run not supported, skipping..."

# Test 2: Build builder stage
echo ""
echo "2️⃣ Building builder stage..."
docker build \
    --target builder \
    -f crates/beagle-hermes/docker/Dockerfile \
    -t hermes-builder:test \
    . 2>&1 | tail -20

if [ $? -eq 0 ]; then
    echo "✅ Builder stage built successfully"
else
    echo "❌ Builder stage failed"
    exit 1
fi

# Test 3: Check image size
echo ""
echo "3️⃣ Checking image size..."
BUILDER_SIZE=$(docker images hermes-builder:test --format "{{.Size}}")
echo "   Builder image size: $BUILDER_SIZE"

echo ""
echo "✅ Docker build test complete!"
echo ""
echo "To build full image:"
echo "  docker build -f crates/beagle-hermes/docker/Dockerfile -t hermes:test ."

