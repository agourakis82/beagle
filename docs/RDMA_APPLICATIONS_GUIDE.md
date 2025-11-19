# Guia de Uso RDMA para Aplicações

**BEAGLE Cluster Darwin - RDMA Applications Guide**

---

## Visão Geral

Este documento descreve como usar RDMA (Remote Direct Memory Access) em aplicações de alto desempenho no cluster BEAGLE, incluindo MPI, TensorFlow/PyTorch distribuído, e outras aplicações HPC.

**Status RDMA:**
- ✅ **tower** (Windows): RDMA habilitado (Ethernet 6, Ethernet 7)
- ✅ **maria** (T560 Ubuntu): RDMA habilitado
- ✅ **Conectividade**: 10.100.0.1 ↔ 10.100.0.2 (~14.8 Gbps)

---

## 1. MPI (Message Passing Interface)

### Instalação

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y openmpi-bin openmpi-common libopenmpi-dev
```

**Configuração Automática:**
```bash
./scripts/infrastructure/setup_rdma_mpi.sh
```

### Uso Básico

**Arquivo de hosts (`hosts.txt`):**
```
10.100.0.1 slots=4
10.100.0.2 slots=4
```

**Executar programa MPI:**
```bash
mpirun -np 8 --hostfile hosts.txt ./seu_programa
```

**Forçar uso de RDMA:**
```bash
mpirun -np 8 --hostfile hosts.txt \
  --mca btl ^openib,self,vader \
  --mca btl_openib_device_include mlx5_0 \
  ./seu_programa
```

### Verificar se está usando RDMA

```bash
# Verificar dispositivos InfiniBand disponíveis
ibstat

# Verificar conexões RDMA
ibdev2netdev

# Monitorar tráfego RDMA
ibmon
```

---

## 2. TensorFlow Distributed Training

### Configuração

**Exemplo de cluster configuration (`cluster.json`):**
```json
{
  "cluster": {
    "worker": [
      "10.100.0.1:2222",
      "10.100.0.2:2222"
    ],
    "ps": [
      "10.100.0.1:2223"
    ]
  },
  "task": {
    "type": "worker",
    "index": 0
  }
}
```

### Usar RDMA no TensorFlow

**TensorFlow 2.x com Horovod:**
```python
import horovod.tensorflow as hvd

# Inicializar Horovod (usa RDMA automaticamente se disponível)
hvd.init()

# Configurar GPU
gpus = tf.config.experimental.list_physical_devices('GPU')
if gpus:
    tf.config.experimental.set_visible_devices(gpus[hvd.local_rank()], 'GPU')
```

**Executar:**
```bash
horovodrun -np 2 -H 10.100.0.1:1,10.100.0.2:1 python train.py
```

**TensorFlow com NCCL (NVIDIA Collective Communications):**
```python
import os
os.environ['NCCL_IB_DISABLE'] = '0'  # Habilitar InfiniBand
os.environ['NCCL_IB_HCA'] = 'mlx5_0'  # Especificar adaptador
os.environ['NCCL_SOCKET_IFNAME'] = 'eth3'  # Interface RDMA
```

---

## 3. PyTorch Distributed Training

### Configuração

**Exemplo de script de treinamento:**
```python
import torch
import torch.distributed as dist
import torch.nn as nn
from torch.nn.parallel import DistributedDataParallel as DDP

# Inicializar processo distribuído
dist.init_process_group(
    backend='nccl',  # Usa NCCL que suporta RDMA
    init_method='tcp://10.100.0.1:23456',
    world_size=2,
    rank=0  # Ajustar para cada nó
)

# Modelo
model = nn.Linear(10, 1)
model = DDP(model)

# Treinamento...
```

**Executar:**
```bash
# No nó 0 (10.100.0.1)
python -m torch.distributed.launch \
  --nproc_per_node=1 \
  --nnodes=2 \
  --node_rank=0 \
  --master_addr=10.100.0.1 \
  --master_port=23456 \
  train.py

# No nó 1 (10.100.0.2)
python -m torch.distributed.launch \
  --nproc_per_node=1 \
  --nnodes=2 \
  --node_rank=1 \
  --master_addr=10.100.0.1 \
  --master_port=23456 \
  train.py
