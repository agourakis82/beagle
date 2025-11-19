# install_winof2_rdma.ps1
# BEAGLE CLUSTER - WinOF-2 RDMA Driver Installation
# Instala driver WinOF-2 da NVIDIA para habilitar RDMA no tower (Dell 5860)
# Uso: .\install_winof2_rdma.ps1 (como Admin)
#
# Requisitos:
# - Executar como Administrador
# - Conexão de internet estável
# - ~500MB de espaço livre em disco

param(
    [switch]$SkipDownload,
    [switch]$SkipReboot,
    [string]$DownloadUrl = "",
    [string]$InstallDir = "$env:TEMP\WinOF2"
)

# URL da pagina de download oficial da NVIDIA (sera usado como fallback)
$NvidiaDownloadPage = "https://network.nvidia.com/products/adapter-software/ethernet/windows/winof-2/"

# Cores para output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput $Title "Cyan"
    Write-ColorOutput "========================================" "Cyan"
    Write-Host ""
}

function Write-Step {
    param(
        [int]$Step,
        [string]$Description
    )
    Write-ColorOutput "[$Step/5] $Description" "Yellow"
}

# Verificar se está rodando como Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-ColorOutput "ERRO: Este script requer privilégios de Administrador!" "Red"
    Write-ColorOutput "Execute: Start-Process powershell -Verb RunAs" "Yellow"
    exit 1
}

Write-Header "BEAGLE CLUSTER - WinOF-2 RDMA Driver Installation"
Write-ColorOutput "Instalando WinOF-2 5.50.54000 (LTS) para ConnectX-6 QSFP28 100Gbps" "Green"
Write-ColorOutput "Tower: Dell 5860 (Windows 11)" "Gray"
Write-ColorOutput ""

# Criar diretório de trabalho
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Set-Location $InstallDir

$msiFile = Join-Path $InstallDir "winof-2.msi"
$logFile = Join-Path $InstallDir "install.log"

# PASSO 1: Download
Write-Step 1 "Download do driver WinOF-2"

if ($SkipDownload -and (Test-Path $msiFile)) {
    Write-ColorOutput "  -> Pulando download (arquivo ja existe)" "Gray"
} elseif ([string]::IsNullOrEmpty($DownloadUrl)) {
    Write-ColorOutput "  -> ERRO: URL de download nao especificado!" "Red"
    Write-ColorOutput "  -> Por favor, baixe o WinOF-2 manualmente:" "Yellow"
    Write-ColorOutput "     1. Acesse: $NvidiaDownloadPage" "Gray"
    Write-ColorOutput "     2. Selecione a versao LTS mais recente (WinOF-2 5.50.x ou superior)" "Gray"
    Write-ColorOutput "     3. Baixe o instalador MSI" "Gray"
    Write-ColorOutput "     4. Copie o arquivo MSI para: $msiFile" "Gray"
    Write-ColorOutput "     5. Execute este script novamente com: -SkipDownload" "Gray"
    Write-ColorOutput "" "Gray"
    Write-ColorOutput "  Ou especifique um URL valido com: -DownloadUrl <URL>" "Yellow"
    
    # Tentar abrir a pagina no navegador
    try {
        Write-ColorOutput "  -> Abrindo pagina de download no navegador..." "Gray"
        Start-Process $NvidiaDownloadPage
    } catch {
        Write-ColorOutput "  -> Nao foi possivel abrir o navegador automaticamente" "Yellow"
    }
    
    exit 1
} else {
    Write-ColorOutput "  -> Baixando de: $DownloadUrl" "Gray"
    try {
        # Verificar se o URL responde antes de baixar
        $headRequest = Invoke-WebRequest -Uri $DownloadUrl -Method Head -UseBasicParsing -ErrorAction Stop
        Write-ColorOutput "  -> URL valido, iniciando download..." "Green"
        
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $msiFile -UseBasicParsing -ErrorAction Stop
        $fileInfo = Get-Item $msiFile
        
        if ($fileInfo.Length -lt 100MB) {
            Write-ColorOutput "  -> AVISO: Arquivo parece pequeno ($([math]::Round($fileInfo.Length / 1MB, 2)) MB)" "Yellow"
            Write-ColorOutput "  -> Arquivo esperado: ~150MB. Verifique se o download esta correto." "Yellow"
        }
        
        Write-ColorOutput "  -> Download concluido: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" "Green"
        Write-ColorOutput "  -> Arquivo: $msiFile" "Gray"
    } catch {
        Write-ColorOutput "  -> ERRO no download: $_" "Red"
        Write-ColorOutput "  -> O URL pode estar incorreto ou o arquivo nao existe mais." "Yellow"
        Write-ColorOutput "  -> Pagina oficial: $NvidiaDownloadPage" "Gray"
        Write-ColorOutput "  -> Baixe manualmente e execute com: -SkipDownload" "Yellow"
        exit 1
    }
}

