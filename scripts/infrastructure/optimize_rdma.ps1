# optimize_rdma.ps1
# BEAGLE CLUSTER - RDMA Optimization Script
# Otimiza configuracoes RDMA para melhor performance
# Uso: .\optimize_rdma.ps1 (como Admin)

param(
    [switch]$SkipReboot,
    [int]$MTU = 9000,
    [int]$ReceiveBuffers = 2048,
    [int]$TransmitBuffers = 2048
)

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

function Write-Section {
    param([string]$Title)
    Write-ColorOutput "" "White"
    Write-ColorOutput "--- $Title ---" "Yellow"
}

# Verificar se esta rodando como Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-ColorOutput "ERRO: Este script requer privilégios de Administrador!" "Red"
    Write-ColorOutput "Execute: Start-Process powershell -Verb RunAs" "Yellow"
    exit 1
}

Write-Header "BEAGLE CLUSTER - RDMA Optimization"

# 1. Encontrar adaptadores RDMA
Write-Section "1. Detectando Adaptadores RDMA"

$rdmaAdapters = Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }

if (-not $rdmaAdapters) {
    Write-ColorOutput "[ERRO] Nenhum adaptador RDMA habilitado encontrado!" "Red"
    Write-ColorOutput "Execute primeiro: .\verify_winof2_rdma.ps1" "Yellow"
    exit 1
}

Write-ColorOutput "[OK] Adaptadores RDMA encontrados:" "Green"
$rdmaAdapters | ForEach-Object {
    Write-ColorOutput "  - $($_.Name)" "Gray"
}

# 2. Configurar MTU (Jumbo Frames)
Write-Section "2. Configurando MTU (Jumbo Frames)"

$rdmaAdapters | ForEach-Object {
    $adapterName = $_.Name
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
    
    if ($adapter) {
        $currentMTU = $adapter.NlMtu
        
        if ($currentMTU -lt $MTU) {
            Write-ColorOutput "  Configurando $adapterName: MTU $currentMTU -> $MTU" "Yellow"
            
            try {
                # Tentar configurar via propriedade avançada
                $jumboProp = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "*Jumbo*" -ErrorAction SilentlyContinue
                
                if ($jumboProp) {
                    Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $jumboProp.DisplayName -DisplayValue "$MTU" -ErrorAction Stop
                    Write-ColorOutput "    [OK] MTU configurado via propriedade avançada" "Green"
                } else {
                    # Fallback: usar Set-NetAdapter
                    Set-NetAdapter -Name $adapterName -Mtu $MTU -ErrorAction Stop
                    Write-ColorOutput "    [OK] MTU configurado via Set-NetAdapter" "Green"
                }
            } catch {
                Write-ColorOutput "    [AVISO] Nao foi possivel configurar MTU: $_" "Yellow"
                Write-ColorOutput "    Configure manualmente: Set-NetAdapter -Name `"$adapterName`" -Mtu $MTU" "Gray"
            }
        } else {
            Write-ColorOutput "  $adapterName: MTU ja esta em $currentMTU (OK)" "Green"
        }
    }
}

# 3. Configurar Buffer Sizes
Write-Section "3. Configurando Buffer Sizes"

$rdmaAdapters | ForEach-Object {
    $adapterName = $_.Name
    
    Write-ColorOutput "  Configurando $adapterName..." "Yellow"
    
    # Receive Buffers
    try {
        $rxBuffers = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "*Receive*Buffer*" -ErrorAction SilentlyContinue
        if ($rxBuffers) {
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $rxBuffers.DisplayName -DisplayValue "$ReceiveBuffers" -ErrorAction SilentlyContinue
            Write-ColorOutput "    [OK] Receive Buffers: $ReceiveBuffers" "Green"
        }
    } catch {
        Write-ColorOutput "    [AVISO] Nao foi possivel configurar Receive Buffers" "Yellow"
    }
    
    # Transmit Buffers
    try {
        $txBuffers = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "*Transmit*Buffer*" -ErrorAction SilentlyContinue
        if ($txBuffers) {
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $txBuffers.DisplayName -DisplayValue "$TransmitBuffers" -ErrorAction SilentlyContinue
            Write-ColorOutput "    [OK] Transmit Buffers: $TransmitBuffers" "Green"
        }
    } catch {
        Write-ColorOutput "    [AVISO] Nao foi possivel configurar Transmit Buffers" "Yellow"
    }
}

# 4. Configurar Flow Control
Write-Section "4. Configurando Flow Control"

$rdmaAdapters | ForEach-Object {
    $adapterName = $_.Name
    
    try {
        $flowControl = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "*Flow*Control*" -ErrorAction SilentlyContinue
        if ($flowControl) {
            # Habilitar flow control para RDMA
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $flowControl.DisplayName -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
            Write-ColorOutput "  $adapterName: Flow Control habilitado" "Green"
        }
    } catch {
        Write-ColorOutput "  $adapterName: Nao foi possivel configurar Flow Control" "Yellow"
    }
}

# 5. Configurar Interrupt Coalescing
Write-Section "5. Configurando Interrupt Coalescing"

$rdmaAdapters | ForEach-Object {
    $adapterName = $_.Name
    
    try {
        $interruptCoal = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "*Interrupt*Coalescing*" -ErrorAction SilentlyContinue
        if ($interruptCoal) {
            # Otimizar para baixa latencia
            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $interruptCoal.DisplayName -DisplayValue "Adaptive" -ErrorAction SilentlyContinue
            Write-ColorOutput "  $adapterName: Interrupt Coalescing configurado" "Green"
        }
    } catch {
        # Ignorar se nao disponivel
    }
}

# 6. Verificar configuracoes aplicadas
Write-Section "6. Verificando Configuracoes Aplicadas"

Start-Sleep -Seconds 2

$rdmaAdapters | ForEach-Object {
    $adapterName = $_.Name
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
    
    if ($adapter) {
        Write-ColorOutput "  $adapterName:" "Cyan"
        Write-ColorOutput "    MTU: $($adapter.NlMtu) bytes" "Gray"
        Write-ColorOutput "    Status: $($adapter.Status)" "Gray"
        Write-ColorOutput "    LinkSpeed: $($adapter.LinkSpeed)" "Gray"
    }
}

# 7. Resumo
Write-Header "RESUMO"

Write-ColorOutput "[OK] Otimizacoes aplicadas!" "Green"
Write-ColorOutput "" "White"
Write-ColorOutput "Configuracoes aplicadas:" "Cyan"
Write-ColorOutput "  - MTU: $MTU bytes (Jumbo Frames)" "Gray"
Write-ColorOutput "  - Receive Buffers: $ReceiveBuffers" "Gray"
Write-ColorOutput "  - Transmit Buffers: $TransmitBuffers" "Gray"
Write-ColorOutput "  - Flow Control: Habilitado" "Gray"
Write-ColorOutput "" "White"

if (-not $SkipReboot) {
    Write-ColorOutput "[AVISO] Algumas configuracoes podem requerer reinicializacao" "Yellow"
    Write-ColorOutput "        Execute: Restart-Computer -Force (se necessario)" "Gray"
} else {
    Write-ColorOutput "[INFO] Reboot pulado (--SkipReboot)" "Yellow"
}

Write-ColorOutput "" "White"
Write-ColorOutput "Proximo passo: Execute teste de performance" "Cyan"
Write-ColorOutput "  .\test_rdma_connectivity.ps1" "Gray"
Write-ColorOutput "" "White"



