# 📖 Guia de Uso - WinOF-2 RDMA Installation Script

## Visão Geral

Script PowerShell automatizado para instalação do driver **WinOF-2 da NVIDIA** no tower (Dell 5860), habilitando suporte completo a **RDMA over Ethernet (RoCE)** para o ConnectX-6 QSFP28 (100Gbps).

**Documentação completa:** `docs/RDMA_WINOF2_INSTALL.md`

---

## Pré-requisitos

1. ✅ **Windows 11** no tower (compatível com drivers Windows Server 2019/2022)
2. ✅ **Privilégios de Administrador** (obrigatório)
3. ✅ **Conexão de internet** estável (~150MB download)
4. ✅ **Espaço em disco**: ~500MB livre

---

## Uso Básico

### Instalação Completa (Recomendado)

```powershell
# Abrir PowerShell como Administrador
Start-Process powershell -Verb RunAs

# Navegar para o diretório do script
cd E:\workspace\beagle-remote\scripts\infrastructure

# Executar instalação
.\install_winof2_rdma.ps1
```

**O que o script faz:**
1. ✅ Baixa WinOF-2 5.50.54000 (LTS) da NVIDIA
2. ✅ Verifica adaptadores Mellanox existentes
3. ✅ Instala driver silenciosamente
4. ✅ Verifica instalação pré-reboot
5. ✅ Agenda task para verificação pós-reboot
6. ✅ Reinicia o sistema automaticamente

**Tempo total**: ~10-15 minutos (incluindo reboot)

---

## Opções Avançadas

### Pular Download (usar arquivo existente)

Se você já baixou o MSI manualmente:

```powershell
.\install_winof2_rdma.ps1 -SkipDownload
```

### Pular Reboot (instalação manual)

Para instalar sem reiniciar automaticamente:

```powershell
.\install_winof2_rdma.ps1 -SkipReboot
```

Depois, execute manualmente:
```powershell
Restart-Computer -Force
```

### Usar URL de Download Customizada

Para testar versão diferente ou mirror alternativo:

```powershell
.\install_winof2_rdma.ps1 -DownloadUrl "https://custom-url.com/winof-2.msi"
```

---

## Verificação Pós-Instalação

### Após Reboot Automático

O script cria uma **task agendada** que executa automaticamente no próximo logon, mostrando o status do RDMA.

**Verificar manualmente:**

```powershell
# Listar adaptadores Mellanox
Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*" -or $_.InterfaceDescription -like "*Mellanox*"}

# Verificar RDMA habilitado
Get-NetAdapterRdma | Select-Object Name, Enabled, InterfaceDescription

# Verificar versão do driver
Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*"} | Get-NetAdapterHardwareInfo | Select-Object Name, DriverVersion
```

**Resultado esperado:**
- ✅ Adaptador aparecendo como "mlx5_0" ou similar
- ✅ `Enabled = True` para RDMA
- ✅ Driver version: 5.50.54000 ou superior

---

## Teste de Conectividade

### Servidor (maria - T560 Ubuntu)

```bash
# Iniciar servidor iperf3
iperf3 -s -B 10.100.0.1 -p 5201
```

### Cliente (tower - PowerShell)

```powershell
# Instalar iperf3 (se não tiver)
choco install iperf3 -y

# Testar conexão RDMA
iperf3 -c 10.100.0.1 -t 10 -p 5201
```

**Resultado esperado:**
- Throughput: ~12.5 Gbps (100Gbps link)
- Latência: < 10µs

---

## Troubleshooting

### Erro: "Este script requer privilégios de Administrador"

**Solução:**
```powershell
# Abrir PowerShell como Admin
Start-Process powershell -Verb RunAs

# Ou executar diretamente
Start-Process .\install_winof2_rdma.ps1 -Verb RunAs
```

### Erro: Download falha

**Solução:**
1. Verificar conexão de internet
2. Tentar download manual:
   ```powershell
   Invoke-WebRequest -Uri "https://network.nvidia.com/files/drivers/ethernet/windows/winof-2/winof-2.5.50.54000.msi" -OutFile "$env:TEMP\WinOF2\winof-2.msi"
   ```
3. Executar com `-SkipDownload`

### Erro: Instalação falha (Exit Code != 0)

**Solução:**
1. Verificar log de instalação:
   ```powershell
   Get-Content "$env:TEMP\WinOF2\install.log" | Select-String -Pattern "error|fail" -Context 3
   ```
2. Verificar se MSI está corrompido (re-baixar)
3. Executar MSI manualmente:
   ```powershell
   msiexec.exe /i "$env:TEMP\WinOF2\winof-2.msi" /L*v install_manual.log
   ```

### RDMA não habilitado após reboot

**Solução:**
```powershell
# Habilitar RDMA manualmente
$adapter = Get-NetAdapter | Where-Object {$_.Name -like "*mlx5*"} | Select-Object -First 1
Enable-NetAdapterRdma -Name $adapter.Name

# Verificar
Get-NetAdapterRdma | Where-Object {$_.Name -like "*mlx5*"}
```

### Adaptador não detectado

**Solução:**
1. Verificar Device Manager:
   ```powershell
   Get-PnpDevice | Where-Object {$_.FriendlyName -like "*Mellanox*"}
   ```
2. Executar diagnóstico NVIDIA:
   ```powershell
   & "C:\Program Files\NVIDIA Corporation\Ethernet Adapter Diagnostics\nvdiagnostics.exe"
   ```
3. Verificar se NIC está fisicamente conectada

---

## Estrutura de Arquivos

Após execução, o script cria:

```
$env:TEMP\WinOF2\
├── winof-2.msi          # Driver baixado (~150MB)
├── install.log          # Log de instalação MSI
└── verify_rdma.ps1      # Script de verificação pós-reboot
```

**Limpeza manual:**
```powershell
Remove-Item "$env:TEMP\WinOF2" -Recurse -Force
```

---

## Logs e Debugging

### Log de Instalação MSI

```powershell
# Ver últimas 50 linhas
Get-Content "$env:TEMP\WinOF2\install.log" -Tail 50

# Buscar erros
Get-Content "$env:TEMP\WinOF2\install.log" | Select-String -Pattern "error|fail|warning" -Context 2
```

### Task Agendada (Verificação Pós-Reboot)

```powershell
# Ver task criada
Get-ScheduledTask -TaskName "WinOF2_PostReboot_Verify"

# Executar manualmente
Start-ScheduledTask -TaskName "WinOF2_PostReboot_Verify"

# Remover task (após verificação)
Unregister-ScheduledTask -TaskName "WinOF2_PostReboot_Verify" -Confirm:$false
```

---

## Próximos Passos

Após instalação bem-sucedida:

1. ✅ **Testar link 100Gbps** com iperf3
2. ✅ **Configurar aplicações RDMA-aware** (MPI, distributed training)
3. ✅ **Otimizar configurações** (jumbo frames, MTU 9000)
4. ✅ **Monitorar performance** (latência, throughput)

**Documentação completa:** `docs/RDMA_WINOF2_INSTALL.md`

---

**Script desenvolvido para:** BEAGLE Cluster Darwin — Tower 5860  
**Versão:** 1.0  
**Data:** 2025-11-18