```

**Habilitar RDMA no PyTorch:**
```bash
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=mlx5_0
export NCCL_SOCKET_IFNAME=eth3
```

---

## 4. NFS over RDMA

### Configuração do Servidor (maria)

```bash
# Instalar pacotes
sudo apt-get install -y nfs-kernel-server

# Configurar export
echo "/data *(rw,async,insecure,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports

# Habilitar RDMA no NFS
echo "rdma 20049" | sudo tee -a /etc/services
echo "rdma 20049/tcp" | sudo tee -a /etc/services

# Reiniciar NFS
sudo systemctl restart nfs-kernel-server
```

### Montar no Cliente (tower)

**Windows:**
```powershell
# Montar via NFS (requer NFS client no Windows)
mount -o nolock 10.100.0.2:/data Z:
```

**Linux/WSL:**
```bash
# Montar com RDMA
sudo mount -t nfs -o rdma,port=20049 10.100.0.2:/data /mnt/nfs-rdma
```

---

## 5. Monitoramento e Performance

### Scripts Disponíveis

**Monitorar RDMA (Windows):**
```powershell
.\scripts\infrastructure\monitor_rdma.ps1
```

**Benchmark RDMA (Linux/WSL):**
```bash
./scripts/infrastructure/rdma_benchmark.sh 10.100.0.2 5201
```

**Verificar status:**
```bash
# Linux
ibstat
ibdev2netdev
ibmon

# Windows (PowerShell)
Get-NetAdapterRdma
Get-NetAdapter | Where-Object {$_.Name -like "*Ethernet*"}
```

### Métricas Importantes

- **Throughput**: Esperado ~10-15 Gbps para link 100Gbps
- **Latência**: < 10µs para RDMA, < 1ms para TCP
- **Jitter**: Mínimo (< 1µs)
- **Packet Loss**: < 0.01%

---

## 6. Troubleshooting

### RDMA não está sendo usado

**Verificar:**
```bash
# Linux
ibstat
ibdev2netdev

# Verificar se aplicação detecta RDMA
export NCCL_DEBUG=INFO
# Executar aplicação e verificar logs
```

**Forçar uso de RDMA:**
```bash
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=mlx5_0
export NCCL_SOCKET_IFNAME=eth3
```

### Performance abaixo do esperado

1. **Verificar MTU:**
   ```bash
   ip link show | grep mtu
   # Deve ser 9000 (jumbo frames)
   ```

2. **Verificar buffer sizes:**
   ```powershell
   # Windows
   Get-NetAdapterAdvancedProperty -Name "Ethernet 6"
   ```

3. **Otimizar configurações:**
   ```powershell
   .\scripts\infrastructure\optimize_rdma.ps1
   ```

### Erros de conexão

1. **Verificar firewall:**
   ```bash
   # Linux
   sudo ufw status
   sudo ufw allow 5201/tcp
   ```

2. **Verificar conectividade:**
   ```bash
   ping 10.100.0.2
   iperf3 -c 10.100.0.2 -p 5201 -t 5
   ```

---

## 7. Best Practices

### Configuração Recomendada

1. **MTU 9000** (Jumbo Frames) - ✅ Configurado
2. **Flow Control habilitado** - ✅ Configurado
3. **Buffer sizes otimizados** - Execute `optimize_rdma.ps1`
4. **Interrupt Coalescing** - Adaptativo

### Aplicações

1. **MPI**: Use `--mca btl_openib_device_include mlx5_0`
2. **TensorFlow/PyTorch**: Configure `NCCL_IB_HCA` e `NCCL_SOCKET_IFNAME`
3. **NFS**: Use `rdma` mount option
4. **Custom**: Use bibliotecas como `libibverbs` e `librdmacm`

### Monitoramento

- Execute `monitor_rdma.ps1` durante cargas de trabalho
- Use `rdma_benchmark.sh` para baseline de performance
- Monitore latência e throughput regularmente

---

## 8. Referências

- **OpenMPI RDMA**: https://www.open-mpi.org/faq/?category=openfabrics
- **NCCL Documentation**: https://docs.nvidia.com/deeplearning/nccl/
- **TensorFlow Distributed**: https://www.tensorflow.org/guide/distributed_training
- **PyTorch Distributed**: https://pytorch.org/tutorials/intermediate/ddp_tutorial.html

---

**Documento gerado em:** 2025-11-18  
**Versão:** 1.0  
**Status:** ✅ Ativo

