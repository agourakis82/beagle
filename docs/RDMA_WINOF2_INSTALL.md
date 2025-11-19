# Driver RDMA para Windows (WinOF-2 NVIDIA)

**Documentação Técnica — Instalação WinOF-2 no Tower (Dell 5860)**

---

## Resumo Executivo

Este documento descreve a instalação do driver **WinOF-2 da NVIDIA** (Mellanox OFED para Windows) no tower Dell 5860 com RTX 4000 Ada e ConnectX-6 QSFP28 (100Gbps Ethernet), habilitando suporte completo a **RDMA over Ethernet (RoCE)**.

**Status Atual (2025-11-18):**
- ⚠️ **tower**: RDMA não detectado ou não configurado
- ✅ **maria**: RDMA detectado (T560, Ubuntu)

**Objetivo:** Habilitar RDMA 100Gbps entre tower (Windows) e maria (Ubuntu).

---

## Especificações do Hardware

### Tower (Dell 5860)
- **Sistema**: Windows 11 (compatível com Windows Server 2019/2022 drivers)
- **GPU**: NVIDIA RTX 4000 Ada (20GB)
- **NIC**: ConnectX-6 QSFP28 (100Gbps Ethernet)
- **Protocolo**: RDMA over Ethernet (RoCE v2)
- **IP RDMA**: 10.100.0.2

### Maria (T560, Ubuntu)
- **Sistema**: Ubuntu Linux
- **NIC**: ConnectX (100Gbps)
- **IP RDMA**: 10.100.0.1

---

## Download do Driver

### Link Oficial NVIDIA (Novembro 2025)

**URL Base:**
```
https://network.nvidia.com/products/adapter-software/ethernet/windows/winof-2/
```

**Versão LTS Recomendada:**
- **Versão**: 5.50.x ou superior (2025)
- **Suporte LTS**: 3 anos
- **Tamanho**: ~150MB
- **Arquivo**: `winof-2.*.msi` (nome varia conforme versão)

**⚠️ Nota Importante:**
A NVIDIA frequentemente atualiza os links de download direto. O **método recomendado** é baixar manualmente através da página oficial:

1. Acesse: https://network.nvidia.com/products/adapter-software/ethernet/windows/winof-2/
2. Selecione a versão LTS mais recente disponível
3. Baixe o instalador MSI para Windows Server 2019/2022 (compatível com Windows 11)

**Alternativa - Download Manual via Script:**
```powershell
# O script abre automaticamente a página de download se o URL direto falhar
.\install_winof2_rdma.ps1

# Depois de baixar manualmente, copie para o diretório temporário e execute:
.\install_winof2_rdma.ps1 -SkipDownload
```

**Verificação SHA256:**
- Verificar checksum no site NVIDIA após download.

---

## Instalação (Método Manual)

### Pré-requisitos

1. **Acesso RDP** ao tower (via MacBook)
2. **Privilégios de Administrador** no Windows
3. **Conexão de rede estável** para download
4. **Backup do sistema** (recomendado)

### Passo 1: Download do MSI

Execute no PowerShell (como usuário normal):

```powershell
# Criar diretório temporário
New-Item -ItemType Directory -Force -Path "$env:TEMP\WinOF2" | Out-Null
Set-Location "$env:TEMP\WinOF2"

# Download do driver
Invoke-WebRequest -Uri "https://network.nvidia.com/files/drivers/ethernet/windows/winof-2/winof-2.5.50.54000.msi" -OutFile "winof-2.msi"

# Verificar arquivo baixado
Get-Item "winof-2.msi" | Select-Object Name, Length, LastWriteTime
```

**Tempo estimado**: 2-5 minutos (depende da conexão)

### Passo 2: Instalação Silenciosa (Admin)

Execute no PowerShell **como Administrador**:

```powershell
# Navegar para o diretório de download
Set-Location "$env:TEMP\WinOF2"

# Instalar MSI silenciosamente (sem reiniciar automaticamente)
Start-Process msiexec.exe -ArgumentList '/i winof-2.msi /quiet /norestart /L*v install.log' -Wait -Verb RunAs

# Verificar log de instalação (últimas 20 linhas)
Get-Content install.log -Tail 20
```