# Verificar se arquivo existe
if (-not (Test-Path $msiFile)) {
    Write-ColorOutput "  -> ERRO: Arquivo MSI nao encontrado!" "Red"
    exit 1
}

# PASSO 2: Verificação pré-instalação
Write-Step 2 "Verificação de adaptadores Mellanox"

$existingAdapters = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -like "*Mellanox*" -or
    $_.InterfaceDescription -like "*ConnectX*" -or
    $_.Name -like "*mlx5*"
}

if ($existingAdapters) {
    Write-ColorOutput "  -> Adaptadores Mellanox detectados:" "Green"
    $existingAdapters | ForEach-Object {
        Write-ColorOutput "     - $($_.Name): $($_.InterfaceDescription)" "Gray"
    }
} else {
    Write-ColorOutput "  -> Nenhum adaptador Mellanox detectado (sera detectado apos instalacao)" "Yellow"
}

# Verificar RDMA atual
$rdmaStatus = Get-NetAdapterRdma -ErrorAction SilentlyContinue
if ($rdmaStatus) {
    Write-ColorOutput "  -> Status RDMA atual:" "Yellow"
    $rdmaStatus | ForEach-Object {
        $status = if ($_.Enabled) { "HABILITADO" } else { "DESABILITADO" }
        Write-ColorOutput "     - $($_.Name): $status" "Gray"
    }
} else {
    Write-ColorOutput "  -> RDMA nao configurado (sera habilitado apos instalacao)" "Yellow"
}

# PASSO 3: Instalação
Write-Step 3 "Instalação do driver WinOF-2"

Write-ColorOutput "  -> Instalando MSI silenciosamente..." "Gray"
Write-ColorOutput "  -> Log: $logFile" "Gray"

$installArgs = @(
    "/i",
    "`"$msiFile`"",
    "/quiet",
    "/norestart",
    "/L*v",
    "`"$logFile`""
)

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
    
    if ($process.ExitCode -eq 0) {
        Write-ColorOutput "  -> Instalacao concluida com sucesso!" "Green"
    } elseif ($process.ExitCode -eq 3010) {
        Write-ColorOutput "  -> Instalacao concluida (reboot necessario)" "Yellow"
        Write-ColorOutput "  -> Exit Code: $($process.ExitCode) (reboot requerido)" "Gray"
    } else {
        Write-ColorOutput "  -> AVISO: Exit Code $($process.ExitCode)" "Yellow"
        Write-ColorOutput "  -> Verifique o log: $logFile" "Gray"
    }
} catch {
        Write-ColorOutput "  -> ERRO na instalacao: $_" "Red"
        Write-ColorOutput "  -> Verifique o log: $logFile" "Red"
        exit 1
    }

# Verificar erros no log
$logErrors = Select-String -Path $logFile -Pattern "error|fail" -Context 0,2 -ErrorAction SilentlyContinue
if ($logErrors) {
    Write-ColorOutput "  -> AVISOS/ERROS encontrados no log:" "Yellow"
    $logErrors | Select-Object -First 5 | ForEach-Object {
        Write-ColorOutput "     $($_.Line)" "Gray"
    }
}

# PASSO 4: Verificação pós-instalação (antes do reboot)
Write-Step 4 "Verificação pós-instalação (pré-reboot)"

Start-Sleep -Seconds 3

$adaptersAfter = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -like "*Mellanox*" -or
    $_.InterfaceDescription -like "*ConnectX*" -or
    $_.Name -like "*mlx5*"
}

if ($adaptersAfter) {
    Write-ColorOutput "  -> Adaptadores detectados:" "Green"
    $adaptersAfter | ForEach-Object {
        $driverInfo = Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction SilentlyContinue
        Write-ColorOutput "     - $($_.Name): $($_.InterfaceDescription)" "Gray"
        if ($driverInfo) {
            Write-ColorOutput "       Driver: $($driverInfo.DriverVersion) ($($driverInfo.DriverDate))" "Gray"
        }
    }
} else {
    Write-ColorOutput "  -> Adaptadores nao detectados ainda (sera apos reboot)" "Yellow"
}

