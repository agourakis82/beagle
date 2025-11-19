# Infrastructure Scripts

Scripts para configuração e gerenciamento de infraestrutura do Beagle.

## vLLM Server (T560)

### Scripts Disponíveis

1. **`setup_vllm_t560.sh`** - Setup completo do servidor vLLM
   - Instala CUDA, Python, vLLM
   - Baixa modelo Qwen 2.5 32B GPTQ
   - Configura ambiente completo

2. **`start_vllm.sh`** - Inicia servidor vLLM
   - Ativa virtual environment
   - Inicia servidor na porta 8001
   - Suporta variáveis de ambiente

3. **`test_vllm.sh`** - Testa servidor vLLM
   - Verifica saúde do servidor
   - Testa endpoints de API
   - Valida completions e chat

4. **`download_qwen32b.sh`** - Download do modelo Qwen 32B GPTQ
   - Baixa em sessão tmux separada (não interfere com servidor)
   - ~18GB, 20-30 minutos
   - Roda em background

5. **`swap_to_qwen.sh`** - Troca servidor: Mistral-7B → Qwen 32B
   - Para servidor atual
   - Inicia com Qwen 32B
   - Testa automaticamente

### Uso Rápido (Máquina Local T560)

```bash
# 1. Setup (uma vez) - executar LOCALMENTE na T560
./setup_vllm_t560.sh

# 2. Iniciar servidor
tmux new -s vllm
~/start_vllm.sh
# Ctrl+B, D para detach

# 3. Testar (localhost)
./test_vllm.sh

# Ou testar de outro host na rede:
./test_vllm.sh http://<IP_DA_T560>:8001
```

### Download e Swap para Qwen 32B

```bash
# 1. Download do modelo (em background, não interfere com servidor)
./download_qwen32b.sh

# Ver progresso:
tmux attach -t download

# 2. Quando terminar, fazer swap
./swap_to_qwen.sh

# 3. Testar novo servidor
./test_vllm.sh http://localhost:8000
```

### Documentação Completa

Ver: [`docs/VLLM_SERVER_SETUP.md`](../../docs/VLLM_SERVER_SETUP.md)

## RDMA WinOF-2 (Tower - Windows)

### Scripts Disponíveis

1. **`install_winof2_rdma.ps1`** - Instalação automatizada do driver WinOF-2
   - Baixa WinOF-2 5.50.54000 (LTS) da NVIDIA
   - Instala driver silenciosamente
   - Habilita RDMA para ConnectX-6 QSFP28 (100Gbps)
   - Configura verificação pós-reboot automática

2. **`clean_cluster_tower.ps1`** - Limpeza e otimização do tower
   - Remove arquivos temporários
   - Limpa cache Docker
   - Configura RDMA (referência)

### Uso Rápido (Tower - Windows)

```powershell
# 1. Abrir PowerShell como Administrador
Start-Process powershell -Verb RunAs

# 2. Navegar para o diretório
cd E:\workspace\beagle-remote\scripts\infrastructure

# 3. Executar instalação automatizada
.\install_winof2_rdma.ps1

# 4. Após reboot, verificar RDMA
Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*"}
Get-NetAdapterRdma | Select-Object Name, Enabled
```

### Opções Avançadas

```powershell
# Pular download (usar arquivo existente)
.\install_winof2_rdma.ps1 -SkipDownload

# Pular reboot (instalação manual)
.\install_winof2_rdma.ps1 -SkipReboot

# URL customizada
.\install_winof2_rdma.ps1 -DownloadUrl "https://custom-url.com/winof-2.msi"
```

### Teste de Conectividade

```powershell
# Servidor (maria - T560 Ubuntu)
iperf3 -s -B 10.100.0.1 -p 5201

# Cliente (tower - PowerShell)
iperf3 -c 10.100.0.1 -t 10 -p 5201
```

### Scripts Adicionais

3. **`verify_winof2_rdma.ps1`** - Verificação completa do WinOF-2
   - Verifica adaptadores, drivers, RDMA status
   - Mostra configurações de rede (IP, MTU)
   - Resumo final com status

4. **`optimize_rdma.ps1`** - Otimização de configurações RDMA
   - Configura MTU 9000 (Jumbo Frames)
   - Ajusta buffer sizes
   - Habilita Flow Control
   - Otimiza Interrupt Coalescing

5. **`monitor_rdma.ps1`** - Monitoramento de performance RDMA
   - Monitora throughput em tempo real
   - Estatísticas de rede
   - Métricas de adaptadores RDMA

6. **`test_rdma_connectivity.ps1`** - Teste de conectividade RDMA
   - Testa throughput com iperf3
   - Análise automática de resultados
   - Validação de performance

### Scripts Linux/WSL

- **`test_rdma_connectivity.sh`** - Teste de conectividade (WSL/Linux)
- **`test_rdma_quick.sh`** - Teste rápido sem interação
- **`rdma_benchmark.sh`** - Benchmark completo (múltiplos testes)
- **`setup_rdma_mpi.sh`** - Setup MPI com suporte RDMA

### Documentação Completa

- **Guia de Instalação**: [`docs/RDMA_WINOF2_INSTALL.md`](../../docs/RDMA_WINOF2_INSTALL.md)
- **Guia de Aplicações**: [`docs/RDMA_APPLICATIONS_GUIDE.md`](../../docs/RDMA_APPLICATIONS_GUIDE.md)
- **Guia de Uso do Script**: [`README_WINOF2.md`](README_WINOF2.md)
- **Limpeza do Tower**: [`README_CLUSTER_CLEAN.md`](README_CLUSTER_CLEAN.md)

## Outros Scripts

- `darwin_infrastructure_audit.py` - Auditoria do cluster Darwin
- `deep_cluster_audit.sh` - Auditoria profunda do cluster
- `init-db.sql` - Inicialização do banco de dados

