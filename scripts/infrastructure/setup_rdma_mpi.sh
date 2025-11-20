#!/bin/bash
# setup_rdma_mpi.sh
# BEAGLE CLUSTER - Setup MPI com suporte RDMA
# Configura OpenMPI/MPICH para usar RDMA
# Uso: ./setup_rdma_mpi.sh

set -e

echo "=== BEAGLE CLUSTER - MPI RDMA Setup ==="
echo ""

# Verificar se RDMA esta disponivel
if ! ip link show | grep -q "mtu 9000"; then
    echo "AVISO: Jumbo frames (MTU 9000) nao detectado"
    echo "Configure MTU 9000 para melhor performance RDMA"
fi

# Verificar se MPI esta instalado
if command -v mpirun &> /dev/null; then
    MPI_VERSION=$(mpirun --version | head -1)
    echo "[OK] MPI encontrado: $MPI_VERSION"
else
    echo "[INFO] MPI nao encontrado. Instalando OpenMPI..."
    
    # Detectar sistema
    if [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install -y openmpi-bin openmpi-common libopenmpi-dev
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y openmpi openmpi-devel
    else
        echo "ERRO: Sistema nao suportado. Instale MPI manualmente."
        exit 1
    fi
fi

echo ""
echo "=== Configuracao RDMA para MPI ==="
echo ""

# Criar arquivo de configuracao MPI
MPI_CONFIG_DIR="$HOME/.openmpi"
mkdir -p "$MPI_CONFIG_DIR"

cat > "$MPI_CONFIG_DIR/mca-params.conf" << 'EOF'
# OpenMPI RDMA Configuration
# Usar RDMA quando disponivel
btl = ^openib,self,vader
btl_openib_allow_ib = 1
btl_openib_device_include = mlx5_0,mlx5_1
btl_openib_warn_default_device_if_empty = 0
btl_openib_warn_no_device_if_empty = 0
EOF

echo "[OK] Configuracao MPI criada em $MPI_CONFIG_DIR/mca-params.conf"
echo ""

# Testar MPI
echo "=== Testando MPI ==="
if command -v mpirun &> /dev/null; then
    echo "Teste basico MPI:"
    mpirun --version
    
    echo ""
    echo "Para testar MPI com RDMA:"
    echo "  mpirun -np 2 --hostfile hosts.txt ./seu_programa"
    echo ""
    echo "Exemplo hosts.txt:"
    echo "  10.100.0.1 slots=4"
    echo "  10.100.0.2 slots=4"
else
    echo "[AVISO] MPI nao esta no PATH. Reinicie o terminal ou execute:"
    echo "  source /etc/profile.d/openmpi.sh"
fi

echo ""
echo "=== Setup concluido ==="