# PASSO 5: Agendamento de reboot e verificação final
Write-Step 5 "Reinicialização e verificação final"

if ($SkipReboot) {
    Write-ColorOutput "  -> Reboot pulado (--SkipReboot)" "Yellow"
    Write-ColorOutput "  -> Execute manualmente: Restart-Computer -Force" "Gray"
} else {
    Write-ColorOutput "  -> REBOOT OBRIGATORIO para carregar drivers RDMA" "Yellow"
    Write-ColorOutput "  -> Criando task agendada para verificacao pos-reboot..." "Gray"
    
    # Criar script de verificacao pos-reboot
    $verifyScript = @"
# Verificacao automatica WinOF-2 pos-reboot
`$adapters = Get-NetAdapter | Where-Object {`$_.Name -like "*mlx5*" -or `$_.InterfaceDescription -like "*Mellanox*"}
`$rdma = Get-NetAdapterRdma | Where-Object {`$_.Enabled -eq `$true}

Write-Host "=== WinOF-2 RDMA Status (Pos-Reboot) ===" -ForegroundColor Cyan
if (`$adapters) {
    Write-Host "Adaptadores Mellanox:" -ForegroundColor Green
    `$adapters | ForEach-Object { Write-Host "  - `$(`$_.Name): `$(`$_.InterfaceDescription)" }
} else {
    Write-Host "ERRO: Nenhum adaptador Mellanox detectado!" -ForegroundColor Red
}

if (`$rdma) {
    Write-Host "RDMA Habilitado:" -ForegroundColor Green
    `$rdma | ForEach-Object { Write-Host "  - `$(`$_.Name): HABILITADO" }
} else {
    Write-Host "AVISO: RDMA nao habilitado. Execute: Enable-NetAdapterRdma -Name <adapter>" -ForegroundColor Yellow
}

# Remover task agendada apos execucao
Unregister-ScheduledTask -TaskName "WinOF2_PostReboot_Verify" -Confirm:`$false -ErrorAction SilentlyContinue
"@
    
    $verifyScriptPath = Join-Path $InstallDir "verify_rdma.ps1"
    $verifyScript | Out-File -FilePath $verifyScriptPath -Encoding UTF8
    
    # Agendar task para executar no proximo logon (apos reboot)
    $taskArgument = "-ExecutionPolicy Bypass -File `"$verifyScriptPath`""
    $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $taskArgument
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    try {
        Register-ScheduledTask -TaskName "WinOF2_PostReboot_Verify" -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null
        Write-ColorOutput "  -> Task agendada criada: WinOF2_PostReboot_Verify" "Green"
    } catch {
        Write-ColorOutput "  -> AVISO: Nao foi possivel criar task agendada: $_" "Yellow"
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "  -> Reiniciando em 10 segundos..." "Yellow"
    Write-ColorOutput "  -> Pressione Ctrl+C para cancelar" "Gray"
    Start-Sleep -Seconds 10
    
    Restart-Computer -Force
}

# Resumo final (se não reiniciou)
if (-not $SkipReboot) {
    Write-ColorOutput ""
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput "INSTALAÇÃO CONCLUÍDA!" "Green"
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "Proximos passos (apos reboot):" "Yellow"
    Write-ColorOutput ""
    Write-ColorOutput "1. Verificar adaptadores RDMA:" "Cyan"
    Write-ColorOutput "   Get-NetAdapter | Where-Object {`$_.Name -like '*mlx5*'}" "Gray"
    Write-ColorOutput ""
    Write-ColorOutput "2. Verificar RDMA habilitado:" "Cyan"
    Write-ColorOutput "   Get-NetAdapterRdma | Select-Object Name, Enabled" "Gray"
    Write-ColorOutput ""
    Write-ColorOutput "3. Testar conectividade (iperf3):" "Cyan"
    Write-ColorOutput "   iperf3 -c 10.100.0.1 -t 10" "Gray"
    Write-ColorOutput ""
    Write-ColorOutput "Documentacao completa: docs/RDMA_WINOF2_INSTALL.md" "Gray"
    Write-ColorOutput ""
}