**Tempo estimado**: 3-5 minutos

**Nota**: O parâmetro `/norestart` impede reinicialização automática. Você pode executar o reboot manualmente após verificar a instalação.

### Passo 3: Reinicialização Obrigatória

**Após a instalação**, o reboot é obrigatório para carregar os drivers:

```powershell
# Reiniciar imediatamente
Restart-Computer -Force

# Ou agendar reinicialização em 60 segundos (com aviso)
Shutdown /r /t 60 /c "Reiniciando para aplicar drivers WinOF-2 RDMA"
```

**Tempo estimado**: 2-3 minutos (tempo de boot)

### Passo 4: Verificação Pós-Instalação

Após o reboot, execute no PowerShell:

```powershell
# Listar adaptadores Mellanox
Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*" -or $_.InterfaceDescription -like "*Mellanox*" -or $_.InterfaceDescription -like "*ConnectX*"}

# Verificar status RDMA
Get-NetAdapterRdma | Select-Object Name, Enabled, InterfaceDescription

# Verificar driver instalado
Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*"} | Get-NetAdapterHardwareInfo | Select-Object Name, DriverVersion, DriverDate
```

**Resultado Esperado:**
- Adaptador QSFP28 aparecendo como "mlx5" ou similar
- `Enabled = True` para RDMA
- Driver version: 5.50.54000 ou superior

### Passo 5: Configuração de Rede RDMA

Verificar e configurar IP RDMA (se necessário):

```powershell
# Verificar adaptador RDMA
$rdmaAdapter = Get-NetAdapterRdma | Where-Object {$_.Enabled -eq $true} | Select-Object -First 1

# Verificar configuração IP
Get-NetIPAddress -InterfaceAlias $rdmaAdapter.Name | Where-Object {$_.AddressFamily -eq "IPv4"}

# Configurar IP RDMA manualmente (se não estiver configurado)
# New-NetIPAddress -InterfaceAlias $rdmaAdapter.Name -IPAddress "10.100.0.2" -PrefixLength 24
```

---

## Teste de Conectividade RDMA

### Teste com iperf3

#### Servidor (maria - T560, Ubuntu)

```bash
# Instalar iperf3 (se não tiver)
sudo apt-get update && sudo apt-get install -y iperf3

# Iniciar servidor iperf3 na interface RDMA
iperf3 -s -B 10.100.0.1 -p 5201
```

#### Cliente (tower - PowerShell)

```powershell
# Instalar iperf3 no Windows (via Chocolatey ou download manual)
# choco install iperf3 -y

# Testar conexão RDMA (10 segundos)
iperf3 -c 10.100.0.1 -t 10 -p 5201

# Teste bidirecional (duas conexões simultâneas)
iperf3 -c 10.100.0.1 -t 10 -d
```

**Resultado Esperado:**
- **Throughput**: ~12.5 Gbps (100Gbps link físico, ~12.5 GB/s máximo teórico)
- **Latência**: < 10µs (RDMA ultra-baixa latência)
- **Jitter**: Mínimo

**Nota**: Se não alcançar 100Gbps, verificar:
- Firmware da NIC (atualizar via `mstflint`)
- Switch/roteador RDMA configurado corretamente
- MTU size (jumbo frames habilitado)

---

## Instalação Automatizada (Script PowerShell)

Para facilitar o processo, utilize o script automatizado:

```powershell
# Executar script de instalação automática
.\scripts\infrastructure\install_winof2_rdma.ps1
```

O script realiza automaticamente:
1. ✅ Download do driver WinOF-2
2. ✅ Instalação silenciosa
3. ✅ Verificação pré-reboot
4. ✅ Agendamento de reboot (com confirmação)
5. ✅ Verificação pós-reboot (via task agendada)

**Ver documentação do script para detalhes:** `scripts/infrastructure/README_WINOF2.md`

---

## Diagnóstico e Troubleshooting

### Problema: Driver não detecta a NIC

**Solução:**
1. Verificar se a NIC está presente no Device Manager:
   ```powershell
   Get-PnpDevice | Where-Object {$_.FriendlyName -like "*Mellanox*" -or $_.FriendlyName -like "*ConnectX*"}
   ```

