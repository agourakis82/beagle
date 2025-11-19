#!/bin/bash
# test_rdma_connectivity.sh
# BEAGLE CLUSTER - RDMA Connectivity Test (WSL/Linux)
# Testa conectividade RDMA entre tower e maria usando iperf3
# Uso: ./test_rdma_connectivity.sh [server_ip] [port]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Parametros
SERVER_IP="${1:-10.100.0.1}"
PORT="${2:-5201}"
DURATION="${3:-10}"

# Funcoes de output
print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${YELLOW}--- $1 ---${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_info() {
    echo -e "${GRAY}$1${NC}"
}

print_header "BEAGLE CLUSTER - RDMA Connectivity Test (WSL)"

# Verificar se iperf3 esta instalado
if ! command -v iperf3 &> /dev/null; then
    print_error "iperf3 nao encontrado!"
    echo ""
    print_warn "Instale iperf3:"
    print_info "  sudo apt-get update && sudo apt-get install -y iperf3"
    exit 1
fi

IPERF3_PATH=$(which iperf3)
print_ok "iperf3 encontrado: $IPERF3_PATH"
echo ""

# Verificar se estamos no WSL
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    print_info "Ambiente: WSL (Windows Subsystem for Linux)"
    print_warn "RDMA pode nao estar disponivel diretamente no WSL"
    print_info "O teste usara a rede do Windows host"
    echo ""
fi

# Verificar adaptadores de rede
print_section "Adaptadores de Rede"
print_info "Adaptadores disponiveis:"
ip -4 addr show | grep -E "^[0-9]+:|inet " | while read line; do
    if [[ $line =~ ^[0-9]+: ]]; then
        echo -e "${GRAY}  $line${NC}"
    else
        echo -e "${GRAY}    $line${NC}"
    fi
done

echo ""
print_info "Configuracao do teste:"
print_info "  Servidor: $SERVER_IP"
print_info "  Porta: $PORT"
print_info "  Duracao: $DURATION segundos"
echo ""

# Verificar conectividade basica
print_section "Verificacao de Conectividade"
print_info "Testando ping para $SERVER_IP..."

if ping -c 2 -W 2 "$SERVER_IP" &> /dev/null; then
    print_ok "Ping bem-sucedido"
else
    print_warn "Ping falhou - servidor pode estar offline ou firewall bloqueando"
    print_info "Continuando com teste iperf3 mesmo assim..."
fi

echo ""
print_section "INSTRUCOES"
print_info "1. No servidor (maria - T560 Ubuntu), execute:"
echo -e "${GRAY}   iperf3 -s -B $SERVER_IP -p $PORT${NC}"
echo ""
print_info "2. Apos o servidor estar rodando, pressione Enter para iniciar o teste..."
echo ""

read -p "Pressione Enter quando o servidor estiver pronto..."

# Executar teste
echo ""
print_section "Teste de Throughput RDMA"
print_info "Iniciando teste... Aguarde $DURATION segundos..."
echo ""

# Executar iperf3 e capturar output
if iperf3 -c "$SERVER_IP" -p "$PORT" -t "$DURATION" -f m 2>&1 | tee /tmp/iperf3_result.txt; then
    echo ""
    print_section "RESULTADO DO TESTE"
    
    # Analisar resultado
    RESULT_FILE="/tmp/iperf3_result.txt"
    
    if grep -q "sender\|receiver" "$RESULT_FILE"; then
        print_ok "Teste concluido com sucesso!"
        echo ""
        
        # Extrair throughput
        THROUGHPUT=$(grep -E "sender|receiver" "$RESULT_FILE" | grep -oE "[0-9]+\.[0-9]+\s*(Gbits|Mbits|Kbits)/sec" | head -1)
        
        if [ -n "$THROUGHPUT" ]; then
            print_section "ANALISE"
            print_info "Throughput detectado: $THROUGHPUT"
            echo ""
            
            if echo "$THROUGHPUT" | grep -q "Gbits"; then
                VALUE=$(echo "$THROUGHPUT" | grep -oE "[0-9]+\.[0-9]+" | head -1)
                if (( $(echo "$VALUE >= 10" | bc -l) )); then
                    print_ok "Throughput >= 10 Gbps - RDMA funcionando otimamente!"
                elif (( $(echo "$VALUE >= 1" | bc -l) )); then
                    print_ok "Throughput >= 1 Gbps - RDMA funcionando"
                else
                    print_warn "Throughput < 1 Gbps - verifique configuracao"
                fi
            else
                print_warn "Throughput em Mbits/Kbits - pode nao estar usando RDMA"
            fi
        else
            print_warn "Nao foi possivel extrair throughput do resultado"
        fi
    else
        print_error "Teste falhou ou resultado invalido"
        print_info "Verifique se o servidor iperf3 esta rodando"
    fi
    
    # Limpar arquivo temporario
    rm -f "$RESULT_FILE"
else
    print_error "Falha ao executar teste"
    echo ""
    print_warn "Verifique:"
    print_info "  1. Servidor iperf3 esta rodando no maria"
    print_info "  2. Firewall permite conexao na porta $PORT"
    print_info "  3. IP $SERVER_IP esta correto"
    exit 1
fi

echo ""
print_ok "Teste concluido!"

