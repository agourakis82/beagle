# BEAGLE CLUSTER CLEAN — TOWER 5860

Script PowerShell automatizado para limpeza e otimização do cluster Tower (Windows/WSL).

## 🚀 Como Usar

### Pré-requisitos

- Windows 10/11 no Tower (5860)
- PowerShell como **Administrador**
- Acesso ao drive D:\ (para mover Docker data)

### Execução

1. **Abra PowerShell como Administrador:**
   - Clique com botão direito no PowerShell
   - Selecione "Executar como administrador"

2. **Execute o script:**
   ```powershell
   cd E:\workspace\beagle-remote\scripts\infrastructure
   
   # Permite executar scripts (primeira vez)
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   
   # Roda o script
   .\clean_cluster_tower.ps1
   ```

3. **Aguarde ~15 minutos:**
   - Script para Docker
   - Move Docker data root para D:\docker
   - Limpa Windows Update cache (5-30GB)
   - Limpa logs antigos
   - Limpa arquivos temporários
   - Reinicia Docker

## ✨ O Que Faz

### 1. Configura Docker
- Para serviço Docker
- Move `data-root` de `C:\ProgramData\Docker` para `D:\docker`
- Configura logs com rotação (max 10MB, 3 arquivos)
- Reinicia Docker

### 2. Limpa Windows Update Cache
- Para serviços: `wuauserv`, `cryptSvc`, `bits`, `msiserver`
- Remove `C:\Windows\SoftwareDistribution\Download\*`
- Libera **5-30GB** tipicamente
- Reinicia serviços

### 3. Limpa Logs Antigos
- Limpa todos os logs do Event Viewer
- Remove logs do Windows com mais de 30 dias
- Libera **1-10GB** tipicamente

### 4. Limpa Arquivos Temporários
- Remove `C:\Windows\Temp\*`
- Remove `%TEMP%\*`
- Remove `%LOCALAPPDATA%\Temp\*`
- Libera **10-50GB** tipicamente

### 5. Total Liberado
- **100-200GB** no drive C:\ tipicamente

## 📊 Resultado Esperado

```
═══════════════════════════════════════════════════
CLUSTER TOWER LIMPO E OTIMIZADO!
═══════════════════════════════════════════════════

✓ Docker configurado para usar: D:\docker
✓ Windows Update cache limpo
✓ Logs antigos removidos
✓ Arquivos temporários limpos

ESPACO LIVRE NO C:\: 250 GB
ESPACO USADO NO C:\: 700 GB
```

## 🔧 Próximos Passos

### 1. RDMA (InfiniBand 100Gbps)

**Instalar driver WinOF-2 da NVIDIA (Mellanox OFED para Windows):**

**Método Automatizado (Recomendado):**
```powershell
.\scripts\infrastructure\install_winof2_rdma.ps1
```

**Método Manual:**
1. Download: https://network.nvidia.com/products/adapter-software/ethernet/windows/winof-2/
2. Versão LTS: 5.50.54000 (2025, suporte até 2028)
3. Instale o MSI como Administrador
4. Reinicie o PC (obrigatório)
5. Verifique com:
   ```powershell
   Get-NetAdapter | Where-Object { $_.Name -like "*mlx5*" -or $_.InterfaceDescription -like "*Mellanox*" }
   Get-NetAdapterRdma | Select-Object Name, Enabled
   ```

**Documentação completa:** `docs/RDMA_WINOF2_INSTALL.md`

### 2. Verificar Espaço em Disco

```powershell
Get-PSDrive C | Select-Object Used,Free
```

### 3. Reiniciar PC (Recomendado)

```powershell
Restart-Computer -Force
```

## ⚠️ Avisos

1. **Backup recomendado:** O script remove arquivos permanentemente
2. **Docker data:** Se Docker tiver containers/imagens importantes, faça backup antes
3. **Windows Update:** Cache será reconstruído na próxima atualização (normal)

## 🐛 Troubleshooting

### Docker não reinicia

```powershell
# Verifica status
Get-Service docker

# Reinicia manualmente
Restart-Service docker

# Se falhar, reinicie o Docker Desktop
```

### Erro de permissão

- Certifique-se de estar rodando como **Administrador**
- Verifique `Set-ExecutionPolicy RemoteSigned`

### Drive D:\ não existe

- Edite o script e mude `$dockerRoot = "D:\docker"` para outro drive disponível
- Exemplo: `$dockerRoot = "E:\docker"`

## 📝 Notas

- Script **não deleta** dados do Docker (apenas move configuração)
- Script **seguro** para rodar periodicamente (mensal)
- Docker data real precisa ser movido manualmente se necessário (robocopy)

---

**Desenvolvido para BEAGLE Cluster Darwin — Tower 5860** 🚀

