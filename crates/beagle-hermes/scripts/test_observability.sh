#!/bin/bash
# Test script for HERMES Observability Stack

set -e

echo "🧪 Testing HERMES Observability Stack"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running${NC}"
    exit 1
fi

# Create network if it doesn't exist
echo -e "${YELLOW}📡 Creating beagle-network...${NC}"
docker network create beagle-network 2>/dev/null || echo "Network already exists"
echo ""

# Start observability stack
echo -e "${YELLOW}🚀 Starting observability stack...${NC}"
cd "$(dirname "$0")/.."
docker compose -f docker-compose.observability.yml up -d

echo ""
echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
sleep 10

# Test Prometheus
echo ""
echo -e "${YELLOW}📊 Testing Prometheus...${NC}"
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    echo -e "${GREEN}✅ Prometheus is healthy${NC}"
    echo "   URL: http://localhost:9090"
else
    echo -e "${RED}❌ Prometheus is not responding${NC}"
fi

# Test Grafana
echo ""
echo -e "${YELLOW}📈 Testing Grafana...${NC}"
if curl -s http://localhost:3000/api/health > /dev/null; then
    echo -e "${GREEN}✅ Grafana is healthy${NC}"
    echo "   URL: http://localhost:3000"
    echo "   Username: admin"
    echo "   Password: hermesadmin"
else
    echo -e "${RED}❌ Grafana is not responding${NC}"
fi

# Test Loki
echo ""
echo -e "${YELLOW}📝 Testing Loki...${NC}"
if curl -s http://localhost:3100/ready > /dev/null; then
    echo -e "${GREEN}✅ Loki is healthy${NC}"
    echo "   URL: http://localhost:3100"
else
    echo -e "${RED}❌ Loki is not responding${NC}"
fi

# Check container status
echo ""
echo -e "${YELLOW}🐳 Container Status:${NC}"
docker compose -f docker-compose.observability.yml ps

# Test metrics endpoint (if HERMES API is running)
echo ""
echo -e "${YELLOW}📡 Testing metrics endpoint...${NC}"
if curl -s http://localhost:8080/metrics > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Metrics endpoint is accessible${NC}"
    echo "   Sample metrics:"
    curl -s http://localhost:8080/metrics | head -20
else
    echo -e "${YELLOW}⚠️  Metrics endpoint not available (HERMES API may not be running)${NC}"
    echo "   This is expected if the HERMES service is not started yet"
fi

echo ""
echo "======================================"
echo -e "${GREEN}✅ Observability Stack Test Complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Open Grafana: http://localhost:3000"
echo "  2. Login with admin/hermesadmin"
echo "  3. Check Prometheus: http://localhost:9090"
echo "  4. View logs in Grafana → Explore → Loki"
echo ""
echo "To stop the stack:"
echo "  docker compose -f docker-compose.observability.yml down"

