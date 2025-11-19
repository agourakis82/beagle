#!/bin/bash
# test_rdma_quick.sh
# Teste rapido de RDMA (sem interacao)
# Uso: ./test_rdma_quick.sh [server_ip] [port] [duration]

SERVER_IP="${1:-10.100.0.1}"
PORT="${2:-5201}"
DURATION="${3:-10}"

echo "=== Teste RDMA - $SERVER_IP:$PORT (${DURATION}s) ==="
echo ""

# Verificar se servidor esta respondendo
if ! ping -c 1 -W 2 "$SERVER_IP" &> /dev/null; then
    echo "ERRO: Servidor $SERVER_IP nao responde ao ping"
    echo "Certifique-se de que o servidor iperf3 esta rodando:"
    echo "  iperf3 -s -B $SERVER_IP -p $PORT"
    exit 1
fi

echo "Servidor detectado. Iniciando teste..."
echo ""

# Executar teste
iperf3 -c "$SERVER_IP" -p "$PORT" -t "$DURATION" -f m

echo ""
echo "=== Teste concluido ==="