2. Executar "NVIDIA Ethernet Adapter Diagnostics" (incluído no MSI):
   ```powershell
   & "C:\Program Files\NVIDIA Corporation\Ethernet Adapter Diagnostics\nvdiagnostics.exe"
   ```

3. Verificar logs de instalação:
   ```powershell
   Get-Content "$env:TEMP\WinOF2\install.log" | Select-String -Pattern "error|fail" -Context 3
   ```

### Problema: RDMA não habilitado após instalação

**Solução:**
```powershell
# Habilitar RDMA manualmente
Enable-NetAdapterRdma -Name "mlx5_0"  # Ajustar nome conforme seu adaptador

# Verificar se está habilitado
Get-NetAdapterRdma | Where-Object {$_.Name -like "*mlx5*"}
```

### Problema: Atualizar firmware da NIC

**Solução:**
1. Baixar `mstflint` do NVIDIA:
   ```powershell
   # Download mstflint
   Invoke-WebRequest -Uri "https://network.nvidia.com/files/management-tools/mstflint/mstflint-4.24.0.msi" -OutFile "mstflint.msi"
   Start-Process msiexec.exe -ArgumentList '/i mstflint.msi /quiet' -Wait -Verb RunAs
   ```

2. Verificar firmware atual:
   ```powershell
   & "C:\Program Files\Mellanox\mstflint\mstflint.exe" -d mlx5_0 query
   ```

3. Baixar firmware atualizado do NVIDIA e aplicar (seguir instruções específicas do modelo)

### Problema: iperf3 não alcança 100Gbps

**Checklist:**
- ✅ RDMA habilitado em ambos os lados
- ✅ Jumbo frames configurado (MTU 9000)
- ✅ Switch/roteador suporta RoCE v2
- ✅ Sem congestionamento de rede
- ✅ Firmware da NIC atualizado

**Verificar MTU:**
```powershell
Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*"} | Select-Object Name, MTU
Set-NetAdapterAdvancedProperty -Name "mlx5_0" -DisplayName "Jumbo Packet" -DisplayValue "9000"
```

---

## Compatibilidade e Notas Importantes (2025)

### Compatibilidade
- ✅ **ConnectX-4, ConnectX-5, ConnectX-6**: Totalmente suportado
- ✅ **Windows 11**: Compatível (usa drivers Windows Server 2019/2022)
- ✅ **Windows Server 2019/2022**: Suporte oficial
- ✅ **Ethernet (RoCE)**: Suporte completo
- ✅ **InfiniBand**: Suporte via WinOF-2

### Versão LTS
- **Versão Atual**: 5.50.54000 (LTS)
- **Suporte**: 3 anos (até 2028)
- **Atualizações**: Verificar site NVIDIA trimestralmente

### Requisitos de Sistema
- **RAM**: Mínimo 16GB (recomendado 32GB+)
- **Espaço em disco**: ~500MB para instalação
- **Privilégios**: Administrador obrigatório

---

## Referências e Links Úteis

### Documentação Oficial
- **WinOF-2 Download**: https://network.nvidia.com/products/adapter-software/ethernet/windows/winof-2/
- **Documentação NVIDIA**: https://docs.nvidia.com/networking/
- **Guia RoCE**: https://docs.nvidia.com/networking/display/MLNXOFEDv570050/RDMA+over+Converged+Ethernet

### Ferramentas
- **mstflint** (Firmware management): https://network.nvidia.com/files/management-tools/mstflint/
- **NVIDIA Ethernet Adapter Diagnostics**: Incluído no MSI WinOF-2

### Suporte
- **NVIDIA Enterprise Support**: https://www.nvidia.com/en-us/support/
- **Comunidade**: NVIDIA Developer Forums

---

## Próximos Passos

Após instalação bem-sucedida:

1. **Testar link 100Gbps** com iperf3 entre tower e maria
2. **Configurar aplicações RDMA-aware** (MPI, TensorFlow, PyTorch distributed)
3. **Otimizar configurações de rede** (jumbo frames, flow control)
4. **Monitorar performance** (latência, throughput, perdas)

---

**Documento gerado em:** 2025-11-18  
**Versão:** 1.0  
**Autor:** BEAGLE Infrastructure Team  
**Status:** ✅ Ativo

