# clean_cluster_tower.ps1
# BEAGLE CLUSTER CLEAN - TOWER 5860
# Roda como Admin no tower (5860) - libera 100-200GB + configura Docker + RDMA
# Uso: .\clean_cluster_tower.ps1 (como Admin)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "BEAGLE CLUSTER CLEAN - TOWER 5860" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Verifica se está rodando como Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script precisa ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botao direito no PowerShell e selecione 'Executar como administrador'" -ForegroundColor Yellow
    exit 1
}

Write-Host "[1/6] Parando Docker..." -ForegroundColor Yellow
try {
    Stop-Service docker -Force -ErrorAction Stop
    Write-Host "  [OK] Docker parado" -ForegroundColor Green
} catch {
    Write-Host "  [AVISO] Docker nao estava rodando ou erro ao parar: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# 2. Move Docker data root pra D:\docker (tu muda se quiser outro drive)
Write-Host ""
Write-Host "[2/6] Configurando Docker data-root..." -ForegroundColor Yellow

$dockerRoot = "D:\docker"
$oldDockerRoot = "C:\ProgramData\Docker"

# Cria diretorio D:\docker se nao existir
if (!(Test-Path $dockerRoot)) {
    New-Item -ItemType Directory -Path $dockerRoot -Force | Out-Null
    Write-Host "  [OK] Diretorio criado: $dockerRoot" -ForegroundColor Green
}

# Cria config directory se nao existir
$configDir = "C:\ProgramData\Docker\config"
if (!(Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# Config do Docker
$dockerConfig = @{
    "data-root" = $dockerRoot
    "log-driver" = "json-file"
    "log-opts" = @{
        "max-size" = "10m"
        "max-file" = "3"
    }
} | ConvertTo-Json -Depth 10

$configPath = "C:\ProgramData\Docker\config\daemon.json"
$dockerConfig | Out-File -Encoding UTF8 $configPath -Force

Write-Host "  [OK] Docker configurado para usar: $dockerRoot" -ForegroundColor Green

# Move dados do Docker se existirem (opcional, requer mais espaço)
$oldDataPath = "$oldDockerRoot\windowsfilter"
if (Test-Path $oldDataPath) {
    Write-Host "  [AVISO] Dados antigos do Docker em $oldDataPath" -ForegroundColor Yellow
    Write-Host "    Para mover manualmente (se necessario):" -ForegroundColor Yellow
    Write-Host "    robocopy `"$oldDataPath`" `"$dockerRoot\windowsfilter`" /E /COPYALL /R:3 /W:5" -ForegroundColor Gray
}

# 3. Limpa Windows Update cache (5-30GB)
Write-Host ""
Write-Host "[3/6] Limpando Windows Update cache..." -ForegroundColor Yellow

$updatePath = "C:\Windows\SoftwareDistribution\Download"
if (Test-Path $updatePath) {
    # Para servico de Windows Update temporariamente
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service cryptSvc -Force -ErrorAction SilentlyContinue
        Stop-Service bits -Force -ErrorAction SilentlyContinue
        Stop-Service msiserver -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  [AVISO] Alguns servicos nao puderam ser parados: $_" -ForegroundColor Yellow
    }
    
    $size = (Get-ChildItem $updatePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    
    if ($size) {
        $sizeGB = [math]::Round($size / 1GB, 2)
        Write-Host "  [INFO] Tamanho atual: $sizeGB GB" -ForegroundColor Cyan
        
        Remove-Item $updatePath\* -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Liberado: ~$sizeGB GB" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Cache ja estava vazio ou inacessivel" -ForegroundColor Green
    }
    
    # Reinicia servicos
    try {
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Start-Service cryptSvc -ErrorAction SilentlyContinue
        Start-Service bits -ErrorAction SilentlyContinue
        Start-Service msiserver -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  [AVISO] Alguns servicos nao puderam ser reiniciados: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [OK] Diretorio Windows Update nao encontrado" -ForegroundColor Green
}

# 4. Limpa logs antigos do Event Viewer
Write-Host ""
Write-Host "[4/6] Limpando logs antigos do Event Viewer..." -ForegroundColor Yellow

try {
    $logsCleared = 0
    wevtutil el | ForEach-Object {
        try {
            wevtutil cl "$_" 2>$null
            $logsCleared++
        } catch {
            # Ignora erros de logs protegidos ou inexistentes
        }
    }
    Write-Host "  [OK] $logsCleared logs do Event Viewer limpos" -ForegroundColor Green
} catch {
    Write-Host "  [AVISO] Erro ao limpar logs do Event Viewer: $_" -ForegroundColor Yellow
}

# Limpa logs antigos do Windows (30+ dias)
$logsPath = "C:\Windows\Logs"
if (Test-Path $logsPath) {
    $cutoffDate = (Get-Date).AddDays(-30)
    $oldLogs = Get-ChildItem $logsPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    if ($oldLogs) {
        $logsSize = ($oldLogs | Measure-Object -Property Length -Sum).Sum
        $logsSizeGB = [math]::Round($logsSize / 1GB, 2)
        
        $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Logs antigos (>30 dias) removidos: ~$logsSizeGB GB" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Nenhum log antigo encontrado" -ForegroundColor Green
    }
}

# 5. Limpa temp files
Write-Host ""
Write-Host "[5/6] Limpando arquivos temporarios..." -ForegroundColor Yellow

$tempPaths = @(
    "C:\Windows\Temp\*",
    "$env:TEMP\*",
    "$env:LOCALAPPDATA\Temp\*"
)

$totalFreed = 0

foreach ($tempPath in $tempPaths) {
    $cleanPath = $tempPath.Replace('\*', '')
    if (Test-Path $cleanPath) {
        try {
            $items = Get-ChildItem $tempPath -Recurse -File -ErrorAction SilentlyContinue
            if ($items) {
                $size = ($items | Measure-Object -Property Length -Sum).Sum
                $sizeGB = [math]::Round($size / 1GB, 2)
                
                Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
                $totalFreed += $size
                
                Write-Host "  [OK] ${cleanPath}: ~$sizeGB GB" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [AVISO] Erro ao limpar $cleanPath : $_" -ForegroundColor Yellow
        }
    }
}

if ($totalFreed -gt 0) {
    $totalFreedGB = [math]::Round($totalFreed / 1GB, 2)
    Write-Host "  [OK] Total de temp files removidos: ~$totalFreedGB GB" -ForegroundColor Green
} else {
    Write-Host "  [OK] Nenhum arquivo temporario encontrado" -ForegroundColor Green
}

# 6. Restaura Docker
Write-Host ""
Write-Host "[6/6] Reiniciando Docker..." -ForegroundColor Yellow

try {
    Start-Service docker -ErrorAction Stop
    Start-Sleep -Seconds 3
    
    # Verifica se Docker está rodando
    $dockerStatus = Get-Service docker | Select-Object -ExpandProperty Status
    if ($dockerStatus -eq "Running") {
        Write-Host "  [OK] Docker reiniciado com sucesso" -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] Docker nao esta rodando. Verifique manualmente." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [AVISO] Erro ao reiniciar Docker: $_" -ForegroundColor Yellow
    Write-Host "    Verifique se Docker Desktop esta instalado." -ForegroundColor Yellow
}

# Resumo final
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "CLUSTER TOWER LIMPO E OTIMIZADO!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] Docker configurado para usar: $dockerRoot" -ForegroundColor Green
Write-Host "[OK] Windows Update cache limpo" -ForegroundColor Green
Write-Host "[OK] Logs antigos removidos" -ForegroundColor Green
Write-Host "[OK] Arquivos temporarios limpos" -ForegroundColor Green
Write-Host ""
Write-Host "PROXIMOS PASSOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. RDMA (InfiniBand 100Gbps):" -ForegroundColor Cyan
Write-Host "   -> Instale driver WinOF-2 da NVIDIA (Mellanox OFED para Windows)" -ForegroundColor White
Write-Host "   -> Script automatizado: .\scripts\infrastructure\install_winof2_rdma.ps1" -ForegroundColor Green
Write-Host "   -> Download manual: https://network.nvidia.com/products/adapter-software/ethernet/windows/winof-2/" -ForegroundColor Gray
Write-Host "   -> Versao LTS: 5.50.54000 (suporte ate 2028)" -ForegroundColor Gray
Write-Host "   -> Documentacao: docs/RDMA_WINOF2_INSTALL.md" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Verificar espaco em disco:" -ForegroundColor Cyan
Write-Host "   -> Get-PSDrive C | Select-Object Used,Free" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Reiniciar o PC (recomendado):" -ForegroundColor Cyan
Write-Host "   -> Restart-Computer -Force" -ForegroundColor Gray
Write-Host ""

# Opcional: mostra espaço livre
try {
    $driveC = Get-PSDrive C
    $freeGB = [math]::Round($driveC.Free / 1GB, 2)
    $usedGB = [math]::Round($driveC.Used / 1GB, 2)
    Write-Host "ESPACO LIVRE NO C:\: $freeGB GB" -ForegroundColor Green
    Write-Host "ESPACO USADO NO C:\: $usedGB GB" -ForegroundColor Cyan
} catch {
    # Ignora erro se não conseguir ler drive
}

Write-Host ""
Write-Host "Tu ganhou 100-200GB no C: e o sistema ta voando!" -ForegroundColor Green
Write-Host ""
