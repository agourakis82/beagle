#!/bin/bash
# rdma_benchmark.sh
# BEAGLE CLUSTER - RDMA Comprehensive Benchmark
# Testa performance RDMA com diferentes configuracoes
# Uso: ./rdma_benchmark.sh [server_ip] [port]

set -e

SERVER_IP="${1:-10.100.0.2}"
PORT="${2:-5201}"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== BEAGLE CLUSTER - RDMA Comprehensive Benchmark ===${NC}"
echo ""

# Verificar iperf3
if ! command -v iperf3 &> /dev/null; then
    echo "ERRO: iperf3 nao encontrado"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} iperf3 encontrado"
echo ""
echo "Servidor: $SERVER_IP:$PORT"
echo "Certifique-se de que o servidor esta rodando:"
echo "  iperf3 -s -B $SERVER_IP -p $PORT"
echo ""
read -p "Pressione Enter quando o servidor estiver pronto..."

echo ""
echo -e "${CYAN}=== Teste 1: Throughput Unidirecional (10s) ===${NC}"
iperf3 -c "$SERVER_IP" -p "$PORT" -t 10 -f m

echo ""
echo -e "${CYAN}=== Teste 2: Throughput Bidirecional (10s) ===${NC}"
iperf3 -c "$SERVER_IP" -p "$PORT" -t 10 -d -f m

echo ""
echo -e "${CYAN}=== Teste 3: Latencia (100 pacotes) ===${NC}"
iperf3 -c "$SERVER_IP" -p "$PORT" -u -b 1M -l 64 -t 5 -f m

echo ""
echo -e "${CYAN}=== Teste 4: Multiple Streams (4 conexoes, 10s) ===${NC}"
iperf3 -c "$SERVER_IP" -p "$PORT" -P 4 -t 10 -f m

echo ""
echo -e "${CYAN}=== Teste 5: Window Size Otimizado (10s) ===${NC}"
iperf3 -c "$SERVER_IP" -p "$PORT" -t 10 -w 1M -f m

echo ""
echo -e "${GREEN}=== Benchmark concluido ===${NC}"

